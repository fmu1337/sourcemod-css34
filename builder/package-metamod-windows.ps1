param(
    [Parameter(Mandatory = $true)][string]$PackageDir,
    [Parameter(Mandatory = $true)][string]$OutputDir,
    [Parameter(Mandatory = $true)][string]$MmsDir
)

$ErrorActionPreference = 'Stop'

$version = (Get-Content -Raw "$MmsDir/product.version").Trim()
$filename = "mmsource-$version-css34-windows.zip"
$archive = Join-Path (Resolve-Path $OutputDir) $filename

$mmCore = $null
foreach ($cand in @('metamod.2.ep1.dll', 'metamod.1.ep1.dll')) {
    if (Test-Path (Join-Path $PackageDir "addons/metamod/bin/$cand")) {
        $mmCore = $cand
        break
    }
}
if (-not $mmCore) {
    throw "Missing metamod.2.ep1.dll / metamod.1.ep1.dll in Metamod package"
}

$required = @(
    'addons/metamod.vdf',
    "addons/metamod/bin/$mmCore",
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

    # Match rom4s/css34 gameinfo path (relative to hl2/cstrike).
    $vdf = Join-Path $staging 'addons/metamod.vdf'
    if (Test-Path $vdf) {
        $text = Get-Content -Raw $vdf
        $text = [regex]::Replace(
            $text,
            '"file"\s+"addons/metamod/bin/server"',
            "`"file`"`t`"../cstrike/addons/metamod/bin/server`""
        )
        Set-Content -NoNewline -Path $vdf -Value $text
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
