---
description: "Review loop: review-and-fix the current branch until a round brings no new Critical/Important findings"
argument-hint: "[MAX_ITERATIONS]"
hide-from-slash-command-tool: "true"
---

# Review loop

Start a Ralph loop that runs the `review-loop` skill once per iteration:

```!
max="$ARGUMENTS"
max="${max:-4}"
case "$max" in
  *[!0-9]*|'') echo "rl: max iterations must be a whole number, got: '$max'" >&2; exit 1 ;;
esac

# Locate the ralph-loop plugin wherever it was installed from. Install paths
# carry the version (and for some sources a commit hash), so never hard-code.
setup=""
root=$(jq -r '.plugins | to_entries[] | select(.key | startswith("ralph-loop@")) | .value[0].installPath' \
  "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null | head -n 1)
if [ -n "$root" ] && [ -x "$root/scripts/setup-ralph-loop.sh" ]; then
  setup="$root/scripts/setup-ralph-loop.sh"
else
  for dir in $(ls -d "$HOME"/.claude/plugins/cache/*/ralph-loop/*/ 2>/dev/null | sort -V -r); do
    if [ -x "$dir/scripts/setup-ralph-loop.sh" ]; then setup="$dir/scripts/setup-ralph-loop.sh"; break; fi
  done
fi
if [ -z "$setup" ]; then
  echo "rl: ralph-loop plugin not found. Install it: claude plugin install ralph-loop --marketplace anthropics/claude-plugins-official" >&2
  exit 1
fi

"$setup" --max-iterations "$max" --completion-promise REVIEW_CONVERGED "Use the review-loop skill for one round."
```

Please work on the task. When you try to exit, the Ralph loop will feed the SAME PROMPT back to you for the next iteration. You'll see your previous work in files, git history and `REVIEW_NOTES.md`, allowing you to iterate and improve.

CRITICAL RULE: you may ONLY output `<promise>REVIEW_CONVERGED</promise>` when the review-loop skill's convergence condition is completely and unequivocally TRUE: a full round brought no new Critical or Important findings. Do not output a false promise to escape the loop, even if you think you're stuck or should exit for other reasons. The loop is designed to continue until genuine convergence or the iteration limit.
