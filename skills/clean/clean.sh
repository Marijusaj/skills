#!/usr/bin/env bash
# clean.sh: find (and with --apply, retire) everything finished work left
# behind: idle Claude sessions, dev servers, walk browsers, orphaned helper
# processes, merged worktrees, merged branches, a main checkout parked on an old
# branch.
#
#   clean.sh                 survey only: changes nothing
#   clean.sh --apply         retire every ACT row, in a safe order
#   clean.sh --all [...]     the whole machine and every git repo under
#                            $CLEAN_REPOS (default ~/Code)
#   clean.sh --repos-only    skip sessions/servers/browsers/orphans (tests)
#   clean.sh --as <pid>      survey what /clean would do inside session <pid>
#
# Two scopes:
#   default (/clean)      the session running this script and the sessions it
#                         launched: their processes, their worktrees, their
#                         branches and PRs. Other sessions' work is invisible.
#   --all   (/clean-all)  hunt for strays anywhere: every session, server,
#                         browser and orphan on the machine, every $CLEAN_REPOS repo.
#
# Nothing records which session launched which. A session launches another
# only by running `claude --bg` in its Bash tool, so a "child" is a live session
# whose id is in the output of such a call in the parent's transcript. (Merely
# mentioning an id (a listing, a `claude agents`) does not count: a looser
# rule such as "mentioned soon after it started" also matches pre-warmed spares.)
# Agent-tool subagents run inside the parent's process: their servers are in
# its process tree and their transcripts are read along with the parent's.
# A session's worktrees are its transcript's `worktreePath`s plus its cwd; its
# branches are those worktrees' branches and the PRs in its job's state.json.
#
# Every row gets one verdict:
#   ACT   provably finished; --apply retires it
#   ASK   probably finished but something could be lost; the owner decides
#   KEEP  in use or unfinished; reported so nothing is a mystery
#
# "Merged" is asked of GitHub (`gh pr list`), never `git branch --merged`: a
# squash merge puts the work on main as a new commit, so git reports every
# squash-merged branch as unmerged forever. A branch only counts as merged if
# its tip is still the commit the PR merged: a commit added after the merge is
# work, and makes the row ASK.
#
#
# bash 3.2 (stock macOS): no associative arrays, no mapfile.

set -u
export GIT_TERMINAL_PROMPT=0
REPOS=${CLEAN_REPOS:-$HOME/Code}   # where --all looks for git repos

APPLY=0; ALL=0; REPOS_ONLY=0; AS=""
while [ $# -gt 0 ]; do
  a=$1; shift
  case $a in
    --apply) APPLY=1 ;;
    --all) ALL=1 ;;
    --repos-only) REPOS_ONLY=1 ;;
    --as) AS=${1:-}; shift ;;  # survey as if run inside session <pid> (never with --apply)
    -h|--help) sed -n '2,39p' "$0"; exit 0 ;;
  esac
done
if [ -n "$AS" ]; then
  [ "$APPLY" = 1 ] && { echo "clean.sh: --as only surveys; run /clean inside that session to act"; exit 1; }
  [ -f "$HOME/.claude/sessions/$AS.json" ] || { echo "clean.sh: no live session with pid $AS"; exit 1; }
fi

T=$(mktemp -d "${TMPDIR:-/tmp}/clean.XXXXXX")
trap 'rm -rf "$T"' EXIT
: > "$T/rows"      # verdict \t kind \t target \t command \t why
: > "$T/stopping"  # pids of sessions this run will stop (+ descendants)

row() {
  [ "$REPOS_ONLY" = 1 ] && case $2 in session|remote-ctl|viewer|server|browser|orphan) return ;; esac
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$T/rows"
}
tilde() { printf '%s' "${1/#$HOME/~}"; }

ps -axo pid=,ppid=,rss=,tty=,command= > "$T/ps"
lsof -d cwd -Fpn 2>/dev/null |
  awk '/^p/{p=substr($0,2)} /^n/{print p"\t"substr($0,2)}' > "$T/cwd"

