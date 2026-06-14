---
name: diff-main
description: Use when you want to see all changes on the current branch compared to the main branch, before reviewing work or creating a PR.
---

# diff-main

Show and summarize all changes introduced on the current branch relative to `main`.

## Steps

1. Detect the default branch:
   ```bash
   git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|.*/||'
   ```
   If that returns nothing (no remote or HEAD not set), fall back to checking which of `main` or `master` exists locally:
   ```bash
   git branch --list main master
   ```
   Use whichever exists. If both exist, prefer `main`.

2. Run the diff against the detected branch (e.g. `BASE`):
   ```bash
   git diff BASE...HEAD
   ```

3. If the output is large, break it down file by file:
   ```bash
   git diff BASE...HEAD --stat
   git diff BASE...HEAD -- <file>
   ```

4. Summarize:
   - Files changed and what changed in each
   - New features, bug fixes, refactors, deletions
   - Any concerns or noteworthy patterns

5. Check for possible bugs in the changed code:
   - Off-by-one errors, null/undefined dereferences, unchecked return values
   - Race conditions or missing async/await
   - Incorrect logic (inverted conditions, wrong operators)
   - Missing error handling or silent failures
   - Hardcoded values, magic numbers, or credentials
   - Broken edge cases (empty input, zero, negative values)
   - Inconsistencies between the diff and the surrounding code context
   - Any TODO/FIXME/HACK comments introduced
   Report each potential bug with: file, line range, description, and severity (low/medium/high).

## Notes

- Uses three-dot syntax (`BASE...HEAD`) to show only what diverged from the base branch, not what the base has that the branch doesn't.
- If there are no changes, say so clearly.
