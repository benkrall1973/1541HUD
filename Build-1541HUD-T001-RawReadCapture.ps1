param(
    [string]$Repo = (Get-Location).Path
)

$ErrorActionPreference = "Stop"

$T000 = Join-Path $Repo "plugins/user/1541hud-probe/src/1541hud_probe_t000.c"
$T001 = Join-Path $Repo "plugins/user/1541hud-probe/src/1541hud_probe_t001.c"
$Makefile = Join-Path $Repo "plugins/user/1541hud-probe/Makefile"

$User1541 = Join-Path $Repo "plugins/user/1541hud-probe/src/1541hud_mailbox.h"
$UserCompat = Join-Path $Repo "plugins/user/1541hud-probe/src/drivehud_mailbox.h"
$Usb1541 = Join-Path $Repo "plugins/system/usb/include/1541hud_mailbox.h"
$UsbCompat = Join-Path $Repo "plugins/system/usb/include/drivehud_mailbox.h"
$UsbMain = Join-Path $Repo "plugins/system/usb/src/usb_main.c"

$Build000 = Join-Path $Repo "1541hud/Build-1541HUD-T000.ps1"
$Build001 = Join-Path $Repo "1541hud/Build-1541HUD-T001.ps1"
$Preserve = Join-Path $Repo "Preserve-1541HUD-TestSource.ps1"

foreach ($f in @($T000,$Makefile,$User1541,$UserCompat,$Usb1541,$UsbCompat,$UsbMain,$Build000)) {
    if (-not (Test-Path $f)) { throw "Required file missing: $f" }
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$pre = Join-Path $Repo "build-1541hud/T0.0.1_RAW_READ_PREP_$stamp"
New-Item -ItemType Directory -Force -Path $pre | Out-Null

Copy-Item $T000 (Join-Path $pre "1541hud_probe_t000.c") -Force
Copy-Item $Makefile (Join-Path $pre "Makefile") -Force
Copy-Item $UsbMain (Join-Path $pre "usb_main.c") -Force
git -C $Repo diff --binary | Set-Content -Encoding UTF8 (Join-Path $pre "pre-t001-working-tree.patch")

Write-Host "Creating isolated T0.0.1 source from current T0.0.0..."
Copy-Item $T000 $T001 -Force

function Replace-OnceRegex {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Replacement,
        [string]$Label
    )
    $s = Get-Content -LiteralPath $Path -Raw
    $re = [regex]::new($Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $re.IsMatch($s)) { throw "Patch point not found: $Label ($Path)" }
    $s = $re.Replace($s, $Replacement, 1)
    Set-Content -LiteralPath $Path -Value $s -NoNewline
    Write-Host "Patched: $Label"
}

function Ensure-LineAfter {
    param(
        [string]$Path,
        [string]$ExistingRegex,
        [string]$NewLine,
        [string]$AlreadyRegex,
        [string]$Label
    )
    $s = Get-Content -LiteralPath $Path -Raw
    if ($s -match $AlreadyRegex) {
        Write-Host "Already present: $Label"
        return
    }
    $m = [regex]::Match($s, $ExistingRegex)
    if (-not $m.Success) { throw "Anchor not found: $Label ($Path)" }
    $insertAt = $m.Index + $m.Length
    $s = $s.Substring(0,$insertAt) + "`r`n" + $NewLine + $s.Substring($insertAt)
    Set-Content -LiteralPath $Path -Value $s -NoNewline
    Write-Host "Added: $Label"
}

