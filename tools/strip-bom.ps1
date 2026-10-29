# Git clean filter: copy stdin to stdout, dropping one leading UTF-8 BOM.
# B4J's IDE writes a BOM when it saves a .bas or .b4j file. The BOM is not
# meaningful to the compiler, but it makes Git see a change on every save.
# Configuring this as filter.stripbom.clean keeps committed blobs BOM-free
# while leaving the working tree exactly as the IDE saved it.
#
# Run tools/setup-git-filters.ps1 once per clone to register the filter.

$ErrorActionPreference = 'Stop'

$inputStream = [Console]::OpenStandardInput()
$outputStream = [Console]::OpenStandardOutput()
$buffer = New-Object System.IO.MemoryStream

try {
    $inputStream.CopyTo($buffer)
    $bytes = $buffer.ToArray()

    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $outputStream.Write($bytes, 3, $bytes.Length - 3)
    }
    else {
        $outputStream.Write($bytes, 0, $bytes.Length)
    }
    $outputStream.Flush()
}
finally {
    $buffer.Dispose()
}
