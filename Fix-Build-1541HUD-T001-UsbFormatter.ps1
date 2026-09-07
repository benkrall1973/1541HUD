param(
    [string]$Repo = (Get-Location).Path
)

$ErrorActionPreference = "Stop"

$UsbMain = Join-Path $Repo "plugins/system/usb/src/usb_main.c"
$Build001 = Join-Path $Repo "1541hud/Build-1541HUD-T001.ps1"
$Preserve = Join-Path $Repo "Preserve-1541HUD-TestSource.ps1"

foreach ($f in @($UsbMain,$Build001,$Preserve)) {
    if (-not (Test-Path $f)) { throw "Missing required file: $f" }
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = Join-Path $Repo "build-1541hud/T0.0.1_USB_FORMATTER_PRE_FIX_$stamp"
New-Item -ItemType Directory -Force -Path $backup | Out-Null
Copy-Item $UsbMain (Join-Path $backup "usb_main.c") -Force
git -C $Repo diff --binary -- plugins/system/usb/src/usb_main.c |
    Set-Content -Encoding UTF8 (Join-Path $backup "pre-fix-usb.patch")

$s = Get-Content -LiteralPath $UsbMain -Raw

# Remove the malformed READRAW block inserted by the previous script.
$bad = '(?ms)\}\}\s*else\s+if\s*\(\s*type\s*==\s*DRIVEHUD_EVENT_READRAW\s*\)\s*\{.*?p\s*=\s*drivehud_append_str\s*\(\s*p\s*,\s*e\s*,\s*"\\r\\n"\s*\)\s*;'
if ([regex]::IsMatch($s, $bad)) {
    $s = [regex]::Replace($s, $bad, '}', 1)
    Write-Host "Removed malformed READRAW formatter block"
} elseif ($s -match 'READRAW T0\.0\.1 count=') {
    throw "READRAW formatter exists, but not in the expected malformed form. Refusing blind edit."
} else {
    Write-Host "Malformed READRAW block already absent"
}

# Find the known-good UC2A block and insert READRAW as the next else-if.
$anchor = '(?ms)(\}\s*else\s+if\s*\(\s*type\s*==\s*DRIVEHUD_EVENT_UC2A_SAMPLE\s*\)\s*\{.*?p\s*=\s*drivehud_append_str\s*\(\s*p\s*,\s*e\s*,\s*"\\r\\n"\s*\)\s*;\s*\})'
$m = [regex]::Match($s, $anchor)
if (-not $m.Success) {
    throw "Could not locate intact UC2A formatter block."
}

$readraw = @'
else if(type==DRIVEHUD_EVENT_READRAW){
 uint32_t count=(w>>8)&0x000FFFFFu;
 uint8_t data=(uint8_t)(w&0xFFu);
 p=drivehud_append_str(p,e,"READRAW T0.0.1 count=");
 p=drivehud_append_u32(p,e,count);
 p=drivehud_append_str(p,e," data=$");
 p=drivehud_append_hex8(p,e,data);
 p=drivehud_append_str(p,e,"\r\n");
}
'@

$s = $s.Substring(0,$m.Index + $m.Length) + $readraw + $s.Substring($m.Index + $m.Length)

# Repair accidental "}\nelse if" formatting only; semantics unchanged.
$s = $s -replace '\}\s*else if\(type==DRIVEHUD_EVENT_READRAW\)', '}else if(type==DRIVEHUD_EVENT_READRAW)'

Set-Content -LiteralPath $UsbMain -Value $s -NoNewline

Write-Host ""
Write-Host "USB formatter sanity check..."

$check = Get-Content -LiteralPath $UsbMain -Raw
if ($check -match '\}\}\s*else\s+if\s*\(\s*type\s*==\s*DRIVEHUD_EVENT_READRAW') {
    throw "Malformed double-brace READRAW insertion still present."
}
if ($check -notmatch 'else if\s*\(\s*type\s*==\s*DRIVEHUD_EVENT_READRAW\s*\)') {
    throw "READRAW else-if missing."
}
if ($check -notmatch 'READRAW T0\.0\.1 count=') {
    throw "READRAW text formatter missing."
}

Write-Host " OK: READRAW formatter is structurally placed as an else-if"

Write-Host ""
Write-Host "Building T0.0.1..."
& powershell.exe -ExecutionPolicy Bypass -File $Build001
if ($LASTEXITCODE -ne 0) { throw "T0.0.1 build still failed." }

$BuildDir = Join-Path $Repo "build-1541hud"
$Uf2 = Join-Path $BuildDir "1541HUD_OneROM_T0.0.1.uf2"
$Bin = Join-Path $BuildDir "1541HUD_OneROM_T0.0.1.bin"

if (-not (Test-Path $Uf2)) { throw "Expected UF2 missing: $Uf2" }
if (-not (Test-Path $Bin)) { throw "Expected BIN missing: $Bin" }

Write-Host ""
Write-Host "Preserving exact T0.0.1 source/build bundle..."
& powershell.exe -ExecutionPolicy Bypass -File $Preserve -TestName "T0.0.1_RAW_READ_CAPTURE"
if ($LASTEXITCODE -ne 0) { throw "Build succeeded but source preservation failed." }

Write-Host ""
Write-Host "T0.0.1 RAW READ CAPTURE COMPLETE"
Write-Host "Pre-fix USB snapshot: $backup"
Get-FileHash -Algorithm SHA256 $Bin,$Uf2
Write-Host ""
Write-Host "UF2: $Uf2"
Write-Host ""
Write-Host "Expected new telemetry:"
Write-Host "  READRAW T0.0.1 count=4096 data=`$XX"
Write-Host "  READRAW T0.0.1 count=8192 data=`$XX"
