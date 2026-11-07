---
name: interrogate-list
description: Interrogate me until you know what to build, asking each round as one numbered list of questions with your recommended answers.
disable-model-invocation: true
---

Call the Skill tool with "interrogate" and args `list` (under the plugin, the
name is "mj:interrogate"). Follow it from step 1, passing on everything the
owner wrote after the command as the goal.
