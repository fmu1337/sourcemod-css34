param(
    [Parameter(Mandatory = $true)][string]$PackageDir,
    [Parameter(Mandatory = $true)][string]$OutputDir,
    [Parameter(Mandatory = $true)][string]$SourceModDir
)

$ErrorActionPreference = 'Stop'

$python = if (Get-Command python -ErrorAction SilentlyContinue) { 'python' } else { 'python3' }
& $python (Join-Path $PSScriptRoot 'package_windows.py') sourcemod `
    --package-dir $PackageDir `
    --output-dir $OutputDir `
    --sourcemod-dir $SourceModDir
if ($LASTEXITCODE -ne 0) {
    throw "package_windows.py sourcemod failed ($LASTEXITCODE)"
}
