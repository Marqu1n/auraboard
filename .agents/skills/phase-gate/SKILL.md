---
name: phase-gate
description: >-
  End-of-phase verification and sign-off procedure. Activate when closing any
  development phase before committing the phase milestone.
---

# Phase Gate Procedure

Before marking a phase complete:

1. Run the full verification command:
   ```bash
   ./tool/run_tests.sh all
   ```
2. Capture the diff from the previous phase commit (`git log --oneline <base>..HEAD` and `git diff <base>..HEAD --stat`).
3. Invoke the independent read-only `reviewer` subagent (`define_subagent` with `EnableWriteTools: false` using `.agents/agents/reviewer.md`), passing the phase scope, commit list, and changed files.
4. If the reviewer returns `VERDICT: CHANGES_REQUESTED`:
   - Fix all blocking findings (following TDD for behavioral fixes).
   - Re-run `./tool/run_tests.sh all`.
   - Send the updated diff back to the same `reviewer` subagent via `send_message` until `VERDICT: APPROVE`.
5. Update `docs/DECISIONS.md` if any design or ambiguity resolution occurred during the phase.
6. Ensure the working tree is clean and committed with all tests passing.
