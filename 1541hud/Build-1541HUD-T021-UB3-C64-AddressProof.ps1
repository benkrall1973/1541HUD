[CmdletBinding()]
param(
    [ValidateRange(8, 11)]
    [int]$NewAddress = 10,

    [string]$OutputDirectory = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
    $OutputDirectory = Join-Path $scriptDirectory "build-address-test"
}

# C64 PRG: 10 SYS2061.  It opens command channel 15 at device 8, writes this
# eleven-byte 1541 RAM routine to $0600, then executes it:
#   LDA #(new_address OR $20) / STA $0077 / LDA #(new_address OR $40) / STA $0078 / RTS
# This is temporary RAM state only.  It does not write any OneROM slot, flash,
# ROM image, IEC hardware strap, UB3 configuration, or nonvolatile drive data.
$basicStub = [byte[]](
    0x0B, 0x08, 0x0A, 0x00, 0x9E, 0x32, 0x30, 0x36, 0x31, 0x00, 0x00, 0x00
)

# The machine-code loop sends 24 command bytes through the C64 KERNAL serial
# command channel, then closes the local logical file and returns to BASIC.
# The payload starts at $083B; the LDA absolute,X operand is therefore fixed.
$machineCode = [byte[]](
    0xA9, 0x0F, 0xA2, 0x08, 0xA0, 0x0F, 0x20, 0xBA, 0xFF,
    0xA9, 0x00, 0xAA, 0xA8, 0x20, 0xBD, 0xFF, 0x20, 0xC0, 0xFF,
    0xA9, 0x0F, 0x20, 0xC9, 0xFF, 0xA2, 0x00,
    0xBD, 0x3B, 0x08, 0x20, 0xD2, 0xFF, 0xE8, 0xE0, 0x18, 0xD0, 0xF5,
    0x20, 0xCC, 0xFF, 0xA9, 0x0F, 0x20, 0xC3, 0xFF, 0x60
)

$commandBytes = [byte[]](
    0x4D, 0x2D, 0x57, 0x00, 0x06, 0x0B,
    0xA9, [byte]($NewAddress -bor 0x20), 0x8D, 0x77, 0x00,
    0xA9, [byte]($NewAddress -bor 0x40), 0x8D, 0x78, 0x00, 0x60, 0x0D,
    0x4D, 0x2D, 0x45, 0x00, 0x06, 0x0D
)

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$outFile = Join-Path $OutputDirectory ("1541HUD_UB3_T0.0.21_Set_Address_8_to_{0}.prg" -f $NewAddress)
[System.IO.File]::WriteAllBytes($outFile, $basicStub + $machineCode + $commandBytes)

Get-FileHash -Algorithm SHA256 $outFile
Get-Item $outFile | Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "T0.0.21 C64 temporary address-change proof built."
Write-Host "Run the PRG only with one target 1541 at address 8, drive idle."
Write-Host "It changes only live 1541 RAM: 8 -> $NewAddress; power-cycle resets it."
Write-Host "Verify from the C64 with: LOAD"$",$NewAddress"
