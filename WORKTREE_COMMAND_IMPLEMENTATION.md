# Implementing Worktree-Based Specify Command

This document provides a detailed, self-contained guide for implementing a worktree-compatible version of the `/speckit.specify` command. Follow this guide to add the same functionality to a freshly forked spec-kit repository.

## Problem Statement

The original `/speckit.specify` command creates a new git branch and switches to it:

```bash
/speckit.specify Add user authentication
# → Creates branch 006-user-auth
# → Switches to that branch
# → Creates specs/006-user-auth/spec.md
```

This doesn't work well with **git worktree workflows** where:

1. You create a worktree with a pre-existing branch
2. You want to run `/speckit.specify` inside that worktree
3. The command should use the current branch, not create a new one

**Goal**: Create a new command `/speckit.wt-specify` that works with the current branch instead of creating one.

## Architecture Analysis

### How the Original Command Works

1. **Command file**: `/speckit.specify.md`

   - Defines the AI workflow prompt
   - Steps 1-2: Generate branch name, calculate next number, run script
   - Steps 3-7: Load template, write spec, validate, create checklist

2. **Script**: `create-new-feature.sh`
   - Parses arguments (`--json`, `--short-name`, `--number`)
   - Calculates next feature number from branches and specs directories
   - Creates new branch with `git checkout -b`
   - Creates `specs/<branch>/` directory
   - Copies spec template
   - Outputs JSON: `{"BRANCH_NAME":"...","SPEC_FILE":"...","FEATURE_NUM":"..."}`

### How Downstream Commands Find Features

All downstream commands (`/speckit.plan`, `/speckit.tasks`, `/speckit.clarify`, etc.) use `common.sh`:

```bash
# common.sh - get_current_branch() function
get_current_branch() {
    # First check SPECIFY_FEATURE env var
    if [[ -n "${SPECIFY_FEATURE:-}" ]]; then
        echo "$SPECIFY_FEATURE"
        return
    fi
    # Then check git
    if git rev-parse --abbrev-ref HEAD >/dev/null 2>&1; then
        git rev-parse --abbrev-ref HEAD
        return
    fi
    # Fallback to latest specs directory
    ...
}
```

Key insight: Downstream commands use `git rev-parse --abbrev-ref HEAD` to detect the current branch, then find the matching `specs/<branch>/` directory.

### Compatibility Requirements

For the new command to work with downstream commands:

1. **Same directory structure**: `specs/<branch-name>/spec.md`
2. **Same JSON output fields**: `BRANCH_NAME`, `SPEC_FILE`, `FEATURE_NUM`
3. **Branch naming**: Should follow `###-name` pattern for `find_feature_dir_by_prefix()` to work, user will make sure the worktree & the branch it is on follow `###-name` pattern, you need not to worry about this.

### Spec Quality Consideration

The spec generation workflow (steps 3-7 in original) determines spec quality:

- Loading the template
- Parsing user description
- Extracting concepts (actors, actions, data, constraints)
- Writing spec with max 3 `[NEEDS CLARIFICATION]` markers
- Running validation checklist
- Handling clarifications

**Decision**: Copy the entire spec generation workflow verbatim to ensure identical spec quality.

## Implementation

### Files Created

| File | Purpose |
|------|---------|
| `scripts/bash/init-worktree-feature.sh` | Bash script for worktree initialization |
| `scripts/powershell/init-worktree-feature.ps1` | PowerShell script for worktree initialization |
| `templates/commands/wt-specify.md` | Command definition file |

### 1. Bash Script: `scripts/bash/init-worktree-feature.sh`

Key differences from `create-new-feature.sh`:

- Does NOT create a new branch - uses current branch
- Validates current branch matches `###-name` pattern
- Handles worktrees (where `.git` is a file, not a directory)
- Warns if spec directory already exists (allows resuming work)

**Validation logic:**

```bash
# Get current branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# Validate pattern
if ! echo "$CURRENT_BRANCH" | grep -qE '^[0-9]{3}-'; then
    echo "Error: Branch must match ###-name pattern" >&2
    exit 1
fi

# Extract feature number
FEATURE_NUM=$(echo "$CURRENT_BRANCH" | grep -oE '^[0-9]{3}')
```

**Error cases handled:**

- Not in a git repository → suggests using `/speckit.specify`
- Detached HEAD state → asks user to checkout a branch
- Invalid branch pattern → explains correct pattern and alternatives
- On main/master branch → prevents accidental use

### 2. PowerShell Script: `scripts/powershell/init-worktree-feature.ps1`

Identical logic to bash version, adapted for PowerShell syntax.

### 3. Command File: `templates/commands/wt-specify.md`

**Key differences from `specify.md`:**

- Skips steps 1-2 (branch name generation, number calculation)
- Uses `init-worktree-feature.sh` instead of `create-new-feature.sh`
- Steps 3-7 (spec generation, validation, clarification) copied verbatim

**Script configuration:**

```yaml
scripts:
  sh: scripts/bash/init-worktree-feature.sh --json "{ARGS}"
  ps: scripts/powershell/init-worktree-feature.ps1 -Json "{ARGS}"
```

## Usage

### Workflow Example

```bash
# 1. In main repository, create a numbered branch
git branch 042-user-auth

# 2. Create a worktree for that branch
git worktree add ../user-auth-feature 042-user-auth

# 3. Navigate to worktree
cd ../user-auth-feature

# 4. Run the worktree-compatible specify command
/speckit.wt-specify Add user authentication with OAuth2 support

# 5. Continue with normal workflow
/speckit.plan
/speckit.tasks
```

### When to Use Which Command

| Scenario | Command |
|----------|---------|
| Standard workflow (single directory) | `/speckit.specify` |
| Git worktree with pre-created branch | `/speckit.wt-specify` |
| Non-git repository | `/speckit.specify` |

## Testing

### Test Cases

1. **Valid worktree scenario**

   ```bash
   # Setup
   git branch 001-test-feature
   git worktree add /tmp/test-wt 001-test-feature
   cd /tmp/test-wt

   # Run command - should succeed
   /speckit.wt-specify "Test feature description"

   # Verify
   ls specs/001-test-feature/spec.md  # Should exist
   ```

2. **Invalid branch pattern**

   ```bash
   git checkout -b my-feature  # No number prefix
   /speckit.wt-specify "Test"
   # Should error with helpful message
   ```

3. **Detached HEAD**

   ```bash
   git checkout HEAD~1
   /speckit.wt-specify "Test"
   # Should error asking to checkout a branch
   ```

4. **Downstream command compatibility**

   ```bash
   /speckit.wt-specify "Test feature"
   /speckit.plan  # Should find the spec via get_current_branch()
   ```

## Downstream Compatibility

The new command maintains full compatibility with downstream commands because:

1. **Same directory structure**: `specs/<branch-name>/spec.md`
2. **Same JSON output**: `{"BRANCH_NAME":"...","SPEC_FILE":"...","FEATURE_NUM":"..."}`
3. **`get_current_branch()` works**: Uses `git rev-parse --abbrev-ref HEAD` which works in worktrees
4. **Same spec quality**: Identical generation and validation workflow
