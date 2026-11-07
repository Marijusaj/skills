#!/usr/bin/env bash
# risk.sh: score a branch's diff 0-10 and map it to a review lane.
#
#   risk.sh <base> [--lane l|m|h --reason "<why>"]
#
# Prints key=value lines: script agent score lane security reasons.
# The score is max(script score, highest "Risk: N/10" trailer in <base>..HEAD).
# --lane overrides the lane; lowering it without --reason exits 2.
# bash 3.2 (macOS); needs git. Reads .claude/ship.json riskPaths via jq,
# python3 or plutil, whichever exists.
set -u

base=${1:-}; shift || true
[ -n "$base" ] || { echo "usage: risk.sh <base> [--lane l|m|h --reason why]" >&2; exit 64; }
git rev-parse --verify --quiet "$base" >/dev/null || { echo "risk.sh: unknown base '$base'" >&2; exit 64; }

want_lane=""; reason=""
while [ $# -gt 0 ]; do
  case "$1" in
    --lane) want_lane=$(printf '%s' "${2:-}" | tr 'LMH' 'lmh'); shift 2 ;;
    --reason) reason=${2:-}; shift 2 ;;
    *) echo "risk.sh: unknown arg '$1'" >&2; exit 64 ;;
  esac
done
case "$want_lane" in ""|l|m|h) ;; *) echo "risk.sh: --lane must be l, m or h" >&2; exit 64 ;; esac

root=$(git rev-parse --show-toplevel)
files=$(git diff --name-only "$base"...HEAD)

# --- size: lines changed, lockfiles and generated files excluded ----------
is_noise() {
  case "$1" in
    *package-lock.json|*yarn.lock|*pnpm-lock.yaml|*bun.lockb|*Cargo.lock|*poetry.lock|*uv.lock|*Gemfile.lock|*go.sum|*composer.lock) return 0 ;;
    *.min.js|*.min.css|*.map|*.snap|*/generated/*|*/__generated__/*|*.generated.*|dist/*|build/*) return 0 ;;
  esac
  return 1
}
lines=0; nfiles=0
while IFS="$(printf '\t')" read -r add del path; do
  [ -n "${path:-}" ] || continue
  nfiles=$((nfiles + 1))
  is_noise "$path" && continue
  [ "$add" = "-" ] && continue          # binary
  lines=$((lines + add + del))
done <<EOF
$(git diff --numstat "$base"...HEAD)
EOF

script=0; reasons=""; security=no
add() { script=$((script + $1)); reasons="${reasons:+$reasons, }$2"; }

if   [ "$lines" -ge 1000 ]; then add 3 "$lines lines"
elif [ "$lines" -ge 400 ];  then add 2 "$lines lines"
elif [ "$lines" -ge 100 ];  then add 1 "$lines lines"
fi
[ "$nfiles" -gt 15 ] && add 1 "$nfiles files"

# --- risky path categories, each counted once ---------------------------
hit() { printf '%s\n' "$files" | grep -Eiq "$1"; }

hit '(^|/)(migrations?|migrate|alembic|db/schema|prisma/schema\.prisma|supabase/migrations)(/|\.|$)|\.sql$' \
  && add 4 "migration"
if hit '(^|/)(auth|authn|authz|security|permissions?|rbac|session|middleware|proxy)(/|\.|$)|(^|/)\.env|(^|[/._-])(secrets?|credentials?)([/._-]|$)|\.pem$|\.key$'; then
  add 3 "auth/secrets"; security=yes
fi
if hit '(^|/)(payments?|billing|checkout|invoic(e|es|ing)|stripe|subscriptions?)(/|\.|$)'; then
  add 3 "payments"; security=yes
fi
hit '(^|/)\.github/workflows/|(^|/)(Dockerfile|docker-compose[^/]*|vercel\.json|netlify\.toml|fly\.toml|railway\.(json|toml))$|\.tf$|(^|/)(infra|deploy|k8s|helm)/' \
  && add 2 "CI/infra"
hit '\.(proto|graphql|gql)$|(^|/)(openapi|swagger)[^/]*\.(ya?ml|json)$|(^|/)api/.*schema' \
  && add 2 "public schema"
hit '(^|/)(package\.json|requirements[^/]*\.txt|pyproject\.toml|Cargo\.toml|go\.mod|Gemfile|composer\.json)$|(^|/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|bun\.lockb|Cargo\.lock|poetry\.lock|uv\.lock|Gemfile\.lock|go\.sum|composer\.lock)$' \
  && add 1 "dependencies"

# --- repo's own riskPaths: a trailing / is a prefix, anything else a glob --
cfg="$root/.claude/ship.json"
risk_paths=""
if [ -f "$cfg" ]; then
  if command -v jq >/dev/null 2>&1; then
    risk_paths=$(jq -r '.riskPaths[]? // empty' "$cfg" 2>/dev/null)
  elif command -v python3 >/dev/null 2>&1; then
    risk_paths=$(python3 -I -c 'import json,sys;[print(p) for p in json.load(open(sys.argv[1])).get("riskPaths",[])]' "$cfg" 2>/dev/null)
  elif command -v plutil >/dev/null 2>&1; then
    i=0
    while p=$(plutil -extract "riskPaths.$i" raw -o - "$cfg" 2>/dev/null); do
      risk_paths="$risk_paths$p
"; i=$((i + 1))
    done
  fi
fi
matched=""
while IFS= read -r pat; do
  [ -n "$pat" ] || continue
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$pat" in
      */) case "$f" in "$pat"*) matched="$pat"; break ;; esac ;;
      *)  case "$f" in $pat) matched="$pat"; break ;; esac ;;
    esac
  done <<EOF
$files
EOF
  [ -n "$matched" ] && break
done <<EOF
$risk_paths
EOF
[ -n "$matched" ] && add 3 "riskPaths $matched"

[ "$script" -gt 10 ] && script=10

# --- agent estimate: highest Risk: N/10 trailer on the branch ------------
agent=$(git log --format=%B "$base"..HEAD | sed -n 's/^Risk: *\([0-9][0-9]*\)\/10.*/\1/p' | sort -n | tail -1)
agent=${agent:-0}
[ "$agent" -gt 10 ] && agent=10

score=$script; [ "$agent" -gt "$score" ] && score=$agent
if   [ "$score" -ge 7 ]; then lane=h
elif [ "$score" -ge 4 ]; then lane=m
else lane=l
fi

rank() { case "$1" in l) echo 1 ;; m) echo 2 ;; h) echo 3 ;; esac; }
if [ -n "$want_lane" ] && [ "$want_lane" != "$lane" ]; then
  if [ "$(rank "$want_lane")" -lt "$(rank "$lane")" ] && [ -z "$reason" ]; then
    echo "risk.sh: lowering lane $lane -> $want_lane needs --reason" >&2
    exit 2
  fi
  reasons="${reasons:+$reasons, }override $lane->$want_lane${reason:+ ($reason)}"
  lane=$want_lane
fi

echo "script=$script"
echo "agent=$agent"
echo "score=$score"
echo "lane=$lane"
echo "security=$security"
echo "reasons=${reasons:-small diff, no risky paths}"
