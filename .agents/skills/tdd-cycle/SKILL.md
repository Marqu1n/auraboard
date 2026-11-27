---
name: tdd-cycle
description: >-
  Enforces the Red-Green-Refactor TDD workflow for every feature and bugfix in
  the RPG Soundboard project. Activate before implementing any new behavior.
---

# Enforced TDD Cycle Skill

Follow this strict sequence for every behavior or bugfix:

## 1. RED — Write a Failing Test First
1. Delegate to `test-author` (or write tests under `test/` before touching `lib/`).
2. Run the targeted test suite (`./tool/run_tests.sh unit|widget|smoke`).
3. Confirm the test FAILS for the intended behavioral reason.
4. Commit the failing test as `test(red): <behavior>` so the Red step is visible in git history.

## 2. GREEN — Minimal Implementation
1. Delegate to `implementer` (or implement minimal code under `lib/`).
2. Run the targeted suite and confirm all new and existing tests PASS.
3. Never weaken, skip (`skip: true`), or delete a failing test. If a test itself is wrong, fix it in a dedicated commit explaining why.

## 3. REFACTOR & VERIFY
1. Clean up duplication, naming, and types while keeping tests green.
2. Run the policy guard:
   ```bash
   python3 .agents/skills/tdd-cycle/scripts/tdd_check.py
   ```
3. Run `./tool/run_tests.sh all` (lint + unit + widget + smoke).
4. Commit the passing implementation (`feat(<scope>): <behavior>` or `fix(<scope>): <behavior>`).
