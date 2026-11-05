---
name: review-loop
description: Use when the user asks for a review loop, repeated review, or iterative review-and-fix of the current branch with a bounded number of rounds.
---

# Review loop

Review the current branch, fix what matters, and repeat on the fixes until a round brings no new Critical or Important findings.

`REVIEW_NOTES.md` sits at the repository root and holds what earlier rounds decided. Reviewer reports go to `.claude/review-loop/round-<N>.md`. Both are working state: never commit them.

The loop is driven by a Ralph stop hook: the moment a turn ends, the hook feeds the same prompt back and counts an iteration. Subagents run in the background, so a turn that dispatches the reviewer and then ends burns the iteration before the review exists. A round therefore never ends its turn while a reviewer is out.

Each round:

1. Use superpowers:requesting-code-review on the current scope.
   - Round 1: the diff against the base branch.
   - Later rounds: only the files changed in the last fix round.
   - Pass `REVIEW_NOTES.md` and tell the reviewer not to raise a listed item again without new evidence.
   - Ask for a confidence score (0-100) per finding, and drop findings below 80.
   - Tell the reviewer to write its complete report to `.claude/review-loop/round-<N>.md` as its final action.
   - Then wait for that file in a foreground shell command, which keeps this turn open:
     `until [ -f .claude/review-loop/round-<N>.md ]; do sleep 10; done`
     Run it with the tool's maximum timeout and run it again whenever it times out. After 30 minutes without a report, cancel the loop (see step 4) and report the failure.
   - Read the findings from the file, not from the completion notification.
2. Use superpowers:receiving-code-review to triage each finding:
   - FIX: only Critical and Important findings.
   - REJECT: give the reason.
   - DEFER: Minor findings.
3. Apply the fixes and run the tests. Append each REJECT and DEFER to `REVIEW_NOTES.md`. Also append each FIX with its round number and severity, so a finding that returns can be recognised.
4. Decide how the loop goes on:
   - No new Critical or Important findings this round: use superpowers:verification-before-completion, then output `<promise>REVIEW_CONVERGED</promise>`.
   - A Critical finding that was already fixed in an earlier round comes back (it has survived two rounds): cancel the loop and report it to the user instead of fixing it again. Cancelling means deleting `.claude/ralph-loop.local.md` (what `/cancel-ralph` does); ending the turn without that only starts the next round.
   - Otherwise: start the next round.
