param(
    [Parameter(Mandatory)][string]$ArtifactDir,
    [Parameter(Mandatory)][string]$CertificatePath,
    [Parameter(Mandatory)][string]$SignToolPath,
    [Parameter(Mandatory)][string]$AppVersion
)
$ErrorActionPreference = 'Stop'
$ArtifactDir = (Resolve-Path -LiteralPath $ArtifactDir).Path
$stage = Join-Path $ArtifactDir 'signed-runtime'
if (Test-Path -LiteralPath $stage) { throw 'Signing stage already exists; use a fresh artifact directory.' }
Expand-Archive -LiteralPath (Join-Path $ArtifactDir 'Stashi-Wallet-windows-portable-unsigned.zip') -DestinationPath $stage
$unsignedRuntimeHash = (Get-FileHash -LiteralPath (Join-Path $stage 'Stashi Wallet.exe') -Algorithm SHA256).Hash.ToLowerInvariant()
function Sign-ReleaseFile([string]$Path) {
    & $SignToolPath sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /f $CertificatePath /p $env:WINDOWS_SIGN_PASSWORD $Path
    if ($LASTEXITCODE -ne 0) { throw "Signing failed: $Path" }
    # Public Windows trust is intentionally unavailable for our self-signed
    # certificate. Check that signing produced an embedded signature without changing Root trust.
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($null -eq $signature.SignerCertificate -or $signature.Status -eq 'HashMismatch' -or $signature.Status -eq 'NotSigned') {
        throw "Missing or corrupt Authenticode signature: $Path"
    }

}
# Share the same upstream-signature preservation policy with local builds.
& (Join-Path $PSScriptRoot 'sign-windows-runtime.ps1') -RuntimeDir $stage -CertificatePath $CertificatePath -SignToolPath $SignToolPath
& (Join-Path $PSScriptRoot 'package-windows-installer.ps1') -SourceDir $stage -ComponentAssetDir $ArtifactDir -OutputDir $ArtifactDir -AppVersion $AppVersion -OutputBaseFilename 'Stashi-Wallet-windows-installer'
$installer = Join-Path $ArtifactDir 'Stashi-Wallet-windows-installer.exe'
Sign-ReleaseFile $installer
$hash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  Stashi-Wallet-windows-installer.exe" | Set-Content -LiteralPath "$installer.sha256" -Encoding ascii
$runtimeHash = (Get-FileHash -LiteralPath (Join-Path $stage 'Stashi Wallet.exe') -Algorithm SHA256).Hash.ToLowerInvariant()
"$runtimeHash  Stashi Wallet.exe" | Set-Content -LiteralPath (Join-Path $ArtifactDir 'installed-payload-windows.txt') -Encoding ascii
if ($unsignedRuntimeHash -ne $runtimeHash) {
    # The offline developer portable archive remains unsigned. Hash-first lookup
    # can authenticate that exact executable under a distinct manifest alias.
    "$unsignedRuntimeHash  Stashi Wallet (unsigned).exe" | Add-Content -LiteralPath (Join-Path $ArtifactDir 'installed-payload-windows.txt') -Encoding ascii
}
