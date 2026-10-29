# Registers the BOM-stripping Git clean filter for this clone.
#
# Git cannot run a filter just because .gitattributes names one; the command
# must exist in the repository's Git config. Run this script once after
# cloning, and again only if the repository moves to a different path.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\setup-git-filters.ps1
#
# After registering the filter, normalize existing blobs once:
#
#   git add --renormalize .
#   git commit -m "normalize B4J sources without BOM"
#
# See AGENT.md for the full rationale.

$ErrorActionPreference = 'Stop'

$repoRoot = (& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repoRoot)) {
    throw "Not inside a Git working tree: $PSScriptRoot"
}
$repoRoot = $repoRoot.Trim()

$filterScript = Join-Path $repoRoot 'tools/strip-bom.ps1'
if (-not (Test-Path -LiteralPath $filterScript)) {
    throw "Missing filter script: $filterScript"
}

# Git runs the command through the shell, so use forward slashes and quote the
# path to survive spaces in the checkout location.
$filterPath = ($filterScript -replace '\\', '/')
$cleanCommand = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + $filterPath + '"'

$smudgeScript = Join-Path $repoRoot 'tools/add-bom.ps1'
if (-not (Test-Path -LiteralPath $smudgeScript)) {
    throw "Missing filter script: $smudgeScript"
}
$smudgePath = ($smudgeScript -replace '\\', '/')
$smudgeCommand = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + $smudgePath + '"'

& git -C $repoRoot config --local filter.stripbom.clean $cleanCommand
if ($LASTEXITCODE -ne 0) { throw 'Failed to set filter.stripbom.clean' }

# Checkout restores the BOM so the working tree matches what B4J writes. That
# keeps the file size stable across IDE saves, which is what lets git status
# stay clean instead of showing a size-only change.
& git -C $repoRoot config --local filter.stripbom.smudge $smudgeCommand
if ($LASTEXITCODE -ne 0) { throw 'Failed to set filter.stripbom.smudge' }

# Fail loudly if the filter disappears instead of silently committing BOMs.
& git -C $repoRoot config --local filter.stripbom.required 'true'
if ($LASTEXITCODE -ne 0) { throw 'Failed to set filter.stripbom.required' }

Write-Host "Registered filter.stripbom in $repoRoot"
Write-Host "  clean:  $cleanCommand"
Write-Host "  smudge: $smudgeCommand"
Write-Host "  required: true"
Write-Host ''
Write-Host 'Run "git add --renormalize ." once to strip BOMs from existing blobs,'
Write-Host 'then "git add ." once more so the index records the working-tree sizes.'
