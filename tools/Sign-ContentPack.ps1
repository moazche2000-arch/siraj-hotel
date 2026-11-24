[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateRange(1, 2147483647)]
    [int]$Revision,

    [Parameter(Mandatory)]
    [ValidatePattern('^v[0-9]{1,5}\.[0-9]{1,5}\.[0-9]{1,5}$')]
    [string]$Tag,

    [string]$Pack = 'build/siraj-game.pck',
    [string]$Output = 'build/siraj-update.json'
)

$ErrorActionPreference = 'Stop'
$packFile = Get-Item -LiteralPath $Pack
if ($packFile.Length -le 0 -or $packFile.Length -gt 48MB) {
    throw 'The content pack must be between 1 byte and 48 MiB.'
}

$keyPath = Join-Path $env:LOCALAPPDATA 'SirajHotelBuild/signing/content-signing.dpapi'
$secret = (Get-Content -LiteralPath $keyPath -Raw).Trim() | ConvertTo-SecureString
$payload = [ordered]@{
    protocol = 1
    revision = $Revision
    tag = $Tag
    pack_bytes = $packFile.Length
    sha256 = (Get-FileHash -LiteralPath $packFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
} | ConvertTo-Json -Compress
$payloadBytes = [Text.Encoding]::UTF8.GetBytes($payload)

$rsa = [Security.Cryptography.RSA]::Create()
try {
    $rsa.FromXmlString([Net.NetworkCredential]::new('', $secret).Password)
    $signature = $rsa.SignData(
        $payloadBytes,
        [Security.Cryptography.HashAlgorithmName]::SHA256,
        [Security.Cryptography.RSASignaturePadding]::Pkcs1
    )
} finally {
    $rsa.Dispose()
}
$envelope = [ordered]@{
    payload = [Convert]::ToBase64String($payloadBytes)
    signature = [Convert]::ToBase64String($signature)
} | ConvertTo-Json -Compress
[IO.File]::WriteAllText($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Output), $envelope)
