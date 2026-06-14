---
name: diff-prev
description: Use when you want to see what changed in the most recent commit compared to the one before it.
---

# diff-prev

Show and summarize the changes introduced by the latest commit (`HEAD`) compared to the previous commit (`HEAD~1`).

## Steps

1. Run:
   ```bash
   git diff HEAD~1 HEAD
   ```
2. For a quick overview of what files changed:
   ```bash
   git diff HEAD~1 HEAD --stat
   ```
3. Summarize:
   - What files were modified, added, or deleted
   - What the commit did (feature, fix, refactor, etc.)
   - Any concerns or noteworthy patterns

4. Check for possible bugs in the changed code:
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

- This always refers to the single most recent commit. To inspect an older commit, use `HEAD~2`, `HEAD~3`, etc.
- You can also show the commit message for context:
  ```bash
  git log -1 --pretty=format:"%h %s%n%b"
  ```