# ----------------------------------------------------------------------
# Version isolation
# ----------------------------------------------------------------------
Replace-OnceRegex $T001 `
    'ORA_DEFINE_USER_PLUGIN\s*\(\s*drivehud_probe_main\s*,\s*0\s*,\s*0\s*,\s*0\s*,\s*0\s*,\s*0\s*,\s*7\s*,\s*1\s*\)\s*;' `
    'ORA_DEFINE_USER_PLUGIN(drivehud_probe_main, 0,0,1,0, 0,7,1);' `
    "T0.0.1 plugin version"

# Point Makefile at T0.0.1, accepting either T000 or T001 current state.
$mk = Get-Content -LiteralPath $Makefile -Raw
if ($mk -match 'PLUGIN_SRC\s*:=\s*src/1541hud_probe_t001\.c') {
    Write-Host "Already present: Makefile T0.0.1 source"
} elseif ($mk -match 'PLUGIN_SRC\s*:=\s*src/1541hud_probe_t000\.c') {
    $mk = $mk -replace 'PLUGIN_SRC\s*:=\s*src/1541hud_probe_t000\.c',
        'PLUGIN_SRC := src/1541hud_probe_t001.c'
    Set-Content -LiteralPath $Makefile -Value $mk -NoNewline
    Write-Host "Patched: Makefile T0.0.1 source"
} else {
    throw "Makefile is not pointing at T0.0.0 as expected."
}

Copy-Item $Build000 $Build001 -Force
$b = Get-Content -LiteralPath $Build001 -Raw
$b = $b.Replace("T0.0.0", "T0.0.1")
$b = $b.Replace("T000", "T001")
Set-Content -LiteralPath $Build001 -Value $b -NoNewline
Write-Host "Created: Build-1541HUD-T001.ps1"

# ----------------------------------------------------------------------
# Event type 7: sparse raw read-cycle telemetry.
# No mailbox struct/layout change.
# ----------------------------------------------------------------------
Ensure-LineAfter $User1541 `
    '(?m)^#define\s+HUD1541_EVENT_UC2A_SAMPLE\s+6u\s*$' `
    '#define HUD1541_EVENT_READRAW 7u' `
    'HUD1541_EVENT_READRAW\s+7u' `
    "USER shared event 7"

Ensure-LineAfter $Usb1541 `
    '(?m)^#define\s+HUD1541_EVENT_UC2A_SAMPLE\s+6u\s*$' `
    '#define HUD1541_EVENT_READRAW 7u' `
    'HUD1541_EVENT_READRAW\s+7u' `
    "USB shared event 7"

Ensure-LineAfter $UserCompat `
    '(?m)^#define\s+DRIVEHUD_EVENT_UC2A_SAMPLE\s+HUD1541_EVENT_UC2A_SAMPLE\s*$' `
    '#define DRIVEHUD_EVENT_READRAW HUD1541_EVENT_READRAW' `
    'DRIVEHUD_EVENT_READRAW\s+HUD1541_EVENT_READRAW' `
    "USER compatibility alias event 7"

Ensure-LineAfter $UsbCompat `
    '(?m)^#define\s+DRIVEHUD_EVENT_UC2A_SAMPLE\s+HUD1541_EVENT_UC2A_SAMPLE\s*$' `
    '#define DRIVEHUD_EVENT_READRAW HUD1541_EVENT_READRAW' `
    'DRIVEHUD_EVENT_READRAW\s+HUD1541_EVENT_READRAW' `
    "USB compatibility alias event 7"

# ----------------------------------------------------------------------
# Probe telemetry
#
# Every 4096 raw SM2/DMA10 samples, emit one event BEFORE uc2_porta_read().
# This answers only:
#   "Is SM2/DMA10 actually capturing 6502 read cycles?"
#
# It deliberately does not change PIO timing, filter timing, SM3, mailbox
# layout, track logic, motor logic, density logic, or WP logic.
# ----------------------------------------------------------------------

# Add raw sample counter near existing sector counters.
$s = Get-Content -LiteralPath $T001 -Raw
if ($s -notmatch 'raw_read_count') {
    $anchor = [regex]::Match($s, '(?m)^(?<indent>\s*)uint32_t\s+sector_uc2a_count\s*=\s*0u\s*;')
    if (-not $anchor.Success) {
        throw "Could not find sector_uc2a_count local in T0.0.1."
    }
    $line = $anchor.Value + "`r`n" + $anchor.Groups['indent'].Value + "uint32_t raw_read_count = 0u;"
    $s = $s.Substring(0,$anchor.Index) + $line + $s.Substring($anchor.Index + $anchor.Length)
    Set-Content -LiteralPath $T001 -Value $s -NoNewline
    Write-Host "Patched: raw read counter"
} else {
    Write-Host "Already present: raw read counter"
}

# Insert telemetry immediately after fetching sector_ring[sidx], before UC2 filter.
$s = Get-Content -LiteralPath $T001 -Raw
if ($s -notmatch 'DRIVEHUD_EVENT_READRAW\s*<<\s*28') {
    $pattern = '(?ms)(uint32_t\s+ss\s*=\s*sector_ring\s*\[\s*sidx\s*\]\s*;\s*\r?\n\s*sector_consumer_total\+\+\s*;\s*\r?\n\s*budget--\s*;)'
    $m = [regex]::Match($s, $pattern)
    if (-not $m.Success) {
        throw "Could not locate bounded DMA10 consumer sample point."
    }

    $insert = @'

 raw_read_count++;
 if ((raw_read_count & 0xFFFu) == 0u) {
 uint8_t raw_data = logical_data_from_gpio(ss);
 queue_event(m,
 (DRIVEHUD_EVENT_READRAW << 28) |
 ((raw_read_count & 0x000FFFFFu) << 8) |
 (uint32_t)raw_data);
 }
'@

    $replacement = $m.Groups[1].Value + $insert
    $s = $s.Substring(0,$m.Index) + $replacement + $s.Substring($m.Index + $m.Length)
    Set-Content -LiteralPath $T001 -Value $s -NoNewline
    Write-Host "Patched: sparse READRAW producer telemetry"
} else {
    Write-Host "Already present: sparse READRAW producer telemetry"
}

# ----------------------------------------------------------------------
# USB formatter
# ----------------------------------------------------------------------
$u = Get-Content -LiteralPath $UsbMain -Raw
if ($u -notmatch 'READRAW T0\.0\.1 count=') {
    $anchorPattern = '(?ms)(\}\s*else\s+if\s*\(\s*type\s*==\s*DRIVEHUD_EVENT_UC2A_SAMPLE\s*\)\s*\{.*?\r?\n\s*\})'
    $m = [regex]::Match($u, $anchorPattern)
    if (-not $m.Success) {
        throw "Could not locate existing UC2A USB formatter block."
    }

    $block = @'
}else if(type==DRIVEHUD_EVENT_READRAW){
 uint32_t count=(w>>8)&0x000FFFFFu;
 uint8_t data=(uint8_t)(w&0xFFu);
 p=drivehud_append_str(p,e,"READRAW T0.0.1 count=");
 p=drivehud_append_u32(p,e,count);
 p=drivehud_append_str(p,e," data=$");
 p=drivehud_append_hex8(p,e,data);
 p=drivehud_append_str(p,e,"\r\n");
'@

    $replacement = $m.Groups[1].Value + $block
    $u = $u.Substring(0,$m.Index) + $replacement + $u.Substring($m.Index + $m.Length)
    Set-Content -LiteralPath $UsbMain -Value $u -NoNewline
    Write-Host "Patched: USB READRAW formatter"
} else {
    Write-Host "Already present: USB READRAW formatter"
}

# ----------------------------------------------------------------------
# Sanity checks before build
# ----------------------------------------------------------------------
Write-Host ""
Write-Host "Sanity checks..."

$checks = @(
    @{Path=$T001; Pattern='ORA_DEFINE_USER_PLUGIN\(drivehud_probe_main,\s*0,0,1,0,\s*0,7,1\)'; Name='T0.0.1 plugin version'},
    @{Path=$T001; Pattern='DRIVEHUD_EVENT_READRAW\s*<<\s*28'; Name='READRAW producer'},
    @{Path=$T001; Pattern='uint32_t\s+budget\s*=\s*16u'; Name='bounded DMA10 consumer retained'},
    @{Path=$T001; Pattern='sector_alloc_raw\s*=\s*alloc'; Name='dynamic ring/mailbox collision fix retained'},
    @{Path=$UsbMain; Pattern='READRAW T0\.0\.1 count='; Name='READRAW USB formatter'},
    @{Path=$Makefile; Pattern='1541hud_probe_t001\.c'; Name='Makefile source isolation'}
)

foreach ($c in $checks) {
    $txt = Get-Content -LiteralPath $c.Path -Raw
    if ($txt -notmatch $c.Pattern) { throw "Sanity check failed: $($c.Name)" }
    Write-Host " OK: $($c.Name)"
}

if ((Get-Content -LiteralPath $T001 -Raw) -match 'static\s+volatile\s+uint32_t\s+sector_ring\s*\[') {
    throw "Static sector ring reappeared. Refusing to build."
}

Write-Host ""
Write-Host "Building T0.0.1 RAW READ CAPTURE..."
& powershell.exe -ExecutionPolicy Bypass -File $Build001
if ($LASTEXITCODE -ne 0) { throw "T0.0.1 build failed." }

$BuildDir = Join-Path $Repo "build-1541hud"
$Uf2 = Join-Path $BuildDir "1541HUD_OneROM_T0.0.1.uf2"
$Bin = Join-Path $BuildDir "1541HUD_OneROM_T0.0.1.bin"

if (-not (Test-Path $Uf2)) { throw "Expected UF2 missing: $Uf2" }
if (-not (Test-Path $Bin)) { throw "Expected BIN missing: $Bin" }

Write-Host ""
Write-Host "T0.0.1 BUILD COMPLETE"
Get-FileHash -Algorithm SHA256 $Bin,$Uf2

# Preserve complete matching source/build state automatically.
if (Test-Path $Preserve) {
    Write-Host ""
    Write-Host "Preserving exact T0.0.1 source/build bundle..."
    & powershell.exe -ExecutionPolicy Bypass -File $Preserve -TestName "T0.0.1_RAW_READ_CAPTURE"
    if ($LASTEXITCODE -ne 0) { throw "Build succeeded, but source preservation failed." }
} else {
    throw "Build succeeded but Preserve-1541HUD-TestSource.ps1 is missing. Refusing to call test ready."
}

Write-Host ""
Write-Host "============================================================"
Write-Host "T0.0.1 RAW READ CAPTURE IS BUILT AND SOURCE-PRESERVED"
Write-Host "============================================================"
Write-Host "UF2: $Uf2"
Write-Host ""
Write-Host "Expected new PuTTY telemetry after disk activity:"
Write-Host "  READRAW T0.0.1 count=4096 data=`$XX"
Write-Host "  READRAW T0.0.1 count=8192 data=`$XX"
Write-Host ""
Write-Host "Existing MOTOR / PHASE / TRACK_WRITE / DENSITY / STATE telemetry must remain."
Write-Host "This test does NOT alter PIO sampling timing and does NOT yet use the 22 us timing."
