# Registers the BOM-stripping Git clean filter for this clone.
#
# Git cannot run a filter just because .gitattributes names one; the command
# must exist in the repository's Git config. Run this script once after
# cloning, and again only if the repository moves to a different path.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\setup-git-filters.ps1
#
# The script also adds the BOM to unmodified sources in the current checkout,
# so the first B4J save does not change their size.
#
# On an older clone that still has BOM-bearing blobs, normalize them once:
#
#   git add --renormalize .
#   git commit -m "normalize B4J sources without BOM"
#   git add .
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

# A clone happened before the filter existed, so its files are BOM-free and the
# first IDE save would change their size. Give unmodified sources the BOM now.
# Skip files with local edits so this never stages work in progress.
$normalized = 0
$skipped = 0
foreach ($path in (& git -C $repoRoot ls-files '*.bas' '*.b4j')) {
    $fullPath = Join-Path $repoRoot ($path -replace '/', '\')
    if (-not (Test-Path -LiteralPath $fullPath)) { continue }

    $bytes = [IO.File]::ReadAllBytes($fullPath)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { continue }

    & git -C $repoRoot diff --quiet -- $path
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Not touching $path because it has local changes."
        $skipped++
        continue
    }

    [IO.File]::WriteAllBytes($fullPath, ([byte[]](0xEF, 0xBB, 0xBF) + $bytes))
    # The clean filter removes the BOM again, so this only refreshes the index
    # stat data and stages no content change.
    & git -C $repoRoot add -- $path
    if ($LASTEXITCODE -ne 0) { throw "Failed to refresh the index for $path" }
    $normalized++
}

Write-Host "Registered filter.stripbom in $repoRoot"
Write-Host "  clean:  $cleanCommand"
Write-Host "  smudge: $smudgeCommand"
Write-Host "  required: true"
Write-Host "  worktree BOM normalization: $normalized file(s)"
if (0 -lt $skipped) {
    Write-Host "  skipped $skipped file(s) with local changes; save them once in B4J."
}
Write-Host ''
Write-Host 'Existing blobs are normalized already. On an older clone run'
Write-Host '"git add --renormalize .", commit, then "git add ." once more.'
