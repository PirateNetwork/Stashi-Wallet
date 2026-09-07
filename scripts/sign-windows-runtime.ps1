param(
    [Parameter(Mandatory)][string]$RuntimeDir,
    [Parameter(Mandatory)][string]$CertificatePath,
    [Parameter(Mandatory)][string]$SignToolPath
)
$ErrorActionPreference = 'Stop'
$RuntimeDir = (Resolve-Path -LiteralPath $RuntimeDir).Path
if (-not (Test-Path -LiteralPath (Join-Path $RuntimeDir 'Stashi Wallet.exe'))) { throw 'Wallet executable missing.' }
$timestampUrl = if ($env:WINDOWS_SIGN_TIMESTAMP_URL) { $env:WINDOWS_SIGN_TIMESTAMP_URL } else { 'http://timestamp.digicert.com' }

# Deliberately top-level only: third-party transport helpers are immutable.
Get-ChildItem -LiteralPath $RuntimeDir -File | Where-Object Extension -In '.exe', '.dll' | ForEach-Object {
    $signature = Get-AuthenticodeSignature -LiteralPath $_.FullName
    if ($signature.Status -eq 'HashMismatch') {
        throw "Refusing to cover a corrupt upstream signature: $($_.Name)"
    }
    if ($null -ne $signature.SignerCertificate) {
        # An offline/untrusted chain is not permission to replace its publisher.
        Write-Host "Preserving existing signature: $($_.Name) ($($signature.Status))"
    } elseif ($_.Name -match '^(msvcp140.*|vcruntime140.*|concrt140)\.dll$|^(i2pd|lyrebird|snowflake-client|obfs4proxy)\.exe$') {
        Write-Host "Preserving upstream binary: $($_.Name)"
    } else {
        if ($signature.Status -ne 'NotSigned') { throw "Cannot inspect signature: $($_.Name) ($($signature.Status))" }
        & $SignToolPath sign /fd SHA256 /tr $timestampUrl /td SHA256 /f $CertificatePath /p $env:WINDOWS_SIGN_PASSWORD $_.FullName
        if ($LASTEXITCODE -ne 0) { throw "Signing failed: $($_.Name)" }
        $signed = Get-AuthenticodeSignature -LiteralPath $_.FullName
        if ($null -eq $signed.SignerCertificate -or $signed.Status -in 'HashMismatch', 'NotSigned') {
            throw "Missing or corrupt Authenticode signature: $($_.Name)"
        }
    }
}
