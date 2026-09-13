# T0.0.33 — UB3 turbo_boot preflight
#
# Creates a copy of the exact configuration that originally programmed UB3,
# adding only "turbo_boot": true. It never changes UB3 unless -Program is
# explicitly supplied.
#
# turbo_boot makes One ROM ignore its SEL_A..SEL_D image-select jumpers at
# UB3 boot and serve the first non-plugin ROM set (the Universal bootloader).
# The existing Universal bootloader then performs its normal saved-ROM handoff.
#
# For the known 1541 selector JSON, USB and Host Control are supplied on the
# program command line exactly as the configuration notes require.

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
if (-not $setProperty -or @($setProperty.Value).Count -ne 8) {
    throw "Expected the eight-set UB3 selector configuration. Found $(@($setProperty.Value).Count) set(s). No file was written."
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
Write-Host "Program plugins  : usb + host-control (preserved)"
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

# Validate every local ROM path before any programming begins. Remote HTTP(S)
# paths are intentionally left to onerom.exe to retrieve.
$missingFiles = [System.Collections.Generic.List[string]]::new()
foreach ($set in @($setProperty.Value)) {
    $romList = $set.chips
    if (-not $romList) {
        $romList = $set.roms
    }
    foreach ($rom in @($romList)) {
        $file = [string]$rom.file
        if ($file -and $file -notmatch '^[a-zA-Z]+://') {
            $resolvedFile = $file
            if (-not [System.IO.Path]::IsPathRooted($resolvedFile)) {
                $resolvedFile = Join-Path $sourceDir $resolvedFile
            }
            if (-not (Test-Path -LiteralPath $resolvedFile -PathType Leaf)) {
                $missingFiles.Add($resolvedFile)
            }
        }
    }
}
if ($missingFiles.Count -gt 0) {
    Write-Host ""
    Write-Host "UB3 WAS NOT PROGRAMMED. These local ROM files are missing:"
    $missingFiles | Sort-Object -Unique | ForEach-Object { Write-Host "  $_" }
    throw "Restore/correct the local ROM paths in the source configuration, then rerun."
}

Write-Host ""
Write-Host "Programming UB3 from the generated configuration..."
& $OneRomCli program --config $generatedPath --plugin usb --plugin host-control
if ($LASTEXITCODE -ne 0) {
    throw "One ROM programming failed (exit $LASTEXITCODE)."
}

Write-Host ""
Write-Host "T0.0.33 PROGRAM COMPLETE."
Write-Host "At the next UB3 boot, physical SEL_A/B/C/D jumpers are ignored."
Write-Host "Verify that the Universal bootloader still hands off to the saved ROM before wiring any 1541 address lines."
