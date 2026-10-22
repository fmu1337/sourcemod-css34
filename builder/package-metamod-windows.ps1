param(
    [Parameter(Mandatory = $true)][string]$PackageDir,
    [Parameter(Mandatory = $true)][string]$OutputDir,
    [Parameter(Mandatory = $true)][string]$MmsDir
)

$ErrorActionPreference = 'Stop'

$python = if (Get-Command python -ErrorAction SilentlyContinue) { 'python' } else { 'python3' }
& $python (Join-Path $PSScriptRoot 'package_windows.py') metamod `
    --package-dir $PackageDir `
    --output-dir $OutputDir `
    --mms-dir $MmsDir
if ($LASTEXITCODE -ne 0) {
    throw "package_windows.py metamod failed ($LASTEXITCODE)"
}
