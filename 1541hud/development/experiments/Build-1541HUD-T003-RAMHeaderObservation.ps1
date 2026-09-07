param(
    [string]$Repo = (Get-Location).Path
)

$ErrorActionPreference = "Stop"

$Baseline = "caf46af18f14cb70bdeb80491f3f7d275b0c6c84"

$ProbeRel      = "plugins/user/1541hud-probe/src/1541hud_probe_v031.c"
$T003Rel       = "plugins/user/1541hud-probe/src/1541hud_probe_t003.c"
$MakefileRel   = "plugins/user/1541hud-probe/Makefile"
$User1541Rel   = "plugins/user/1541hud-probe/src/1541hud_mailbox.h"
$UserCompatRel = "plugins/user/1541hud-probe/src/drivehud_mailbox.h"
$Usb1541Rel    = "plugins/system/usb/include/1541hud_mailbox.h"
$UsbCompatRel  = "plugins/system/usb/include/drivehud_mailbox.h"
$UsbMainRel    = "plugins/system/usb/src/usb_main.c"

$T003       = Join-Path $Repo $T003Rel
$Makefile   = Join-Path $Repo $MakefileRel
$User1541   = Join-Path $Repo $User1541Rel
$UserCompat = Join-Path $Repo $UserCompatRel
$Usb1541    = Join-Path $Repo $Usb1541Rel
$UsbCompat  = Join-Path $Repo $UsbCompatRel
$UsbMain    = Join-Path $Repo $UsbMainRel

$Build031 = Join-Path $Repo "1541hud/Build-1541HUD-V031.ps1"
$Build003 = Join-Path $Repo "1541hud/Build-1541HUD-T003.ps1"
$Preserve = Join-Path $Repo "Preserve-1541HUD-TestSource.ps1"

foreach ($f in @($Build031,$Preserve)) {
    if (-not (Test-Path $f)) { throw "Required file missing: $f" }
}

if (-not (Test-Path (Join-Path $Repo ".git"))) {
    throw "Run this from C:\1541HUD_LOCAL. Git repository not found."
}

$branch = (git -C $Repo branch --show-current).Trim()
if ($branch -ne "dev-1541hud") {
    throw "Refusing to build outside dev-1541hud. Current branch: $branch"
}

# Preserve the entire current working tree state before replacing shared
# experiment files with clean baseline versions.
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$pre = Join-Path $Repo "build-1541hud/T0.0.3_RAM_HEADER_PREP_$stamp"
New-Item -ItemType Directory -Force -Path $pre | Out-Null

git -C $Repo status --short | Set-Content -Encoding UTF8 (Join-Path $pre "pre-t003-git-status.txt")
git -C $Repo diff --binary | Set-Content -Encoding UTF8 (Join-Path $pre "pre-t003-working-tree.patch")
git -C $Repo diff --cached --binary | Set-Content -Encoding UTF8 (Join-Path $pre "pre-t003-staged.patch")

Write-Host "Creating T0.0.3 from clean V0.0.31 baseline $Baseline ..."
Write-Host "T0.0.1/T0.0.2 source files are left intact; shared USB/mailbox files are reset to baseline for this test."

function GitShowToFile {
    param(
        [string]$RelPath,
        [string]$OutPath
    )
    $parent = Split-Path -Parent $OutPath
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $content = git -C $Repo show "${Baseline}:$RelPath"
    if ($LASTEXITCODE -ne 0) {
        throw "git show failed for $RelPath at $Baseline"
    }
    # git show through PowerShell returns an array of lines. Join with LF to
    # preserve normal source semantics without injecting BOM.
    [System.IO.File]::WriteAllText($OutPath, (($content -join "`n") + "`n"),
        (New-Object System.Text.UTF8Encoding($false)))
}

# Clean source path: V0.0.31 baseline, not T0.0.2.
GitShowToFile $ProbeRel      $T003
GitShowToFile $MakefileRel   $Makefile
GitShowToFile $User1541Rel   $User1541
GitShowToFile $UserCompatRel $UserCompat
GitShowToFile $Usb1541Rel    $Usb1541
GitShowToFile $UsbCompatRel  $UsbCompat
GitShowToFile $UsbMainRel    $UsbMain

