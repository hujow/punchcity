<#
.SYNOPSIS
Recursively copies every .lua file in the repo to an “export” folder,
keeping the relative folder structure, and changes the extension to .txt.

.PARAMETER SourceRoot
Top-level folder that contains your Lua project (defaults to script location).

.PARAMETER ExportRoot
Destination folder (defaults to "<SourceRoot>\__export_txt").

.PARAMETER VersionTag
    Optional label (e.g. "0061_190525") appended to the exported filenames.

.EXAMPLE
    .\Export-LuaAsTxt.ps1 -VersionTag 0061_190525
#>

param(
    [string]$SourceRoot  = (Split-Path -LiteralPath $PSCommandPath -Parent),
    [string]$ExportRoot  = (Join-Path $SourceRoot "__export_txt"),
    [string]$VersionTag  = ""
)

Write-Host "🔍  Scanning $SourceRoot for .lua files…"

$luaFiles = Get-ChildItem -Path $SourceRoot -Recurse -Filter *.lua -File
if (-not $luaFiles) {
    Write-Warning "No .lua files found. Aborting."
    return
}

foreach ($file in $luaFiles) {

    # Preserve relative directory
    $relPath   = $file.FullName.Substring($SourceRoot.Length).TrimStart("\")
    $targetDir = Split-Path (Join-Path $ExportRoot $relPath) -Parent
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

    # Build new filename:  originalName[_VersionTag].txt
    $baseName   = [IO.Path]::GetFileNameWithoutExtension($file.Name)
    if ($VersionTag) { $baseName = "$baseName`_$VersionTag" }
    $destFile   = Join-Path $targetDir ($baseName + ".txt")

    Copy-Item -Path $file.FullName -Destination $destFile -Force
}

Write-Host "✅  Export complete.  $(($luaFiles).Count) files ➜ $ExportRoot"
