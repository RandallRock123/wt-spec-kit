#!/usr/bin/env pwsh
# Initialize a feature spec in a git worktree using the current branch
# This script does NOT create a new branch - it uses the existing one

[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$Help,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$FeatureDescription
)
$ErrorActionPreference = 'Stop'

# Show help if requested
if ($Help) {
    Write-Host "Usage: ./init-worktree-feature.ps1 [-Json] <feature description>"
    Write-Host ""
    Write-Host "Initialize a feature specification using the current git branch."
    Write-Host "Designed for git worktree workflows where the branch already exists."
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Json         Output in JSON format"
    Write-Host "  -Help         Show this help message"
    Write-Host ""
    Write-Host "Prerequisites:"
    Write-Host "  - Must be on a branch matching pattern: ###-feature-name (e.g., 042-user-auth)"
    Write-Host "  - Branch must already exist (created via 'git worktree add')"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  # In a worktree on branch 042-user-auth:"
    Write-Host "  ./init-worktree-feature.ps1 'Add user authentication system'"
    exit 0
}

# Check if feature description provided
if (-not $FeatureDescription -or $FeatureDescription.Count -eq 0) {
    Write-Error "Usage: ./init-worktree-feature.ps1 [-Json] <feature description>`nError: Feature description is required"
    exit 1
}

$featureDesc = ($FeatureDescription -join ' ').Trim()

# Function to find the repository root by searching for existing project markers
function Find-RepositoryRoot {
    param(
        [string]$StartDir,
        [string[]]$Markers = @('.git', '.specify')
    )
    $current = Resolve-Path $StartDir
    while ($true) {
        foreach ($marker in $Markers) {
            $markerPath = Join-Path $current $marker
            # Check for both directory (.git in main repo) and file (.git in worktree)
            if (Test-Path $markerPath) {
                return $current
            }
        }
        $parent = Split-Path $current -Parent
        if ($parent -eq $current) {
            # Reached filesystem root without finding markers
            return $null
        }
        $current = $parent
    }
}

# Resolve repository root
$fallbackRoot = (Find-RepositoryRoot -StartDir $PSScriptRoot)
if (-not $fallbackRoot) {
    Write-Error "Error: Could not determine repository root. Please run this script from within a git worktree."
    exit 1
}

try {
    $repoRoot = git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -eq 0) {
        $hasGit = $true
    } else {
        throw "Git not available"
    }
} catch {
    $repoRoot = $fallbackRoot
    $hasGit = $false
}

Set-Location $repoRoot

# Validate we're in a git repository
if (-not $hasGit) {
    Write-Error "Error: This command requires a git repository. Use /speckit.specify for non-git repos."
    exit 1
}

# Get current branch name
try {
    $currentBranch = git rev-parse --abbrev-ref HEAD 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($currentBranch)) {
        throw "Could not get branch name"
    }
} catch {
    Write-Error "Error: Could not determine current branch."
    exit 1
}

if ($currentBranch -eq "HEAD") {
    Write-Error "Error: Not on a valid branch. You may be in detached HEAD state.`nPlease checkout a feature branch before running this command."
    exit 1
}

# Validate branch name matches ###-name pattern
if ($currentBranch -notmatch '^\d{3}-') {
    Write-Error @"
Error: Current branch '$currentBranch' does not match required pattern.

Expected pattern: ###-feature-name (e.g., 042-user-auth)

To use this command:
  1. Create a branch with the correct pattern: git branch 042-my-feature
  2. Create a worktree: git worktree add ../my-feature 042-my-feature
  3. Navigate to the worktree and run this command

Or use /speckit.specify to auto-generate a numbered branch.
"@
    exit 1
}

# Check if we're on main/master (common mistake)
if ($currentBranch -eq "main" -or $currentBranch -eq "master") {
    Write-Error "Error: Cannot run on '$currentBranch' branch.`nPlease checkout or create a feature branch first."
    exit 1
}

# Extract feature number from branch name
$featureNum = ($currentBranch -replace '^(\d{3}).*', '$1')
$branchName = $currentBranch

$specsDir = Join-Path $repoRoot 'specs'
New-Item -ItemType Directory -Path $specsDir -Force | Out-Null

$featureDir = Join-Path $specsDir $branchName
$specFile = Join-Path $featureDir 'spec.md'

# Check if spec directory already exists
if (Test-Path $featureDir) {
    if (Test-Path $specFile) {
        Write-Warning "[wt-specify] Spec directory already exists at $featureDir"
        Write-Warning "[wt-specify] Existing spec.md will be used. Delete it manually if you want to start fresh."
    }
} else {
    New-Item -ItemType Directory -Path $featureDir -Force | Out-Null
}

$template = Join-Path $repoRoot '.specify/templates/spec-template.md'

# Only copy template if spec doesn't exist
if (-not (Test-Path $specFile)) {
    if (Test-Path $template) {
        Copy-Item $template $specFile -Force
    } else {
        New-Item -ItemType File -Path $specFile | Out-Null
    }
}

# Set the SPECIFY_FEATURE environment variable for the current session
$env:SPECIFY_FEATURE = $branchName

if ($Json) {
    $obj = [PSCustomObject]@{
        BRANCH_NAME = $branchName
        SPEC_FILE = $specFile
        FEATURE_NUM = $featureNum
    }
    $obj | ConvertTo-Json -Compress
} else {
    Write-Output "BRANCH_NAME: $branchName"
    Write-Output "SPEC_FILE: $specFile"
    Write-Output "FEATURE_NUM: $featureNum"
    Write-Output "SPECIFY_FEATURE environment variable set to: $branchName"
}
