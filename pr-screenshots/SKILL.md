---
name: pr-screenshots
description: Take playwright-cli screenshots of a feature, upload them to a GitHub release, and embed them in a PR description. Works for any GitHub repo.
model: sonnet
---

# pr-screenshots

## Overview

Takes screenshots of a running local UI, uploads them as assets on a GitHub prerelease, and embeds them in a PR body. This is the only approach that produces visible inline images in GitHub PR descriptions for private repos — `raw.githubusercontent.com` URLs require auth and will appear broken.

**Key facts learned from practice:**
- GitHub release asset download URLs are publicly accessible even on private repos.
- The release must be **published** (not draft) for the URLs to resolve.
- `gh release upload` preserves the original filename unless you use the `file#alias` syntax — always provide aliases.
- Delete the release after the PR merges (it only exists to host images).

## Inputs

- **PR number** — inferred from current branch if omitted (`gh pr view --json number`).
- **Repo** — inferred from `gh repo view --json nameWithOwner` in cwd if omitted.
- **Screenshots** — paths passed as arguments, or taken automatically via `playwright-cli` if none given.
- **URLs to screenshot** — only needed when taking screenshots automatically.

## Workflow

### Step 1 — Resolve PR and repo

```bash
PR_NUM=$(gh pr view --json number --jq .number)
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
```

### Step 2 — Take screenshots (if not provided)

Use `playwright-cli` to navigate to each URL and capture screenshots. Save to a temp dir:

```bash
JOB_DIR="${CLAUDE_JOB_DIR:-/tmp}"
playwright-cli open <url>
# fill form / navigate as needed
playwright-cli screenshot   # saves to .playwright-cli/page-<timestamp>.png
```

Collect the paths. Give each a short descriptive alias (e.g. `step1-form.png`, `success-card.png`).

### Step 2.5 — Redact sensitive/client data BEFORE capturing

Default to capturing the screenshot — do not skip a view just because it shows real data. If the frame contains PII (client/portfolio names, balances, returns, account numbers, emails), redact it **in the DOM before** `playwright-cli screenshot`, then capture. Prefer, in order:

1. **Dummy data (preferred — looks natural).** Replace the sensitive text nodes with synthetic values:
   ```bash
   playwright-cli eval "() => {
     const map = [['.portfolio-name','Demo Portfolio'], ['.client-name','Cliente Demo']];
     map.forEach(([sel,val]) => document.querySelectorAll(sel).forEach(el => el.textContent = val));
     // numeric/currency cells → a fixed dummy figure
     document.querySelectorAll('.balance, .amount, [data-currency]').forEach(el => el.textContent = '\$1,234.56');
   }"
   ```