cmd_of()   { awk -v p="$1" '$1==p{ $1=$2=$3=$4=""; sub(/^ +/,""); print; exit }' "$T/ps"; }
ppid_of()  { awk -v p="$1" '$1==p{print $2; exit}' "$T/ps"; }
cwd_of()   { awk -F'\t' -v p="$1" '$1==p{print $2; exit}' "$T/cwd"; }
ancestors() { awk -v p="$1" '{par[$1]=$2} END{while(p>1 && p!=""){print p; p=par[p]}}' "$T/ps"; }
# pid plus every descendant
tree() { awk -v r="$1" '{par[$1]=$2} END{for(i in par){x=i; while(x>1){if(x==r){print i; break} x=par[x]}}}' "$T/ps"; }
tree_mb() { tree "$1" > "$T/tree.$1"; awk 'NR==FNR{t[$1]=1; next} ($1 in t){s+=$3} END{printf "%d", s/1024}' "$T/tree.$1" "$T/ps"; }
# Stale rule: anything untouched for STALE_DAYS may go, even with unshipped
# commits or unsaved files, but only with the owner's yes, so it is an
# ASK row (the skill recommends delete), never ACT. A branch whose PR is still
# open on GitHub is exempt. Age = newest of: last commit, any uncommitted file.
STALE_DAYS=60
age_days() {  # <ref> [worktree-dir] → days since the newest activity
  local t newest
  t=$(git log -1 --format=%ct "$1" 2>/dev/null || echo 0)
  if [ -n "${2:-}" ]; then
    newest=$(git -C "$2" status --porcelain 2>/dev/null | cut -c4- | while read -r f; do
      [ -e "$2/$f" ] && find "$2/$f" -type f -exec stat -f %m {} + 2>/dev/null; done | sort -n | tail -1)
    [ -n "$newest" ] && [ "$newest" -gt "$t" ] && t=$newest
  fi
  echo $(( ($(date +%s) - t) / 86400 ))
}
mem_free() { memory_pressure 2>/dev/null | awk -F': ' '/free percentage/{print $2}'; }

# ───────────────────────── Claude sessions ─────────────────────────
# The registry (~/.claude/sessions/<pid>.json) knows every live session; `claude
# agents` knows the job id and whether its work is `done`. A session can drop out
# of `claude agents` while its process lives on: the registry still sees it.
NOW_MS=$(( $(date +%s) * 1000 ))
claude agents --json 2>/dev/null |
  jq -r '.[] | [.pid, (.id // "-"), (.state // "-")] | @tsv' > "$T/agents" 2>/dev/null || : > "$T/agents"

SELF=""
for p in $(ancestors $$); do
  [ -f "$HOME/.claude/sessions/$p.json" ] && { SELF=$p; break; }
done
[ -n "$AS" ] && SELF=$AS

