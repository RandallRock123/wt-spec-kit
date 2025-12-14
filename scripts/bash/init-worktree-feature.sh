#!/usr/bin/env bash
# Initialize a feature spec in a git worktree using the current branch
# This script does NOT create a new branch - it uses the existing one

set -e

JSON_MODE=false
ARGS=()
i=1
while [ $i -le $# ]; do
    arg="${!i}"
    case "$arg" in
        --json)
            JSON_MODE=true
            ;;
        --help|-h)
            echo "Usage: $0 [--json] <feature_description>"
            echo ""
            echo "Initialize a feature specification using the current git branch."
            echo "Designed for git worktree workflows where the branch already exists."
            echo ""
            echo "Options:"
            echo "  --json        Output in JSON format"
            echo "  --help, -h    Show this help message"
            echo ""
            echo "Prerequisites:"
            echo "  - Must be on a branch matching pattern: ###-feature-name (e.g., 042-user-auth)"
            echo "  - Branch must already exist (created via 'git worktree add')"
            echo ""
            echo "Examples:"
            echo "  # In a worktree on branch 042-user-auth:"
            echo "  $0 'Add user authentication system'"
            exit 0
            ;;
        *)
            ARGS+=("$arg")
            ;;
    esac
    i=$((i + 1))
done

FEATURE_DESCRIPTION="${ARGS[*]}"
if [ -z "$FEATURE_DESCRIPTION" ]; then
    echo "Usage: $0 [--json] <feature_description>" >&2
    echo "Error: Feature description is required" >&2
    exit 1
fi

# Function to find the repository root by searching for existing project markers
find_repo_root() {
    local dir="$1"
    while [ "$dir" != "/" ]; do
        if [ -d "$dir/.git" ] || [ -f "$dir/.git" ] || [ -d "$dir/.specify" ]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

# Resolve repository root
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# For worktrees, .git is a file pointing to the main repo's .git directory
if git rev-parse --show-toplevel >/dev/null 2>&1; then
    REPO_ROOT=$(git rev-parse --show-toplevel)
    HAS_GIT=true
else
    REPO_ROOT="$(find_repo_root "$SCRIPT_DIR")"
    if [ -z "$REPO_ROOT" ]; then
        echo "Error: Could not determine repository root. Please run this script from within a git worktree." >&2
        exit 1
    fi
    HAS_GIT=false
fi

cd "$REPO_ROOT"

# Validate we're in a git repository
if [ "$HAS_GIT" != true ]; then
    echo "Error: This command requires a git repository. Use /speckit.specify for non-git repos." >&2
    exit 1
fi

# Get current branch name
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

if [ -z "$CURRENT_BRANCH" ] || [ "$CURRENT_BRANCH" = "HEAD" ]; then
    echo "Error: Not on a valid branch. You may be in detached HEAD state." >&2
    echo "Please checkout a feature branch before running this command." >&2
    exit 1
fi

# Validate branch name matches ###-name pattern
if ! echo "$CURRENT_BRANCH" | grep -qE '^[0-9]{3}-'; then
    echo "Error: Current branch '$CURRENT_BRANCH' does not match required pattern." >&2
    echo "" >&2
    echo "Expected pattern: ###-feature-name (e.g., 042-user-auth)" >&2
    echo "" >&2
    echo "To use this command:" >&2
    echo "  1. Create a branch with the correct pattern: git branch 042-my-feature" >&2
    echo "  2. Create a worktree: git worktree add ../my-feature 042-my-feature" >&2
    echo "  3. Navigate to the worktree and run this command" >&2
    echo "" >&2
    echo "Or use /speckit.specify to auto-generate a numbered branch." >&2
    exit 1
fi

# Check if we're on main/master (common mistake)
if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
    echo "Error: Cannot run on '$CURRENT_BRANCH' branch." >&2
    echo "Please checkout or create a feature branch first." >&2
    exit 1
fi

# Extract feature number from branch name
FEATURE_NUM=$(echo "$CURRENT_BRANCH" | grep -oE '^[0-9]{3}')
BRANCH_NAME="$CURRENT_BRANCH"

SPECS_DIR="$REPO_ROOT/specs"
mkdir -p "$SPECS_DIR"

FEATURE_DIR="$SPECS_DIR/$BRANCH_NAME"

# Check if spec directory already exists
if [ -d "$FEATURE_DIR" ]; then
    SPEC_FILE="$FEATURE_DIR/spec.md"
    if [ -f "$SPEC_FILE" ]; then
        >&2 echo "[wt-specify] Warning: Spec directory already exists at $FEATURE_DIR"
        >&2 echo "[wt-specify] Existing spec.md will be used. Delete it manually if you want to start fresh."
    fi
else
    mkdir -p "$FEATURE_DIR"
fi

TEMPLATE="$REPO_ROOT/.specify/templates/spec-template.md"
SPEC_FILE="$FEATURE_DIR/spec.md"

# Only copy template if spec doesn't exist
if [ ! -f "$SPEC_FILE" ]; then
    if [ -f "$TEMPLATE" ]; then
        cp "$TEMPLATE" "$SPEC_FILE"
    else
        touch "$SPEC_FILE"
    fi
fi

# Set the SPECIFY_FEATURE environment variable for the current session
export SPECIFY_FEATURE="$BRANCH_NAME"

if $JSON_MODE; then
    printf '{"BRANCH_NAME":"%s","SPEC_FILE":"%s","FEATURE_NUM":"%s"}\n' "$BRANCH_NAME" "$SPEC_FILE" "$FEATURE_NUM"
else
    echo "BRANCH_NAME: $BRANCH_NAME"
    echo "SPEC_FILE: $SPEC_FILE"
    echo "FEATURE_NUM: $FEATURE_NUM"
    echo "SPECIFY_FEATURE environment variable set to: $BRANCH_NAME"
fi
