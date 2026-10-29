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

& git -C $repoRoot config --local filter.stripbom.clean $cleanCommand
if ($LASTEXITCODE -ne 0) { throw 'Failed to set filter.stripbom.clean' }

# Passing content through on checkout keeps the working tree identical to the
# committed bytes. B4J adds the BOM again the next time it saves the file.
& git -C $repoRoot config --local filter.stripbom.smudge 'cat'
if ($LASTEXITCODE -ne 0) { throw 'Failed to set filter.stripbom.smudge' }

# Fail loudly if the filter disappears instead of silently committing BOMs.
& git -C $repoRoot config --local filter.stripbom.required 'true'
if ($LASTEXITCODE -ne 0) { throw 'Failed to set filter.stripbom.required' }

Write-Host "Registered filter.stripbom in $repoRoot"
Write-Host "  clean:  $cleanCommand"
Write-Host "  smudge: cat"
Write-Host "  required: true"
Write-Host ''
Write-Host 'Run "git add --renormalize ." once to strip BOMs from existing blobs.'
