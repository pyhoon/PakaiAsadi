# Git smudge filter: copy stdin to stdout, ensuring one leading UTF-8 BOM.
# Used together with strip-bom.ps1 so the working tree always matches what the
# B4J IDE writes. The committed blob stays BOM-free, and a save that only keeps
# the existing BOM does not change the file size or show up as a diff.
#
# Run tools/setup-git-filters.ps1 once per clone to register the filter.

$ErrorActionPreference = 'Stop'

$inputStream = [Console]::OpenStandardInput()
$outputStream = [Console]::OpenStandardOutput()
$buffer = New-Object System.IO.MemoryStream

try {
    $inputStream.CopyTo($buffer)
    $bytes = $buffer.ToArray()

    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    if (-not $hasBom) {
        $outputStream.WriteByte(0xEF)
        $outputStream.WriteByte(0xBB)
        $outputStream.WriteByte(0xBF)
    }
    $outputStream.Write($bytes, 0, $bytes.Length)
    $outputStream.Flush()
}
finally {
    $buffer.Dispose()
}