# ─────────── session scope: this session + the sessions it launched ───────────
: > "$T/mine"        # session pids in scope
: > "$T/my_paths"    # worktree / checkout paths in scope
: > "$T/my_branches" # branch names in scope
: > "$T/my_prs"      # owner/repo \t PR number
in_mine()   { grep -qx "$1" "$T/mine"; }
wt_in_scope() {  # worktree dir is one this scope used (or a scope path lies inside it)
  awk -v w="$1" '$0==w || index($0, w"/")==1 {f=1} END{exit !f}' "$T/my_paths"
}
cwd_in_scope() {  # a process cwd inside a scope path, but not inside another
                  # worktree nested under a main checkout that is in scope
  awk -v d="$1" '($0==d || index(d, $0"/")==1) && index(d, $0"/.claude/worktrees/")!=1 {f=1} END{exit !f}' "$T/my_paths"
}
transcripts_of() {  # session pid → its transcript and its subagents' transcripts
  local sid f
  sid=$(jq -r .sessionId "$HOME/.claude/sessions/$1.json" 2>/dev/null)
  f=$(find "$HOME/.claude/projects" -maxdepth 2 -name "$sid.jsonl" 2>/dev/null | head -1)
  [ -n "$f" ] || return
  echo "$f"; ls "${f%.jsonl}"/subagents/*.jsonl 2>/dev/null
}
launches_of() {  # session pid → tool_use ids of its Bash calls that ran `claude --bg`
  transcripts_of "$1" | tr '\n' '\0' | xargs -0 grep -h -E 'claude[^"]*--(bg|background)' 2>/dev/null |
    jq -r '.message.content[]? | select(.type=="tool_use" and .name=="Bash")
           | select(.input.command | test("claude\\b[^|;&]*--(bg|background)\\b")) | .id' 2>/dev/null
}

if [ "$ALL" = 0 ]; then
  if [ -z "$SELF" ]; then
    echo "clean.sh: not running inside a Claude session, so there is no 'this session' to clean."
    echo "          Use --all (/clean-all) for a machine-wide sweep."
    exit 1
  fi
  echo "$SELF" > "$T/mine"
  # Children, then their children, until nothing new turns up.
  changed=1
  while [ "$changed" = 1 ]; do
    changed=0
    for f in "$HOME"/.claude/sessions/*.json; do
      [ -f "$f" ] || continue
      pid=$(basename "$f" .json)
      in_mine "$pid" && continue
      kill -0 "$pid" 2>/dev/null || continue
      IFS=$'\t' read -r cid csid cstart spare <<EOF
$(jq -r '[(.jobId // .name), .sessionId, (.startedAt // 0), (.spare // false)] | @tsv' "$f")
EOF
      [ "$spare" = true ] && continue  # a pre-warmed spare nobody has claimed
      for par in $(cat "$T/mine"); do
        pstart=$(jq -r '.startedAt // 0' "$HOME/.claude/sessions/$par.json" 2>/dev/null)
        [ "${cstart%.*}" -gt "${pstart%.*}" ] || continue
        [ -s "$T/launches.$par" ] || launches_of "$par" > "$T/launches.$par"
        [ -s "$T/launches.$par" ] || continue
        # the child's id in the output of one of those launches
        if transcripts_of "$par" | tr '\n' '\0' | xargs -0 grep -h -F -f "$T/launches.$par" 2>/dev/null |
             grep '"tool_result"' | grep -q -F -e "$cid" -e "$csid"; then
          echo "$pid" >> "$T/mine"; changed=1; break
        fi
      done
    done
  done
  for pid in $(cat "$T/mine"); do
    reg="$HOME/.claude/sessions/$pid.json"
    cwd=$(jq -r .cwd "$reg")
    top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) && echo "$top" >> "$T/my_paths"
    transcripts_of "$pid" | tr '\n' '\0' | xargs -0 grep -hoE '"worktree(Path|Branch)":"[^"]+"' 2>/dev/null | sort -u |
      while IFS= read -r kv; do
        v=${kv#*\":\"}; v=${v%\"}
        case $kv in *Path*) echo "$v" >> "$T/my_paths" ;; *) echo "$v" >> "$T/my_branches" ;; esac
      done
    job=$(jq -r '.jobId // empty' "$reg")
    [ -n "$job" ] && jq -r '.children[]? | select(.kind=="pr") | .href' "$HOME/.claude/jobs/$job/state.json" 2>/dev/null |
      sed -nE 's|https://github.com/([^/]+/[^/]+)/pull/([0-9]+).*|\1\t\2|p' >> "$T/my_prs"
  done
  sort -u -o "$T/my_paths" "$T/my_paths"; sort -u -o "$T/my_branches" "$T/my_branches"; sort -u -o "$T/my_prs" "$T/my_prs"
fi

: > "$T/sessions"  # pid \t id \t name \t kind \t status \t state \t idle_min \t cwd \t verdict
for f in "$HOME"/.claude/sessions/*.json; do
  [ -f "$f" ] || continue
  pid=$(basename "$f" .json)
  kill -0 "$pid" 2>/dev/null || continue
  [ "$ALL" = 0 ] && ! in_mine "$pid" && continue
  IFS=$'\t' read -r name kind status upd cwd <<EOF
$(jq -r '[.name, .kind, .status, (.statusUpdatedAt // .updatedAt // 0), .cwd] | @tsv' "$f")
EOF
  idle=$(( (NOW_MS - ${upd%.*}) / 60000 ))
  id=$(awk -F'\t' -v p="$pid" '$1==p{print $2}' "$T/agents"); id=${id:--}
  state=$(awk -F'\t' -v p="$pid" '$1==p{print $3}' "$T/agents"); state=${state:--}
  [ "$id" = "-" ] && printf '%s' "$name" | grep -qE '^[0-9a-f]{8}$' && id=$name
  has_job=0; [ "$id" != "-" ] && [ -f "$HOME/.claude/jobs/$id/state.json" ] && has_job=1
  mb=$(tree_mb "$pid")
  label="$name ($kind, $status, idle ${idle}m, ${mb}MB, $(tilde "$cwd"))"
  stop="claude stop $id 2>/dev/null || kill $pid"
  [ "$id" = "-" ] && stop="kill $pid"

  if [ "$pid" = "$SELF" ]; then
    row KEEP session "$label" "" "this session"
  elif [ "$status" = "busy" ] || [ "$status" = "waiting" ] || [ "$state" = "working" ]; then
    row KEEP session "$label" "" "working right now"
  elif [ "$kind" = "interactive" ]; then
    row KEEP session "$label" "" "interactive / Remote Control: never stopped by /clean; archive it on the device"
  elif [ "$ALL" = 0 ]; then
    # A child of this session: the owner running /clean here says its work is done.
    row ACT session "$label" "$stop" "launched by this session, idle (conversation kept: claude attach $id)"
    tree "$pid" >> "$T/stopping"
  elif [ "$has_job" = 0 ] && [ "$idle" -ge 15 ]; then
    row ACT session "$label" "$stop" "never given a task; idle ${idle}m"
    tree "$pid" >> "$T/stopping"
  elif [ "$idle" -ge 60 ]; then
    row ACT session "$label" "$stop" "idle ${idle}m (conversation kept: claude attach $id)"
    tree "$pid" >> "$T/stopping"
  else
    row KEEP session "$label" "" "used ${idle}m ago"
  fi
done

# Terminal tabs still attached to a session that is gone. (--all only: a stray
# viewer belongs to no session, so it is never "this session's".)
[ "$ALL" = 1 ] && awk '$5=="claude" && $6=="attach" {print $1"\t"$4"\t"$7}' "$T/ps" | while IFS=$'\t' read -r pid tty id; do
  if ! awk -F'\t' -v i="$id" '$2==i{f=1} END{exit !f}' "$T/agents"; then
    row ASK viewer "claude attach $id on $tty" "kill $pid" "the session it shows is not running; closing just ends the viewer"
  fi
done

# Plain `claude` terminal windows are NOT judged. A window talks only to the
# supervisor, which relays to its session, so nothing visible from outside links
# a window to its session. Guessing by start time does not work either: a fresh
# `claude` claims a pre-warmed spare that started minutes before it, so a live
# window looks dead. Only `claude attach <id>` (above), which names its session,
# is judged.

# Remote Control servers (`claude rc` / `claude remote-control`). The server is
# NEVER stopped here, and neither are its sessions: the documented way to end
# one is to archive it on the owner's device, and killing its process from
# outside is not. So this only reports what the idle ones cost.
# (--all only.)
[ "$ALL" = 1 ] && awk '$5=="claude" && ($6=="rc" || $6=="remote-control") {print $1"\t"$4}' "$T/ps" | while IFS=$'\t' read -r host tty; do
  idle_list=""; idle_mb=0
  for f in "$HOME"/.claude/sessions/*.json; do
    [ -f "$f" ] || continue; pid=$(basename "$f" .json)
    [ "$(ppid_of "$pid")" = "$host" ] || continue
    IFS=$'\t' read -r nm st upd <<EOF2
$(jq -r '[.name, .status, (.statusUpdatedAt // 0)] | @tsv' "$f")
EOF2
    i=$(( (NOW_MS - ${upd%.*}) / 60000 ))
    if [ "$st" = idle ] && [ "$i" -ge 60 ]; then
      mb=$(tree_mb "$pid"); idle_mb=$((idle_mb + mb))
      idle_list="${idle_list:+$idle_list, }$nm (idle $((i/60))h)"
    fi
  done
  why="never stopped by /clean"
  [ -n "$idle_list" ] && why="$why; archive on the device to free ~${idle_mb}MB: $idle_list"
  row KEEP remote-ctl "Remote Control server on $tty ($(tree_mb "$host")MB incl. sessions)" "" "$why"
done

# The live sessions whose processes must be left alone: everything under a
# session that is not being stopped.
: > "$T/protected"
for f in "$HOME"/.claude/sessions/*.json; do
  [ -f "$f" ] || continue
  pid=$(basename "$f" .json)
  kill -0 "$pid" 2>/dev/null || continue
  grep -qx "$pid" "$T/stopping" || tree "$pid" >> "$T/protected"
done
owner_session() {  # prints the live, kept session pid this process runs under
  for a in $(ancestors "$1"); do grep -qx "$a" "$T/protected" && [ -f "$HOME/.claude/sessions/$a.json" ] && { echo "$a"; return; }; done
}

# ───────────── dev servers, walk browsers, orphaned helpers ─────────────
judge_proc() {  # pid kind label
  local pid=$1 kind=$2 label=$3 owner
  grep -qx "$pid" "$T/stopping" && { row ACT "$kind" "$label" "kill $pid" "belongs to a session being stopped"; return; }
  owner=$(owner_session "$pid")
  if [ "$ALL" = 0 ]; then
    if [ "$owner" = "$SELF" ]; then
      # Whatever the Bash tool started (dev server, http.server) is finished
      # work. The MCP servers this session runs on are not: their browser may
      # go, they may not. Judge by the session's direct child on the way down;
      # "is it a shell" does not work, a backgrounded `exec` has no shell.
      local top=""
      for a in $(ancestors "$pid"); do [ "$(ppid_of "$a")" = "$SELF" ] && { top=$a; break; }; done
      if ! cmd_of "$top" | grep -qiE 'mcp|stdio' || [ "$kind" = browser ]; then
        row ACT "$kind" "$label" "pkill -P $pid; kill $pid" "started by this session"
      fi
    elif [ -n "$owner" ] && in_mine "$owner"; then
      row KEEP "$kind" "$label" "" "a session this one launched is still working"
    elif [ -z "$owner" ] && [ "$(ppid_of "$pid")" = 1 ] && cwd_in_scope "$(cwd_of "$pid")"; then
      row ACT "$kind" "$label" "pkill -P $pid; kill $pid" "orphaned in this session's worktree"
    fi
    return  # anything else is another session's, or a stray for /clean-all
  fi
  if [ -n "$owner" ]; then
    oname=$(jq -r .name "$HOME/.claude/sessions/$owner.json" 2>/dev/null)
    row KEEP "$kind" "$label" "" "started by live session '$oname'"
  elif [ "$(ppid_of "$pid")" = 1 ]; then
    row ACT "$kind" "$label" "pkill -P $pid; kill $pid" "orphaned, its parent is gone"
  else
    row ASK "$kind" "$label" "pkill -P $pid; kill $pid" "no Claude session owns it, started from a terminal?"
  fi
}

# Anything listening that is a runtime rather than an app.
lsof -nP -iTCP -sTCP:LISTEN -Fpn 2>/dev/null |
  awk '/^p/{p=substr($0,2)} /^n/{print p"\t"substr($0,2)}' | sort -u > "$T/listen"
cut -f1 "$T/listen" | sort -u | while read -r pid; do
  c=$(cmd_of "$pid")
  case $c in /Applications/*|/System/*|/usr/libexec/*|/usr/sbin/*) continue ;; esac
  printf '%s' "$c" | grep -qiE '(^|/)(node|bun|deno|python[0-9.]*|Python|ruby|php|java|npm|pnpm|yarn)( |$)|next-server|vite|http\.server|uvicorn|gunicorn|flask|rails' || continue
  ports=$(awk -F'\t' -v p="$pid" '$1==p{sub(/.*:/,"",$2); print $2}' "$T/listen" | sort -u | paste -sd, -)
  judge_proc "$pid" server ":$ports $(printf '%s' "$c" | cut -c1-70) ($(tilde "$(cwd_of "$pid")"), $(tree_mb "$pid")MB)"
done

# Walk / test browsers (main process only: helpers die with it).
grep -E 'Chrome for Testing|ms-playwright|mcp-chrome|chrome-headless-shell|puppeteer_dev_chrome_profile|Chromium' "$T/ps" |
  grep -v -- '--type=' | awk '{print $1}' | while read -r pid; do
    judge_proc "$pid" browser "$(cmd_of "$pid" | cut -c1-80) ($(tree_mb "$pid")MB)"
  done

# Helpers whose session died without them (reparented to launchd).
awk '$2==1' "$T/ps" | grep -E 'npm exec|mcp-server|playwright-mcp|next dev|next-server|vite|esbuild|turbopack|http\.server|nodemon|tsx watch' |
  awk '{print $1}' | while read -r pid; do
    awk -F'\t' -v c="kill $pid" 'index($4, c) {f=1} END{exit !f}' "$T/rows" && continue
    [ "$ALL" = 0 ] && ! cwd_in_scope "$(cwd_of "$pid")" && continue
    row ACT orphan "$(cmd_of "$pid" | cut -c1-80) ($(tree_mb "$pid")MB)" "pkill -P $pid; kill $pid" "orphaned, its parent is gone"
  done

# ───────────────────────────── repos ─────────────────────────────
in_use_by() {  # path → "pid cmd" of a kept process whose cwd is inside it
  awk -F'\t' -v d="$1" '$2==d || index($2, d"/")==1 {print $1}' "$T/cwd" | while read -r p; do
    grep -qx "$p" "$T/stopping" && continue
    [ "$p" = "$$" ] && continue
    echo "$p $(cmd_of "$p" | cut -c1-40)"; break
  done
}

survey_repo() {
  local R=$1 DEF prs
  cd "$R" || return
  git fetch --quiet --prune origin 2>/dev/null
  # A clone made before the remote had its default branch, or a default changed
  # since, has no origin/HEAD. Guessing `main` then skipped the whole repo when
  # the default was something else (savras: `development`), so ask the remote.
  git symbolic-ref --quiet refs/remotes/origin/HEAD >/dev/null 2>&1 || git remote set-head origin --auto >/dev/null 2>&1
  DEF=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||'); DEF=${DEF:-main}
  git rev-parse --verify --quiet "origin/$DEF" >/dev/null || { row KEEP repo "$(tilde "$R")" "" "no origin/$DEF, skipped"; return; }
  prs=$T/prs.$(basename "$R")
  gh pr list --state all --limit 300 --json headRefName,state,number,headRefOid \
    -q '.[] | [.headRefName, .state, (.number|tostring), .headRefOid] | @tsv' > "$prs" 2>/dev/null || : > "$prs"
  local name; name=$(basename "$R")

  # Session scope: this repo's branches that belong to the scope's sessions.
  local slug scope_b=$T/scope_b.$name
  slug=$(git remote get-url origin 2>/dev/null | sed -E 's#\.git$##; s#.*[:/]([^/:]+/[^/:]+)$#\1#')
  cp "$T/my_branches" "$scope_b"
  awk -F'\t' -v s="$slug" 'tolower($1)==tolower(s){print $2}' "$T/my_prs" | while read -r n; do
    awk -F'\t' -v n="$n" '$3==n{print $1}' "$prs"
  done >> "$scope_b"
  in_scope_branch() { [ "$ALL" = 1 ] || grep -qxF -- "$1" "$scope_b"; }

  # Is branch $1 at tip $2 finished? → "DONE why" / "OPEN why" / "ASK why"
  branch_state() {
    local b=$1 tip=$2 pr st num oid
    pr=$(awk -F'\t' -v b="$b" '$1==b{print; exit}' "$prs")
    # Pushed under another name (`git push origin HEAD:other`): the tip IS that
    # PR's head commit, so match on the tip before declaring "no PR".
    [ -n "$pr" ] || pr=$(awk -F'\t' -v t="$tip" '$4==t{print; exit}' "$prs")
    if [ -z "$pr" ]; then
      if git merge-base --is-ancestor "$tip" "origin/$DEF" 2>/dev/null; then echo "DONE no commits beyond $DEF"
      else echo "OPEN no PR yet, unshipped commits"; fi
      return
    fi
    IFS=$'\t' read -r _ st num oid <<EOF
$pr
EOF
    case $st in
      MERGED)
        if [ "$tip" = "$oid" ] || git merge-base --is-ancestor "$tip" "$oid" 2>/dev/null || git merge-base --is-ancestor "$tip" "origin/$DEF" 2>/dev/null; then
          echo "DONE PR #$num merged"
        else echo "ASK PR #$num merged, but the branch has commits added after the merge"; fi ;;
      OPEN) echo "OPEN PR #$num open" ;;
      CLOSED)
        if git merge-base --is-ancestor "$tip" "origin/$DEF" 2>/dev/null; then echo "DONE PR #$num closed, nothing unique"
        else echo "ASK PR #$num closed without merging"; fi ;;
    esac
  }

  # worktrees
  git worktree list --porcelain | awk '
    /^worktree /{w=substr($0,10); h=""; b="(detached)"; l=0}
    /^HEAD /{h=substr($0,6)}
    /^branch /{b=substr($0,19)}
    /^locked/{l=1}
    /^$/{print w"\t"h"\t"b"\t"l}
    END{if(w!="")print w"\t"h"\t"b"\t"l}' | awk '!seen[$0]++' > "$T/wt"
  local main_wt; main_wt=$(head -1 "$T/wt" | cut -f1)
  : > "$T/checked_out"
  cut -f3 "$T/wt" >> "$T/checked_out"

  tail -n +2 "$T/wt" | while IFS=$'\t' read -r w h b locked; do
    local label="$name: worktree $(basename "$w") [$b]" use dirty bs verdict why cmd
    [ "$ALL" = 0 ] && ! wt_in_scope "$w" && ! in_scope_branch "$b" && continue
    if [ ! -d "$w" ]; then row ACT worktree "$label" "git -C '$R' worktree prune" "directory already gone"; continue; fi
    use=$(in_use_by "$w")
    dirty=$(git -C "$w" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [ "$b" = "(detached)" ]; then
      git merge-base --is-ancestor "$h" "origin/$DEF" 2>/dev/null && bs="DONE detached, nothing unique" || bs="OPEN detached with unique commits"
    else bs=$(branch_state "$b" "$h"); fi
    verdict=${bs%% *}; why=${bs#* }
    cmd="git -C '$R' worktree unlock '$w' 2>/dev/null; git -C '$R' worktree remove '$w'"
    # Never delete the default branch: a parked worktree often holds `main`.
    [ "$b" != "(detached)" ] && [ "$b" != "$DEF" ] && cmd="$cmd && git -C '$R' branch -D '$b'"
    age=$(age_days "$h" "$w")
    if [ -z "$use" ] && [ "$verdict" != DONE ] && [ "$age" -ge "$STALE_DAYS" ] && ! printf '%s' "$why" | grep -q ' open$'; then
      row ASK worktree "$label" "${cmd/worktree remove/worktree remove --force}" "STALE: $why, untouched ${age}d"
    elif [ -n "$use" ]; then row KEEP worktree "$label" "" "$why; in use by pid $use"
    elif [ "$verdict" = OPEN ]; then row KEEP worktree "$label" "" "$why"
    elif [ "$dirty" -gt 0 ]; then
      # The owner's "yes" to this row is the consent to lose those files, so the
      # command must be able to act on it; plain `worktree remove` refuses.
      row ASK worktree "$label" "${cmd/worktree remove/worktree remove --force}" "$why, but $dirty uncommitted/untracked file(s) would be lost: git -C '$w' status"
    elif [ "$verdict" = ASK ]; then row ASK worktree "$label" "$cmd" "$why"
    else row ACT worktree "$label" "$cmd" "$why"; fi
  done

  # the main checkout
  local cur; cur=$(git -C "$main_wt" rev-parse --abbrev-ref HEAD)
  local tracked_dirty; tracked_dirty=$(git -C "$main_wt" status --porcelain --untracked-files=no | wc -l | tr -d ' ')
  local behind; behind=$(git -C "$main_wt" rev-list --count "HEAD..origin/$DEF")
  # Session scope touches the shared main checkout only to bring it back from
  # a branch of this scope; catching it up with origin is /clean-all's job.
  local main_mine=1
  [ "$ALL" = 0 ] && ! in_scope_branch "$cur" && ! grep -qxF -- "$main_wt" "$T/my_paths" && main_mine=0
  [ "$ALL" = 0 ] && [ "$cur" = "$DEF" ] && main_mine=0
  if [ "$main_mine" = 0 ]; then :
  elif [ "$cur" != "$DEF" ]; then
    local bs; bs=$(branch_state "$cur" "$(git -C "$main_wt" rev-parse HEAD)")
    local holder; holder=$(awk -F'\t' -v b="$DEF" 'NR>1 && $3==b{print $1}' "$T/wt")
    local cmd="git -C '$main_wt' switch '$DEF' && git -C '$main_wt' merge --ff-only 'origin/$DEF' && git -C '$main_wt' branch -D '$cur'"
    # The worktree holding $DEF may already be removed by an earlier ACT row.
    [ -n "$holder" ] && cmd="{ git -C '$holder' switch --detach 2>/dev/null || true; } && $cmd"
    if [ "${bs%% *}" = OPEN ]; then row KEEP checkout "$name: main checkout on '$cur'" "" "${bs#* }, switch by hand when that work is done"
    elif [ "$tracked_dirty" -gt 0 ]; then row ASK checkout "$name: main checkout on '$cur'" "$cmd" "${bs#* }, but $tracked_dirty edited tracked file(s)"
    elif [ "${bs%% *}" = ASK ]; then row ASK checkout "$name: main checkout on '$cur'" "$cmd" "${bs#* }"
    else row ACT checkout "$name: main checkout on '$cur', $behind behind" "$cmd" "${bs#* }, back to $DEF"; fi
  elif [ "$behind" -gt 0 ]; then
    # Commits of its own that origin already has as other copies (a rebase or a
    # re-apply upstream) make a fast-forward refuse forever, though nothing
    # would be lost. `git cherry` says "-" for each such copy. `reset --keep`
    # refuses rather than touch a file with local edits.
    local own; own=$(git -C "$main_wt" rev-list --count "origin/$DEF..HEAD")
    local unique; unique=$(git -C "$main_wt" cherry "origin/$DEF" HEAD | grep -c '^+')
    if [ "$own" -eq 0 ]; then
      row ACT checkout "$name: main checkout, $behind behind origin/$DEF" "git -C '$main_wt' merge --ff-only 'origin/$DEF'" "fast-forward only"
    elif [ "$unique" -eq 0 ]; then
      row ACT checkout "$name: main checkout, $behind behind origin/$DEF" "git -C '$main_wt' reset --keep 'origin/$DEF'" "its $own own commit(s) are already on origin/$DEF as other copies"
    else
      row ASK checkout "$name: main checkout, $behind behind origin/$DEF" "git -C '$main_wt' reset --keep 'origin/$DEF'" "$unique commit(s) not on origin/$DEF would be dropped: git -C '$main_wt' log --oneline origin/$DEF..HEAD"
    fi
  fi

  # local branches not checked out anywhere
  git for-each-ref --format='%(refname:short)	%(objectname)' refs/heads | while IFS=$'\t' read -r b tip; do
    [ "$b" = "$DEF" ] && continue
    grep -qx "$b" "$T/checked_out" && continue
    in_scope_branch "$b" || continue
    local bs; bs=$(branch_state "$b" "$tip")
    local age; age=$(age_days "$tip")
    if [ "${bs%% *}" != DONE ] && [ "$age" -ge "$STALE_DAYS" ] && ! printf '%s' "$bs" | grep -q ' open$'; then
      row ASK branch "$name: $b" "git -C '$R' branch -D '$b'" "STALE: ${bs#* }, untouched ${age}d"
      continue
    fi
    case ${bs%% *} in
      DONE) row ACT branch "$name: $b" "git -C '$R' branch -D '$b'" "${bs#* }" ;;
      ASK)  row ASK branch "$name: $b" "git -C '$R' branch -D '$b'" "${bs#* }" ;;
      *)    row KEEP branch "$name: $b" "" "${bs#* }" ;;
    esac
  done

  # remote branches of merged PRs that GitHub did not delete
  git for-each-ref --format='%(refname:lstrip=3)	%(objectname)' "refs/remotes/origin" | while IFS=$'\t' read -r b tip; do
    [ "$b" = "$DEF" ] || [ "$b" = HEAD ] && continue
    in_scope_branch "$b" || continue
    pr=$(awk -F'\t' -v b="$b" '$1==b{print; exit}' "$prs")
    [ -n "$pr" ] || continue
    st=$(printf '%s' "$pr" | cut -f2); oid=$(printf '%s' "$pr" | cut -f4)
    [ "$st" = MERGED ] && [ "$tip" = "$oid" ] &&
      row ACT remote "$name: origin/$b" "git -C '$R' push --quiet origin --delete '$b'" "PR #$(printf '%s' "$pr" | cut -f3) merged"
  done
}

if [ "$ALL" = 1 ]; then
  for d in "$REPOS"/*/; do [ -e "$d/.git" ] && survey_repo "${d%/}"; done
else
  # The repos this scope touched: behind each of its paths (a removed
  # worktree's repo is the part before /.claude/worktrees/), and each PR's repo
  # if it is cloned under $REPOS.
  { while IFS= read -r p; do
      if [ -d "$p" ]; then c=$(git -C "$p" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && dirname "$c"
      else case $p in */.claude/worktrees/*) echo "${p%%/.claude/worktrees/*}" ;; esac; fi
    done < "$T/my_paths"
    cut -f1 "$T/my_prs" | while read -r s; do
      for d in "$REPOS"/*/; do
        git -C "$d" remote get-url origin 2>/dev/null | grep -qiE "[:/]$s(\.git)?$" && echo "${d%/}"
      done
    done
  } | sort -u | while read -r R; do [ -e "$R/.git" ] && survey_repo "$R"; done
fi

# ───────────────────────────── report ─────────────────────────────
ORDER="session remote-ctl viewer server browser orphan repo worktree checkout branch remote"
print_rows() {
  for k in $ORDER; do
    awk -F'\t' -v v="$1" -v k="$k" '$1==v && $2==k {printf "  %-4s %-8s %s\n         → %s\n", $1, $2, $3, $5}' "$T/rows"
  done
}
if [ "$ALL" = 1 ]; then echo "Scope: the whole machine, every repo under $(tilde "$REPOS")"
else echo "Scope: this session + $(( $(wc -l < "$T/mine") - 1 )) session(s) it launched; other sessions are left alone (/clean-all for strays)"; fi
echo "RAM free: $(mem_free)"
for v in ACT ASK KEEP; do
  n=$(awk -F'\t' -v v="$v" '$1==v' "$T/rows" | wc -l | tr -d ' ')
  [ "$n" -gt 0 ] || continue
  echo; echo "── $v ($n) ──"; print_rows "$v"
done
[ -s "$T/rows" ] || echo "Nothing left behind."

# ASK rows as machine-readable commands, for the skill to run after the owner answers.
if awk -F'\t' '$1=="ASK"' "$T/rows" | grep -q .; then
  echo; echo "── ASK commands ──"
  awk -F'\t' '$1=="ASK"{printf "  [%s] %s\n    %s\n", $2, $3, $4}' "$T/rows"
fi

[ "$APPLY" = 1 ] || exit 0

# ───────────────────────────── apply ─────────────────────────────
# Order matters: stop sessions before their worktrees, free a worktree holding
# main before the checkout switches to it, remove worktrees before their branches.
echo; echo "── applying ──"
for k in $ORDER; do
  awk -F'\t' -v k="$k" '$1=="ACT" && $2==k {print $3"\t"$4}' "$T/rows" | while IFS=$'\t' read -r label cmd; do
    if out=$(bash -c "$cmd" 2>&1); then echo "  ok    $label"
    else echo "  FAIL  $label, $(printf '%s' "$out" | tail -1)"; fi
  done
done
for R in $(awk -F'\t' '$1=="ACT" && ($2=="worktree"||$2=="checkout"||$2=="branch") {print $4}' "$T/rows" | grep -oE "git -C '[^']+'" | sed "s/git -C //; s/'//g" | sort -u); do
  git -C "$R" worktree prune 2>/dev/null
done
sleep 1
echo "RAM free: $(mem_free)"
