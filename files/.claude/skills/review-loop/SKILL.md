---
name: review-loop
description: Use when the user asks for a review loop, repeated review, or iterative review-and-fix of the current branch with a bounded number of rounds.
---

# Review loop

Review the current branch, fix what matters, and repeat on the fixes until a round brings no new Critical or Important findings.

`REVIEW_NOTES.md` sits at the repository root and holds what earlier rounds decided. It is working state: never commit it.

Each round:

1. Use superpowers:requesting-code-review on the current scope.
   - Round 1: the diff against the base branch.
   - Later rounds: only the files changed in the last fix round.
   - Pass `REVIEW_NOTES.md` and tell the reviewer not to raise a listed item again without new evidence.
   - Ask for a confidence score (0-100) per finding, and drop findings below 80.
2. Use superpowers:receiving-code-review to triage each finding:
   - FIX: only Critical and Important findings.
   - REJECT: give the reason.
   - DEFER: Minor findings.
3. Apply the fixes and run the tests. Append each REJECT and DEFER to `REVIEW_NOTES.md`. Also append each FIX with its round number and severity, so a finding that returns can be recognised.
4. Decide how the loop goes on:
   - No new Critical or Important findings this round: use superpowers:verification-before-completion, then output `<promise>REVIEW_CONVERGED</promise>`.
   - A Critical finding that was already fixed in an earlier round comes back (it has survived two rounds): stop. Report it to the user instead of fixing it again.
   - Otherwise: start the next round.
