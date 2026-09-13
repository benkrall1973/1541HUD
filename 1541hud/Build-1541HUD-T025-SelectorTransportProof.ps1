[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SelectorPrg,
    [string]$OutputDirectory = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "build-address-test"
}
if (-not (Test-Path -LiteralPath $SelectorPrg -PathType Leaf)) {
    throw "Selector PRG not found: $SelectorPrg"
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$outFile = Join-Path $OutputDirectory "1541HUD_UB3_T0.0.25_Selector_Transport_Proof.prg"
Copy-Item -LiteralPath $SelectorPrg -Destination $outFile -Force
Get-FileHash -Algorithm SHA256 $outFile
Get-Item $outFile | Select-Object Name, Length, LastWriteTime
Write-Host ""
Write-Host "T0.0.25 built: known-good OneROM Selector transport proof."
Write-Host "This is an exact copy of the supplied Selector PRG: no address bytes are written."
Write-Host "PASS is the Selector reaching its normal ROM menu and successfully listing its ROM slots."
