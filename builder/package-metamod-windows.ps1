param(
    [Parameter(Mandatory = $true)][string]$PackageDir,
    [Parameter(Mandatory = $true)][string]$OutputDir,
    [Parameter(Mandatory = $true)][string]$MmsDir
)

$ErrorActionPreference = 'Stop'

$version = (Get-Content -Raw "$MmsDir/product.version").Trim()
$filename = "mmsource-$version-css34-windows.zip"
$archive = Join-Path (Resolve-Path $OutputDir) $filename

$required = @(
    'addons/metamod.vdf',
    'addons/metamod/bin/metamod.1.ep1.dll',
    'addons/metamod/bin/server.dll'
)

foreach ($rel in $required) {
    $path = Join-Path $PackageDir $rel
    if (-not (Test-Path $path)) {
        throw "Missing required Metamod package file: $rel"
    }
}

$staging = Join-Path $env:TEMP ("mm-css34-package-" + [guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $staging | Out-Null
try {
    Copy-Item -Recurse (Join-Path $PackageDir 'addons') (Join-Path $staging 'addons')

    $vdf = Join-Path $staging 'addons/metamod.vdf'
    $vdfText = Get-Content -Raw $vdf
    if ($vdfText -notmatch '"file"\s+"addons/metamod/bin/server"') {
        throw 'Invalid Metamod VDF path; package would load outside the active game root'
    }

    if (Test-Path $archive) {
        Remove-Item $archive
    }
    Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $archive
}
finally {
    Remove-Item -Recurse -Force $staging
}

Write-Output $archive