function ReplaceOnce {
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
    [System.IO.File]::WriteAllText($Path, $s, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Patched: $Label"
}

function InsertAfterLine {
    param(
        [string]$Path,
        [string]$AnchorRegex,
        [string]$Text,
        [string]$Label
    )
    $s = Get-Content -LiteralPath $Path -Raw
    $m = [regex]::Match($s, $AnchorRegex, [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if (-not $m.Success) { throw "Anchor not found: $Label ($Path)" }
    $pos = $m.Index + $m.Length
    $s = $s.Substring(0,$pos) + "`n" + $Text + $s.Substring($pos)
    [System.IO.File]::WriteAllText($Path, $s, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Patched: $Label"
}

# ---------------------------------------------------------------------------
# Isolate test version and source.
# ---------------------------------------------------------------------------
ReplaceOnce $T003 `
    'ORA_DEFINE_USER_PLUGIN\s*\(\s*drivehud_probe_main\s*,\s*0\s*,\s*0\s*,\s*30\s*,\s*0\s*,\s*0\s*,\s*7\s*,\s*1\s*\)\s*;' `
    'ORA_DEFINE_USER_PLUGIN(drivehud_probe_main, 0,0,3,0, 0,7,1);' `
    "T0.0.3 plugin metadata"

ReplaceOnce $Makefile `
    'PLUGIN_SRC\s*:=\s*src/1541hud_probe_v031\.c' `
    'PLUGIN_SRC := src/1541hud_probe_t003.c' `
    "Makefile T0.0.3 source"

# ---------------------------------------------------------------------------
# New event type 6. Mailbox structure/layout is NOT changed.
# ---------------------------------------------------------------------------
foreach ($p in @($User1541,$Usb1541)) {
    InsertAfterLine $p `
        '^#define\s+HUD1541_EVENT_DENSITY\s+5u\s*$' `
        '#define HUD1541_EVENT_HEADER_RAM 6u' `
        "HEADER_RAM event type"
}

foreach ($p in @($UserCompat,$UsbCompat)) {
    InsertAfterLine $p `
        '^#define\s+DRIVEHUD_EVENT_DENSITY\s+HUD1541_EVENT_DENSITY\s*$' `
        '#define DRIVEHUD_EVENT_HEADER_RAM HUD1541_EVENT_HEADER_RAM' `
        "HEADER_RAM compatibility alias"
}

# ---------------------------------------------------------------------------
# RP2350 TIMER0 timestamp source.
#
# RP2350 TIMER0 base = 0x400B0000, TIMERAWL offset = 0x28.
# TIMERAWL is the raw low 32 bits of the microsecond timer.
#
# Event packing:
#   31..28 type = 6
#   27..26 RAM selector: 0=$18, 1=$19, 2=$1A, 3=$22
#   25..18 data byte
#   17..0  TIMERAWL >> 4, modulo 2^18
#
# Timestamp resolution = 16 us.
# Timestamp wrap = 4.194304 seconds.
# This timestamp is taken in decode_snapshot(), i.e. when CPU consumes the
# already-captured write from the proven SM3/DMA11 ring. It is for header-event
# proof/correlation, not final precision RPM measurement.
# ---------------------------------------------------------------------------
InsertAfterLine $T003 `
    '^#define\s+RESET_PIO0\s+\(1u\s*<<\s*11\)\s*$' `
@'
#define TIMER0_BASE 0x400B0000u
#define TIMER0_RAWL (*(volatile uint32_t *)(TIMER0_BASE + 0x28u))
'@ `
    "RP2350 TIMER0 raw microsecond register"

InsertAfterLine $T003 `
    '^#define\s+RAM_LWPT\s+0x001Eu\s*$' `
@'
#define RAM_HDRTRK 0x0018u
#define RAM_HDRSEC 0x0019u
#define RAM_HDRCHK 0x001Au
'@ `
    "header RAM addresses"

# Add compact queue helper after queue_density().
ReplaceOnce $T003 `
    '(static void queue_density\(volatile drivehud_mailbox_t \*m,\s*uint8_t density\)\s*\{\s*queue_event\(m,\s*\(DRIVEHUD_EVENT_DENSITY << 28\)\s*\|\s*\(uint32_t\)\(density & 3u\)\);\s*\})' `
@'
$1

static void queue_header_ram(volatile drivehud_mailbox_t *m,
 uint8_t reg_id, uint8_t data) {
 uint32_t ticks16 = (TIMER0_RAWL >> 4) & 0x0003FFFFu;
 queue_event(m,
 (DRIVEHUD_EVENT_HEADER_RAM << 28) |
 ((uint32_t)(reg_id & 3u) << 26) |
 ((uint32_t)data << 18) |
 ticks16);
}
'@ `
    "timestamped HEADER_RAM queue helper"

# Add $18/$19/$1A write observation immediately before DRVST processing.
ReplaceOnce $T003 `
    '(\n\s*if\s*\(\s*ram_write_at\(snapshot,\s*RAM_DRVST\)\s*\)\s*\{)' `
@'

 if (ram_write_at(snapshot, RAM_HDRTRK)) {
 uint8_t data = logical_data_from_gpio(snapshot);
 queue_header_ram(m, 0u, data);
 }

 if (ram_write_at(snapshot, RAM_HDRSEC)) {
 uint8_t data = logical_data_from_gpio(snapshot);
 queue_header_ram(m, 1u, data);
 }

 if (ram_write_at(snapshot, RAM_HDRCHK)) {
 uint8_t data = logical_data_from_gpio(snapshot);
 queue_header_ram(m, 2u, data);
 }
$1
'@ `
    '$0018/$0019/$001A observation'

# Existing $0022 semantics stay untouched; add one parallel timestamp event.
ReplaceOnce $T003 `
    '(\*last_track_write\s*=\s*data;\s*\*track_write_valid\s*=\s*1u;\s*queue_track_write\(m,\s*data\);)' `
@'
$1
 queue_header_ram(m, 3u, data);
'@ `
    '$0022 timestamp correlation event'

# ---------------------------------------------------------------------------
# USB formatter for HEADER_RAM.
# ---------------------------------------------------------------------------
$usbBlock = @'
}else if(type==DRIVEHUD_EVENT_HEADER_RAM){
 uint32_t reg=(w>>26)&3u;
 uint8_t data=(uint8_t)((w>>18)&0xFFu);
 uint32_t timestamp_us_mod=(w&0x0003FFFFu)<<4;
 p=drivehud_append_str(p,e,"HDRRAM T0.0.3 addr=$");
 if(reg==0u)p=drivehud_append_str(p,e,"0018");
 else if(reg==1u)p=drivehud_append_str(p,e,"0019");
 else if(reg==2u)p=drivehud_append_str(p,e,"001A");
 else p=drivehud_append_str(p,e,"0022");
 p=drivehud_append_str(p,e," data=$");p=drivehud_append_hex8(p,e,data);
 p=drivehud_append_str(p,e," (");p=drivehud_append_u32(p,e,data);
 p=drivehud_append_str(p,e,") timestamp_us_mod=");
 p=drivehud_append_u32(p,e,timestamp_us_mod);
 if(reg==1u && data==0u)p=drivehud_append_str(p,e," SECTOR0");
 p=drivehud_append_str(p,e,"\r\n");
'@

ReplaceOnce $UsbMain `
    '(\}else if\(type==DRIVEHUD_EVENT_DENSITY\)\{\s*p=drivehud_append_str\(p,e,"DENSITY state="\);\s*p=drivehud_append_u32\(p,e,w&3u\);\s*p=drivehud_append_str\(p,e,"\\r\\n"\);\s*)\}else\{' `
    ('$1' + $usbBlock + '}else{') `
    "USB HEADER_RAM formatter"

# ---------------------------------------------------------------------------
# Separate build script. Stable V031 script remains untouched.
# ---------------------------------------------------------------------------
Copy-Item $Build031 $Build003 -Force
$b = Get-Content -LiteralPath $Build003 -Raw
$b = $b.Replace("V0.0.31", "T0.0.3")
$b = $b.Replace("V031", "T003")
$b = $b.Replace("1541HUD_OneROM_V0.0.31", "1541HUD_OneROM_T0.0.3")
[System.IO.File]::WriteAllText($Build003, $b, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Created: 1541hud/Build-1541HUD-T003.ps1"

# ---------------------------------------------------------------------------
# Sanity checks: explicitly prove the abandoned SM2/DMA10 experiment is absent.
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "Sanity checks..."

$probe = Get-Content -LiteralPath $T003 -Raw
$usb   = Get-Content -LiteralPath $UsbMain -Raw
$mk    = Get-Content -LiteralPath $Makefile -Raw

$required = @(
    @{Ok=($probe -match 'ORA_DEFINE_USER_PLUGIN\(drivehud_probe_main,\s*0,0,3,0,\s*0,7,1\)'); Name="T0.0.3 plugin metadata"},
    @{Ok=($probe -match 'RAM_HDRTRK\s+0x0018u'); Name='$0018 defined'},
    @{Ok=($probe -match 'RAM_HDRSEC\s+0x0019u'); Name='$0019 defined'},
    @{Ok=($probe -match 'RAM_HDRCHK\s+0x001Au'); Name='$001A defined'},
    @{Ok=($probe -match 'TIMER0_RAWL'); Name="TIMER0 timestamp"},
    @{Ok=($probe -match 'queue_header_ram\(m,\s*1u,\s*data\)'); Name='$0019 event'},
    @{Ok=($probe -match 'queue_header_ram\(m,\s*3u,\s*data\)'); Name='$0022 correlation event'},
    @{Ok=($usb -match 'HDRRAM T0\.0\.3 addr=\$'); Name="USB HDRRAM formatter"},
    @{Ok=($usb -match 'SECTOR0'); Name="SECTOR0 marker"},
    @{Ok=($mk -match '1541hud_probe_t003\.c'); Name="Makefile source isolation"}
)

foreach ($c in $required) {
    if (-not $c.Ok) { throw "Sanity check failed: $($c.Name)" }
    Write-Host " OK: $($c.Name)"
}

$forbidden = @(
    "DMA10",
    "PIO_SM2",
    "READRAW",
    "READDMA",
    "UC2A_SAMPLE",
    "sector_ring",
    "sector_dma_update_producer"
)
foreach ($term in $forbidden) {
    if ($probe -match [regex]::Escape($term)) {
        throw "Experimental read-path term unexpectedly present in T0.0.3 probe: $term"
    }
}
Write-Host " OK: SM2/DMA10 experimental read path absent"

if ($usb -match 'READRAW|READDMA|UC2A T0\.0') {
    throw "Experimental T0.0.1/T0.0.2 USB formatter residue remains."
}
Write-Host " OK: experimental USB formatter residue absent"

# Mailbox ABI must remain exactly 512 bytes / ring offset 0x100 via existing
# compile-time assertions. We added only a define, never struct members.
Write-Host " OK: mailbox struct was restored from baseline and only event define added"

# ---------------------------------------------------------------------------
# Build.
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "Building T0.0.3 RAM HEADER OBSERVATION..."
& powershell.exe -ExecutionPolicy Bypass -File $Build003
if ($LASTEXITCODE -ne 0) {
    throw "T0.0.3 build failed."
}

$BuildDir = Join-Path $Repo "build-1541hud"
$Uf2 = Join-Path $BuildDir "1541HUD_OneROM_T0.0.3.uf2"
$Bin = Join-Path $BuildDir "1541HUD_OneROM_T0.0.3.bin"

if (-not (Test-Path $Uf2)) { throw "Expected UF2 missing: $Uf2" }
if (-not (Test-Path $Bin)) { throw "Expected BIN missing: $Bin" }

Write-Host ""
Write-Host "T0.0.3 BUILD COMPLETE"
Get-FileHash -Algorithm SHA256 $Bin,$Uf2

# Preserve exact source/binary state. If this script does not complete, the
# firmware may exist but is NOT considered test-ready under project policy.
Write-Host ""
Write-Host "Preserving exact T0.0.3 source/build bundle..."
& powershell.exe -ExecutionPolicy Bypass -File $Preserve -TestName "T0.0.3_RAM_HEADER_OBSERVATION"
if ($LASTEXITCODE -ne 0) {
    throw "Build succeeded but source preservation failed. Do not flash."
}

Write-Host ""
Write-Host "============================================================"
Write-Host "T0.0.3 RAM HEADER OBSERVATION READY"
Write-Host "============================================================"
Write-Host "UF2: $Uf2"
Write-Host ""
Write-Host "Expected records:"
Write-Host '  HDRRAM T0.0.3 addr=$0018 data=$12 (18) timestamp_us_mod=...'
Write-Host '  HDRRAM T0.0.3 addr=$0019 data=$00 (0) timestamp_us_mod=... SECTOR0'
Write-Host '  HDRRAM T0.0.3 addr=$001A data=$XX (...) timestamp_us_mod=...'
Write-Host '  HDRRAM T0.0.3 addr=$0022 data=$12 (18) timestamp_us_mod=...'
Write-Host ""
Write-Host "Existing STATE / STATUS / TRACK_WRITE / MOTOR / PHASE / DENSITY / WP records remain."
Write-Host "Timestamp resolution: 16 us; wraps every 4.194304 s."
Write-Host "This is a RAM-header proof test, not yet final precision RPM timing."
