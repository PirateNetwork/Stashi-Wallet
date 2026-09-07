param(
    [Parameter(Mandatory)][string]$SourceDir,
    [Parameter(Mandatory)][string]$OutputDir,
    [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$AppVersion,
    [string]$ComponentAssetDir,
    [switch]$IncludeI2pd = $true,
    [string]$OutputBaseFilename = 'Stashi-Wallet-windows-installer-unsigned',
    [string]$IsccPath = 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe'
)
$ErrorActionPreference = 'Stop'
$SourceDir = (Resolve-Path -LiteralPath $SourceDir).Path
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$OutputDir = (Resolve-Path -LiteralPath $OutputDir).Path
if (-not (Test-Path -LiteralPath $IsccPath)) { throw 'Install Inno Setup 6.5 or newer, or supply IsccPath.' }
if (-not (Test-Path -LiteralPath (Join-Path $SourceDir 'Stashi Wallet.exe'))) { throw 'Wallet executable missing.' }

# A warm output directory must not republish removed helpers from an old build.
$retiredAssets = @('snowflake-client.exe', 'obfs4proxy.exe')
if (-not $IncludeI2pd) { $retiredAssets += 'i2pd.exe' }
foreach ($retired in $retiredAssets) {
    foreach ($suffix in @('', '.sha256', '.provenance.json')) {
        $obsolete = Join-Path $OutputDir "Stashi-Wallet-windows-component-$retired$suffix"
        if (Test-Path -LiteralPath $obsolete) { Remove-Item -LiteralPath $obsolete -Force }
    }
}

# Each optional executable is visible as its own release asset. Hashes are
# compiled into the authenticated installer; never fetch an unpinned latest URL.
$components = @(
    @{ Path = 'tor-pt\lyrebird.exe'; Component = 'bridges' }
)
if ($IncludeI2pd) { $components += @{ Path = 'i2p\i2pd.exe'; Component = 'i2p' } }
if ($ComponentAssetDir) { $ComponentAssetDir = (Resolve-Path -LiteralPath $ComponentAssetDir).Path }
$entries = @(foreach ($component in $components) {
    $name = Split-Path $component.Path -Leaf
    $asset = "Stashi-Wallet-windows-component-$name"
    $source = if ($ComponentAssetDir) { Join-Path $ComponentAssetDir $asset } else { Join-Path $SourceDir $component.Path }
    if (-not (Test-Path -LiteralPath $source)) { throw "Missing privacy component: $($component.Path)" }
    $provenanceFile = "$source.provenance.json"
    if (-not (Test-Path -LiteralPath $provenanceFile)) { throw "Missing component provenance; rerun fetch-tor-i2p-assets.ps1: $source" }
    $provenance = Get-Content -LiteralPath $provenanceFile -Raw | ConvertFrom-Json
    $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($provenance.sha256 -ne $sourceHash -or $provenance.modified -ne $false) {
        throw "Privacy component differs from verified upstream bytes: $source"
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $source
    if ($signature.Status -eq 'HashMismatch') { throw "Corrupt component signature: $source" }
    $destination = Join-Path $OutputDir $asset
    if ([IO.Path]::GetFullPath($source) -ne [IO.Path]::GetFullPath($destination)) {
        Copy-Item -LiteralPath $source -Destination $destination -Force
        Copy-Item -LiteralPath $provenanceFile -Destination "$destination.provenance.json" -Force
    }
    $hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne $sourceHash) { throw "Component changed during packaging: $asset" }
    "$hash  $asset" | Set-Content -LiteralPath "$destination.sha256" -Encoding ascii
    $size = (Get-Item -LiteralPath $destination).Length
    $folder = Split-Path $component.Path -Parent
    $url = "https://github.com/PirateNetwork/Pirate-Unified-Light-Wallet/releases/download/v$AppVersion/$asset"
    "Source: `"$url`"; DestDir: `"{app}\$folder`"; DestName: `"$name`"; ExternalSize: $size; Hash: `"$hash`"; Components: $($component.Component); Flags: external download ignoreversion"
})
# License notices are part of the installer; only executables are downloaded.
$licenseAsset = 'Stashi-Wallet-windows-component-lyrebird.LICENSE.txt'
$licenseSource = if ($ComponentAssetDir) { Join-Path $ComponentAssetDir $licenseAsset } else { Join-Path $SourceDir 'tor-pt\lyrebird.LICENSE.txt' }
$licenseDestination = Join-Path $OutputDir $licenseAsset
if ([IO.Path]::GetFullPath($licenseSource) -ne [IO.Path]::GetFullPath($licenseDestination)) {
    Copy-Item -LiteralPath $licenseSource -Destination $licenseDestination -Force
}
$entries += "Source: `"$licenseDestination`"; DestDir: `"{app}\tor-pt`"; DestName: `"lyrebird.LICENSE.txt`"; Components: bridges; Flags: ignoreversion"
$include = Join-Path $OutputDir 'windows-components.iss'
$entries | Set-Content -LiteralPath $include -Encoding utf8
& $IsccPath "/DSourceDir=$SourceDir" "/DOutputDir=$OutputDir" "/DOutputBaseFilename=$OutputBaseFilename" "/DAppVersion=$AppVersion" "/DComponentsFile=$include" "/DIncludeI2pd=$([int]$IncludeI2pd.IsPresent)" (Join-Path $PSScriptRoot 'windows-installer.iss')
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed: $LASTEXITCODE" }
