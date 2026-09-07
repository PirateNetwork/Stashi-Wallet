param(
    [string]$TorBundleVersion = $(if ($env:TOR_EXPERT_BUNDLE_VERSION) { $env:TOR_EXPERT_BUNDLE_VERSION } else { '15.0.21' }),
    [string]$TorBundleUrl = $env:TOR_EXPERT_BUNDLE_WINDOWS_URL,
    [string]$TorBundleSha256 = $(if ($env:TOR_EXPERT_BUNDLE_WINDOWS_SHA256) { $env:TOR_EXPERT_BUNDLE_WINDOWS_SHA256 } else { 'f22b8b17cb18c9fa775dfcf68acf6a2fe788336535fe94645204ca85158aa490' }),
    [string]$I2pdVersion = $(if ($env:I2PD_VERSION) { $env:I2PD_VERSION } else { '2.59.0' }),
    [string]$I2pdBaseUrl = $env:I2PD_BASE_URL,
    [string]$I2pdSha512 = $(if ($env:I2PD_WINDOWS_SHA512) { $env:I2PD_WINDOWS_SHA512 } else { 'c5cae4b2b2166935f1bed9f302f5647e3c201c784a9cf7c4a605ca47906b57358ffe3ce6b45762d4857ce060299e17e1a3ea70f8f1e3f72472b87ea7bb96d0b5' }),
    [ValidateSet('i2p', 'bridges')][string[]]$Components = @('i2p', 'bridges')
)
$ErrorActionPreference = 'Stop'
if ($env:SKIP_TOR_I2P_FETCH -eq '1') {
    Write-Host '[INFO] Skipping Tor/I2P asset fetch (SKIP_TOR_I2P_FETCH=1).'
    exit 0
}
if (-not $I2pdBaseUrl) {
    $I2pdBaseUrl = "https://github.com/PurpleI2P/i2pd/releases/download/$I2pdVersion"
}
if (-not $TorBundleUrl) {
    $TorBundleUrl = "https://archive.torproject.org/tor-package-archive/torbrowser/$TorBundleVersion/tor-expert-bundle-windows-x86_64-$TorBundleVersion.tar.gz"
}
# Windows releases use exact upstream bytes, not locally rebuilt/re-signed PTs.
# SHA-256 source: the Tor release's sha256sums-signed-build.txt.
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$appDir = Join-Path $projectRoot 'app'

function Download-VerifiedArchive {
    param([string]$Url, [string]$Destination, [string]$Algorithm, [string]$Expected)
    if (-not $Expected) { throw "Missing pinned $Algorithm checksum for $Url" }
    $curl = Get-Command curl.exe -ErrorAction Stop
    & $curl.Source --fail --location --silent --show-error --retry 3 --connect-timeout 30 --max-time 600 --output $Destination $Url
    if ($LASTEXITCODE -ne 0) { throw "Download failed: $Url" }
    $actual = (Get-FileHash -LiteralPath $Destination -Algorithm $Algorithm).Hash
    if ($actual -ne $Expected) { throw "$Algorithm mismatch for $Url" }
}

function Write-ComponentProvenance {
    param([string]$Binary, [string]$Version, [string]$Url, [string]$Algorithm, [string]$ArchiveHash)
    $signature = Get-AuthenticodeSignature -LiteralPath $Binary
    if ($signature.Status -eq 'HashMismatch') { throw "Corrupt upstream signature: $Binary" }
    [ordered]@{
        schemaVersion = 1
        file = Split-Path $Binary -Leaf
        version = $Version
        sourceUrl = $Url
        archiveHashAlgorithm = $Algorithm
        archiveHash = $ArchiveHash.ToLowerInvariant()
        sha256 = (Get-FileHash -LiteralPath $Binary -Algorithm SHA256).Hash.ToLowerInvariant()
        authenticodeStatus = [string]$signature.Status
        signerSubject = $signature.SignerCertificate.Subject
        modified = $false
    } | ConvertTo-Json | Set-Content -LiteralPath "$Binary.provenance.json" -Encoding utf8
}

# Temporary extraction stays under this one verified workspace-owned directory.
$stagingParent = Join-Path $projectRoot 'output/release-investigation/privacy-assets'
$staging = Join-Path $stagingParent ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $staging -Force | Out-Null
try {
    if ($Components -contains 'bridges') {
        $archive = Join-Path $staging 'tor-expert-bundle.tar.gz'
        Download-VerifiedArchive -Url $TorBundleUrl -Destination $archive -Algorithm SHA256 -Expected $TorBundleSha256
        & tar.exe -xf $archive -C $staging tor/pluggable_transports/lyrebird.exe docs/lyrebird.txt
        if ($LASTEXITCODE -ne 0) { throw 'Cannot extract Lyrebird and its license notices from Tor Expert Bundle.' }
        $destination = Join-Path $appDir 'tor-pt/windows'
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $staging 'tor/pluggable_transports/lyrebird.exe') -Destination (Join-Path $destination 'lyrebird.exe') -Force
        Copy-Item -LiteralPath (Join-Path $staging 'docs/lyrebird.txt') -Destination (Join-Path $destination 'lyrebird.LICENSE.txt') -Force
        Write-ComponentProvenance -Binary (Join-Path $destination 'lyrebird.exe') -Version $TorBundleVersion -Url $TorBundleUrl -Algorithm SHA256 -ArchiveHash $TorBundleSha256
        # Do not accidentally ship old, locally rebuilt helpers from a warm build.
        foreach ($legacy in @('snowflake-client.exe', 'obfs4proxy.exe')) {
            Remove-Item -LiteralPath (Join-Path $destination $legacy) -Force -ErrorAction SilentlyContinue
        }
    }
    if ($Components -contains 'i2p') {
        $url = "$I2pdBaseUrl/i2pd_$($I2pdVersion)_win64_mingw.zip"
        $archive = Join-Path $staging 'i2pd.zip'
        Download-VerifiedArchive -Url $url -Destination $archive -Algorithm SHA512 -Expected $I2pdSha512
        $extract = Join-Path $staging 'i2pd'
        Expand-Archive -LiteralPath $archive -DestinationPath $extract
        $binaries = @(Get-ChildItem -LiteralPath $extract -Recurse -File -Filter 'i2pd.exe')
        if ($binaries.Count -ne 1) { throw 'Expected exactly one i2pd.exe in the upstream archive.' }
        $destination = Join-Path $appDir 'i2p/windows'
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Copy-Item -LiteralPath $binaries[0].FullName -Destination (Join-Path $destination 'i2pd.exe') -Force
        Write-ComponentProvenance -Binary (Join-Path $destination 'i2pd.exe') -Version $I2pdVersion -Url $url -Algorithm SHA512 -ArchiveHash $I2pdSha512
    }
} finally {
    $resolvedStaging = [IO.Path]::GetFullPath($staging)
    $resolvedParent = [IO.Path]::GetFullPath($stagingParent).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedStaging.StartsWith($resolvedParent, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refusing to remove a staging directory outside the privacy-assets workspace.'
    }
    Remove-Item -LiteralPath $resolvedStaging -Recurse -Force
}
Write-Host '[INFO] Staged checksum-verified upstream Windows privacy tools without modifying their executables.'