2. **Blur (when text can't be cleanly swapped).** Apply a CSS blur to the sensitive elements:
   ```bash
   playwright-cli eval "() => document.querySelectorAll('.portfolio-name, .balance, .client-selector')
     .forEach(el => { el.style.filter = 'blur(6px)'; })"
   ```

Adjust selectors to the actual app (inspect the snapshot/DOM first). Re-`snapshot` to confirm the values changed, then `playwright-cli screenshot`. Only fall back to a textual description (no image) if neither redaction is feasible. App-specific selectors and a no-PII login path live in the project's own screenshot/login skill (e.g. `wiq-login`).

### Step 3 — Create a prerelease to host the images

Tag name: `pr-<N>-screenshots` (e.g. `pr-52-screenshots`).

```bash
gh release create "pr-${PR_NUM}-screenshots" \
  --repo "$REPO" \
  --title "PR #${PR_NUM} screenshots" \
  --notes "Screenshot assets for PR #${PR_NUM} — delete this release after the PR merges." \
  --prerelease
```

Do NOT use `--draft` — draft release assets are not publicly accessible and images will appear broken.

### Step 4 — Upload screenshots

Upload each file directly — do NOT use the `file#alias` syntax. The `#alias` only sets the display label; the download URL always uses the **original filename**. Rename the files to clean names before uploading:

```bash
cp /path/to/page-timestamp1.png /tmp/step1-form.png
cp /path/to/page-timestamp2.png /tmp/success-card.png

gh release upload "pr-${PR_NUM}-screenshots" \
  --repo "$REPO" \
  "/tmp/step1-form.png" \
  "/tmp/success-card.png"
```

### Step 5 — Build download URLs

```bash
BASE="https://github.com/${REPO}/releases/download/pr-${PR_NUM}-screenshots"
# URLs use the actual uploaded filenames:
# ${BASE}/step1-form.png
# ${BASE}/success-card.png
```

### Step 6 — Embed in PR body

Read the current PR body, inject a `## Screenshots` section with a markdown table, and update:

```bash
gh pr edit "$PR_NUM" --repo "$REPO" --body "$(cat <<'EOF'
... existing body ...

## Screenshots

| Step 1 | Success |
|---|---|
| ![step1](${BASE}/step1-form.png) | ![success](${BASE}/success-card.png) |

EOF
)"
```

### Step 7 — Output

Print:
```
PR #<N>: <k> screenshots embedded.
Release: https://github.com/<repo>/releases/tag/pr-<N>-screenshots
⚠ Delete the release after the PR merges.
```

## Layout patterns

### Desktop + mobile side-by-side, one subsection per feature/step

For multi-step wizards (or any feature with multiple screens), organize the PR's
`## Screenshots` section as **one subsection per step**, each containing a
two-column markdown table with Desktop and Mobile screenshots side by side.
This mirrors the "match Figma on both viewports" rule that most frontends
enforce, and lets the reviewer compare layouts at a glance without scrolling.

Template:

````markdown
## Screenshots

### Landing
| Desktop | Mobile |
|---|---|
| ![landing-d](${BASE}/01-landing-desktop.png) | ![landing-m](${BASE}/02-landing-mobile.png) |

### Step name
| Desktop | Mobile |
|---|---|
| ![step-d](${BASE}/03-step-desktop.png) | ![step-m](${BASE}/04-step-mobile.png) |
````

### Multi-state steps (conditional UI)

For a single step that renders multiple meaningful UI states (e.g. a Sí/No
toggle that reveals different sub-forms), promote each state to its own row of
a wider table — keep desktop + mobile adjacent within each state so the pair
stays comparable:

````markdown
### Paso 3 — Datos del ELD (all conditional states)
States: opt-in collapsed, Sí + misma cuenta Sí, misma cuenta No + Depósito,
misma cuenta No + Vale vista.

| Mobile — collapsed | Desktop — misma cuenta Sí | Mobile — misma cuenta Sí |
|---|---|---|
| ![](${BASE}/15-eld-collapsed-mobile.png) | ![](${BASE}/16-eld-misma-desktop.png) | ![](${BASE}/17-eld-misma-mobile.png) |

| Desktop — Depósito | Mobile — Depósito | Desktop — Vale vista | Mobile — Vale vista |
|---|---|---|---|
| ![](${BASE}/18-eld-deposito-desktop.png) | ![](${BASE}/19-eld-deposito-mobile.png) | ![](${BASE}/20-eld-vale-desktop.png) | ![](${BASE}/21-eld-vale-mobile.png) |
````

### Filename convention

Capture screenshots with **numbered + descriptive** filenames so the upload
list and the embed table stay aligned and self-documenting:

- `<NN>-<step>-<viewport>.png` — e.g. `01-landing-desktop.png`,
  `08-landing-mobile.png`, `14-seleccion-asesor-mobile.png`.
- A two-digit prefix sets the natural sort order in
  `gh release view --json assets --jq '.assets[].name'`.
- Trailing `-desktop` / `-mobile` makes the viewport explicit so reviewers (and
  later you) spot missing pairs at a glance.

### Capture order

For each step, capture the **default state first** (no interaction needed),
then any conditional states. Always do desktop first at `1440 × 900`, then
resize to mobile (`393 × 852`) and re-walk the same flow. State-driven
conditionals (asesor sub-form expanded, "ELD = Sí" branches, etc.) require
click navigation, not `goto`, so the in-memory wizard state persists between
captures.

## Common mistakes

- **Using `--draft`**: Draft release assets are NOT accessible without authentication — images show as broken. Always use `--prerelease` (no `--draft`).
- **Using `file#alias` in `gh release upload`**: The `#alias` only sets the display label — the download URL always uses the **original filename**. Always copy/rename the file to a clean name before uploading so the URL is readable.
- **Using `raw.githubusercontent.com`**: These URLs require authentication on private repos. They always appear broken in PR descriptions. Use release asset URLs instead.
- **Using `uploads.github.com` directly**: This endpoint requires multipart form data in a specific undocumented format. Use `gh release upload` instead — it handles the upload correctly.
- **Forgetting to delete the release**: Remind the user to delete `pr-<N>-screenshots` after the PR merges. It's clutter and the assets will be orphaned.

## Cleanup reminder

After the PR is merged, delete the release:
```bash
gh release delete "pr-${PR_NUM}-screenshots" --repo "$REPO" --yes
git push origin --delete "pr-${PR_NUM}-screenshots"
