# T0.0.33 — UB3 turbo_boot preflight
#
# Creates a copy of the exact configuration that originally programmed UB3,
# adding only "turbo_boot": true.  It never changes UB3 unless -Program is
# explicitly supplied.
#
# turbo_boot makes One ROM ignore its SEL_A..SEL_D image-select jumpers at
# UB3 boot and serve the first non-plugin ROM set (the Universal bootloader).
# The bootloader can then perform its normal saved-ROM handoff.
#
# Important: use the actual JSON that was used to program this UB3.  Writing
# the generated JSON beside that source preserves all relative ROM/plugin paths.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceConfig,

    [string]$OneRomCli = "C:\Users\Admin\Desktop\onerom-cli-win-0.3.0-x86_64\onerom.exe",

    [switch]$Program
)

$ErrorActionPreference = "Stop"

$sourcePath = (Resolve-Path -LiteralPath $SourceConfig).Path
$sourceDir = Split-Path -Parent $sourcePath
$sourceName = [System.IO.Path]::GetFileNameWithoutExtension($sourcePath)
$generatedPath = Join-Path $sourceDir "$sourceName.T0.0.33-turbo-boot.json"

try {
    $config = Get-Content -LiteralPath $sourcePath -Raw | ConvertFrom-Json
}
catch {
    throw "SourceConfig is not valid JSON: $sourcePath"
}

$setProperty = $config.PSObject.Properties["chip_sets"]
if (-not $setProperty) {
    $setProperty = $config.PSObject.Properties["rom_sets"]
}
if (-not $setProperty -or @($setProperty.Value).Count -lt 2) {
    throw "SourceConfig does not look like the multi-ROM UB3 selector configuration. No file was written."
}

$existingTurbo = $config.PSObject.Properties["turbo_boot"]
if ($existingTurbo) {
    $existingTurbo.Value = $true
}
else {
    $config | Add-Member -NotePropertyName "turbo_boot" -NotePropertyValue $true
}

$json = $config | ConvertTo-Json -Depth 32
[System.IO.File]::WriteAllText(
    $generatedPath,
    $json + [Environment]::NewLine,
    [System.Text.UTF8Encoding]::new($false)
)

$setCount = @($setProperty.Value).Count
$sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
$generatedHash = (Get-FileHash -LiteralPath $generatedPath -Algorithm SHA256).Hash

Write-Host "T0.0.33 UB3 turbo_boot configuration generated."
Write-Host "Source config    : $sourcePath"
Write-Host "Generated config : $generatedPath"
Write-Host "ROM set count    : $setCount (preserved)"
Write-Host "turbo_boot       : true"
Write-Host "Source SHA256    : $sourceHash"
Write-Host "Generated SHA256 : $generatedHash"
Write-Host ""
Write-Host "NO UB3 CHANGE HAS BEEN MADE."

if (-not $Program) {
    Write-Host "Review the generated file. To flash it deliberately, rerun with -Program."
    exit 0
}

if (-not (Test-Path -LiteralPath $OneRomCli -PathType Leaf)) {
    throw "onerom.exe not found: $OneRomCli"
}

Write-Host ""
Write-Host "Programming UB3 from the generated configuration..."
& $OneRomCli program --config $generatedPath
if ($LASTEXITCODE -ne 0) {
    throw "One ROM programming failed (exit $LASTEXITCODE)."
}

Write-Host ""
Write-Host "T0.0.33 PROGRAM COMPLETE."
Write-Host "At the next UB3 boot, physical SEL_A/B/C/D jumpers are ignored."
Write-Host "Verify that the Universal bootloader still hands off to the saved ROM before wiring any 1541 address lines."
