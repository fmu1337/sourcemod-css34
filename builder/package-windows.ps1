param(
    [Parameter(Mandatory = $true)][string]$PackageDir,
    [Parameter(Mandatory = $true)][string]$OutputDir,
    [Parameter(Mandatory = $true)][string]$SourceModDir
)

$ErrorActionPreference = 'Stop'

$gitRev = if ($env:SOURCEMOD_GIT_REV) { $env:SOURCEMOD_GIT_REV } else {
    (git -C $SourceModDir rev-list --count HEAD)
}
$version = (Get-Content -Raw "$SourceModDir/product.version").Trim()
$filename = "sourcemod-$version-git$gitRev-css34-windows.zip"
$archive = Join-Path (Resolve-Path $OutputDir) $filename

# SM 1.12 / MM 1.12 css34: sourcemod.2.ep1 only. Dual 1.ep1+2.ep1 is the 1.11 layout.
$has2 = Test-Path (Join-Path $PackageDir 'addons/sourcemod/bin/sourcemod.2.ep1.dll')
$has1 = Test-Path (Join-Path $PackageDir 'addons/sourcemod/bin/sourcemod.1.ep1.dll')

if ($has2) {
    $required = @(
        'addons/metamod/sourcemod.vdf',
        'addons/sourcemod/bin/sourcemod.2.ep1.dll',
        'addons/sourcemod/extensions/dbi.mysql.ext.dll',
        'addons/sourcemod/extensions/dbi.sqlite.ext.dll',
        'addons/sourcemod/extensions/game.cstrike.ext.2.ep1.dll',
        'addons/sourcemod/gamedata/sm-cstrike.games/game.cstrike.txt',
        'addons/sourcemod/scripting/include/version_auto.inc',
        'cfg/sourcemod/sourcemod.cfg'
    )
} elseif ($has1) {
    $required = @(
        'addons/metamod/sourcemod.vdf',
        'addons/sourcemod/bin/sourcemod.1.ep1.dll',
        'addons/sourcemod/extensions/dbi.mysql.ext.dll',
        'addons/sourcemod/extensions/dbi.sqlite.ext.dll',
        'addons/sourcemod/extensions/game.cstrike.ext.1.ep1.dll',
        'addons/sourcemod/gamedata/sm-cstrike.games/game.cstrike.txt',
        'addons/sourcemod/scripting/include/version_auto.inc',
        'cfg/sourcemod/sourcemod.cfg'
    )
} else {
    throw 'Missing sourcemod.1.ep1.dll / sourcemod.2.ep1.dll'
}

foreach ($rel in $required) {
    $path = Join-Path $PackageDir $rel
    if (-not (Test-Path $path)) {
        throw "Missing required package file: $rel"
    }
}

$staging = Join-Path $env:TEMP ("sm-css34-package-" + [guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $staging | Out-Null
try {
  Copy-Item -Recurse (Join-Path $PackageDir 'addons') (Join-Path $staging 'addons')
  Copy-Item -Recurse (Join-Path $PackageDir 'cfg') (Join-Path $staging 'cfg')
  if (Test-Path $archive) {
    Remove-Item $archive
  }
  Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $archive
}
finally {
  Remove-Item -Recurse -Force $staging
}

Write-Output $archive
