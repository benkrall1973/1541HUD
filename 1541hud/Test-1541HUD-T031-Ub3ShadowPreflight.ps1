[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$OneRomCli,

    [string]$Shadow = "1541hud\build-address-test\JiffyDOS-1541-6.00-shadow-address-10.bin",

    [ValidateRange(8,11)]
    [int]$Address = 10,

    [string]$OutPlan = "1541hud\build-address-test\T0.0.31-UB3-shadow-preflight.json"
)

$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath $OneRomCli -PathType Leaf)) {
    throw "onerom.exe not found: $OneRomCli"
}
if (!(Test-Path -LiteralPath $Shadow -PathType Leaf)) {
    throw "Shadow file not found: $Shadow"
}

$shadowBytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Shadow))
if ($shadowBytes.Length -ne 8192) {
    throw "Refusing: shadow must be exactly 8192 bytes; got $($shadowBytes.Length)."
}

$patchOffset = 0x0B3A
$expected = @{
    8  = [byte[]](0xA9,0x00,0xC9,0xF0,0xEA)
    9  = [byte[]](0xA9,0x20,0xC9,0xD0,0xEA)
    10 = [byte[]](0xA9,0x40,0xC9,0xB0,0xEA)
    11 = [byte[]](0xA9,0x60,0xC9,0x90,0xEA)
}[$Address]
$actual = $shadowBytes[$patchOffset..($patchOffset + 4)]

if (-not [Linq.Enumerable]::SequenceEqual([byte[]]$actual, [byte[]]$expected)) {
    $got = ($actual | ForEach-Object { $_.ToString("X2") }) -join " "
    throw "Refusing: shadow patch at CPU $([char]36)EB3A does not match address $Address. Got: $got"
}

$inspect = & $OneRomCli inspect slots 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "onerom.exe inspect slots failed:`n$inspect"
}
$inspectText = $inspect -join [Environment]::NewLine
if ($inspectText -notmatch "Configured with") {
    throw "Unrecognised inspect-slots output; refusing to continue."
}
if ($inspectText -notmatch "JIFFYDOS") {
    throw "No JIFFYDOS slot was found in UB3 current configuration. Nothing changed."
}
if ($inspectText -notmatch "1541 ONEROM BOOTLOADER") {
    throw "Expected Universal Bootloader slot was not found. Nothing changed."
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Shadow).Hash.ToLowerInvariant()
$plan = [ordered]@{
    test = "T0.0.31 UB3 shadow preflight"
    generated_utc = (Get-Date).ToUniversalTime().ToString("o")
    target_address = $Address
    shadow_path = (Resolve-Path -LiteralPath $Shadow).Path
    shadow_sha256 = $hash
    patch_cpu_address = "$([char]36)EB3A"
    patch_bytes = (($actual | ForEach-Object { $_.ToString("X2") }) -join " ")
    ub3_inspect_slots = $inspectText
    changes_made = $false
    reset_asserted = $false
    next_gate = "PASS only verifies inputs. It does not upload, select, patch UB3 RAM, flash firmware, or pulse X2/1541 reset."
}
$dir = Split-Path -Parent $OutPlan
if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$plan | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $OutPlan -Encoding utf8

Write-Host "T0.0.31 PASS — UB3 shadow preflight complete."
Write-Host "JiffyDOS slot and Universal Bootloader were found."
Write-Host "Shadow SHA256 : $hash"
Write-Host "Patch         : CPU $([char]36)EB3A = $($plan.patch_bytes) (address $Address)"
Write-Host "Plan written  : $((Resolve-Path -LiteralPath $OutPlan).Path)"
Write-Host "NO CHANGES MADE: no upload, slot selection, firmware flash, UB3 RAM write, or X2 reset pulse."
