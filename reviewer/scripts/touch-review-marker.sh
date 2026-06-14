#!/usr/bin/env bash
# Touches .claude/.review-passed at the workspace root.
# Called by reviewer on a clean (zero must-fix) local/branch/file review.
# Only this script writes the marker — executor must NOT call it directly.

set -u

# Resolve workspace root: walk up from cwd until we find a dir that looks like
# a workspace (has both .gitmodules and .claude/settings.json).
find_workspace_root() {
    local dir
    dir="$(git rev-parse --show-toplevel 2>/dev/null)"
    if [ -z "$dir" ]; then
        echo "ERROR: not inside a git repository" >&2
        exit 1
    fi

    # If we're inside a submodule, the toplevel is the submodule root.
    # Walk up until we find the workspace root (identified by .gitmodules).
    local candidate="$dir"
    while [ "$candidate" != "/" ]; do
        if [ -f "$candidate/.gitmodules" ] && [ -f "$candidate/.claude/settings.json" ]; then
            echo "$candidate"
            return 0
        fi
        candidate="$(dirname "$candidate")"
    done

    # Fall back to git toplevel (handles running from inside a single-repo project)
    echo "$dir"
}

WORKSPACE_ROOT="$(find_workspace_root)"
MARKER="$WORKSPACE_ROOT/.claude/.review-passed"

# Create the .claude dir if it doesn't exist (e.g. first run)
mkdir -p "$(dirname "$MARKER")"

touch "$MARKER"
echo "✓ .claude/.review-passed updated at $MARKER"
