param(
    [string]$Repo = (Get-Location).Path
)

$ErrorActionPreference = "Stop"

$Baseline = "caf46af18f14cb70bdeb80491f3f7d275b0c6c84"

$ProbeRel      = "plugins/user/1541hud-probe/src/1541hud_probe_v031.c"
$T004Rel       = "plugins/user/1541hud-probe/src/1541hud_probe_t004.c"
$MakefileRel   = "plugins/user/1541hud-probe/Makefile"
$User1541Rel   = "plugins/user/1541hud-probe/src/1541hud_mailbox.h"
$UserCompatRel = "plugins/user/1541hud-probe/src/drivehud_mailbox.h"
$Usb1541Rel    = "plugins/system/usb/include/1541hud_mailbox.h"
$UsbCompatRel  = "plugins/system/usb/include/drivehud_mailbox.h"
$UsbMainRel    = "plugins/system/usb/src/usb_main.c"

$T004       = Join-Path $Repo $T004Rel
$Makefile   = Join-Path $Repo $MakefileRel
$User1541   = Join-Path $Repo $User1541Rel
$UserCompat = Join-Path $Repo $UserCompatRel
$Usb1541    = Join-Path $Repo $Usb1541Rel
$UsbCompat  = Join-Path $Repo $UsbCompatRel
$UsbMain    = Join-Path $Repo $UsbMainRel

$Build031 = Join-Path $Repo "1541hud/Build-1541HUD-V031.ps1"
$Build004 = Join-Path $Repo "1541hud/Build-1541HUD-T004.ps1"
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

# Preserve the exact current pre-T0.0.4 state before resetting shared
# experiment files back to the clean V0.0.31 baseline.
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$pre = Join-Path $Repo "build-1541hud/T0.0.4_SECTOR0_PREP_$stamp"
New-Item -ItemType Directory -Force -Path $pre | Out-Null

git -C $Repo status --short | Set-Content -Encoding UTF8 (Join-Path $pre "pre-t004-git-status.txt")
git -C $Repo diff --binary | Set-Content -Encoding UTF8 (Join-Path $pre "pre-t004-working-tree.patch")
git -C $Repo diff --cached --binary | Set-Content -Encoding UTF8 (Join-Path $pre "pre-t004-staged.patch")

Write-Host "Creating T0.0.4 from clean V0.0.31 baseline $Baseline ..."
Write-Host "T0.0.3 remains preserved as its own source file."
Write-Host "T0.0.4 adds only compact Sector-0 telemetry to the proven V0.0.30/V0.0.31 path."

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

    [System.IO.File]::WriteAllText(
        $OutPath,
        (($content -join "`n") + "`n"),
        (New-Object System.Text.UTF8Encoding($false))
    )
}

# Start from the known-stable source and transport, not from T0.0.3.
GitShowToFile $ProbeRel      $T004
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
    $re = [regex]::new(
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    if (-not $re.IsMatch($s)) {
        throw "Patch point not found: $Label ($Path)"
    }

    $s = $re.Replace($s, $Replacement, 1)
    [System.IO.File]::WriteAllText(
        $Path, $s, (New-Object System.Text.UTF8Encoding($false))
    )

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
    $m = [regex]::Match(
        $s,
        $AnchorRegex,
        [System.Text.RegularExpressions.RegexOptions]::Multiline
    )

    if (-not $m.Success) {
        throw "Anchor not found: $Label ($Path)"
    }

    $pos = $m.Index + $m.Length
    $s = $s.Substring(0,$pos) + "`n" + $Text + $s.Substring($pos)

    [System.IO.File]::WriteAllText(
        $Path, $s, (New-Object System.Text.UTF8Encoding($false))
    )

    Write-Host "Patched: $Label"
}

# ---------------------------------------------------------------------------
# Isolated temporary version/source.
# ---------------------------------------------------------------------------
ReplaceOnce $T004 `
    'ORA_DEFINE_USER_PLUGIN\s*\(\s*drivehud_probe_main\s*,\s*0\s*,\s*0\s*,\s*30\s*,\s*0\s*,\s*0\s*,\s*7\s*,\s*1\s*\)\s*;' `
    'ORA_DEFINE_USER_PLUGIN(drivehud_probe_main, 0,0,4,0, 0,7,1);' `
    "T0.0.4 plugin metadata"

ReplaceOnce $Makefile `
    'PLUGIN_SRC\s*:=\s*src/1541hud_probe_v031\.c' `
    'PLUGIN_SRC := src/1541hud_probe_t004.c' `
    "Makefile T0.0.4 source"

# ---------------------------------------------------------------------------
# Event type 6. Mailbox ABI stays byte-for-byte identical.
# ---------------------------------------------------------------------------
foreach ($p in @($User1541,$Usb1541)) {
    InsertAfterLine $p `
        '^#define\s+HUD1541_EVENT_DENSITY\s+5u\s*$' `
        '#define HUD1541_EVENT_SECTOR0 6u' `
        "SECTOR0 event type"
}

foreach ($p in @($UserCompat,$UsbCompat)) {
    InsertAfterLine $p `
        '^#define\s+DRIVEHUD_EVENT_DENSITY\s+HUD1541_EVENT_DENSITY\s*$' `
        '#define DRIVEHUD_EVENT_SECTOR0 HUD1541_EVENT_SECTOR0' `
        "SECTOR0 compatibility alias"
}

# ---------------------------------------------------------------------------
# TIMER0 low raw microsecond counter.
#
# Event payload:
# 31..28  type 6
# 27..21  cached DOS track (7 bits)
# 20..0   TIMERAWL / 16 (21 bits)
#
# 16 us resolution, modulo 33.554432 seconds.
# No new DMA, no new PIO state machine, no mailbox layout change.
# ---------------------------------------------------------------------------
InsertAfterLine $T004 `
    '^#define\s+RESET_PIO0\s+\(1u\s*<<\s*11\)\s*$' `
@'
#define TIMER0_BASE 0x400B0000u
#define TIMER0_RAWL (*(volatile uint32_t *)(TIMER0_BASE + 0x28u))
'@ `
    "RP2350 TIMER0 timestamp source"

InsertAfterLine $T004 `
    '^#define\s+RAM_LWPT\s+0x001Eu\s*$' `
    '#define RAM_HDRSEC 0x0019u' `
    '$0019 header-sector RAM address'

# Add one tiny queue helper after queue_density().
ReplaceOnce $T004 `
    '(static void queue_density\(volatile drivehud_mailbox_t \*m,\s*uint8_t density\)\s*\{\s*queue_event\(m,\s*\(DRIVEHUD_EVENT_DENSITY << 28\)\s*\|\s*\(uint32_t\)\(density & 3u\)\);\s*\})' `
@'
$1

static void queue_sector0(volatile drivehud_mailbox_t *m, uint8_t track) {
 uint32_t ticks16 = (TIMER0_RAWL >> 4) & 0x001FFFFFu;
 queue_event(m,
 (DRIVEHUD_EVENT_SECTOR0 << 28) |
 ((uint32_t)(track & 0x7Fu) << 21) |
 ticks16);
}
'@ `
    "compact Sector-0 queue helper"

# Observe ONLY $0019 writes. Emit only when the decoded header sector is zero.
# Use the existing cached $0022 value as requested. No $18/$1A diagnostic spam.
ReplaceOnce $T004 `
    '(\n\s*if\s*\(\s*ram_write_at\(snapshot,\s*RAM_DRVST\)\s*\)\s*\{)' `
@'

 if (ram_write_at(snapshot, RAM_HDRSEC)) {
 uint8_t data = logical_data_from_gpio(snapshot);
 if (data == 0u) {
 uint8_t track = (*track_write_valid &&
                  *last_track_write >= 1u &&
                  *last_track_write <= 127u)
                   ? *last_track_write : 0u;
 queue_sector0(m, track);
 }
 }
$1
'@ `
    '$0019 == 0 Sector-0 detector'

# ---------------------------------------------------------------------------
# USB formatter. One line per Sector-0 hit.
#
# The formatter calculates the revolution interval from successive 21-bit
# timestamps. This diagnostic state is local to USB output only; the original
# V0.0.30 GUI protocol/state path is otherwise untouched.
# ---------------------------------------------------------------------------
$usbBlock = @'
}else if(type==DRIVEHUD_EVENT_SECTOR0){
 static uint32_t s0_hit=0u;
 static uint32_t s0_last_ticks16=0u;
 static uint8_t s0_have_last=0u;
 uint32_t track=(w>>21)&0x7Fu;
 uint32_t ticks16=w&0x001FFFFFu;
 uint32_t timestamp_us_mod=ticks16<<4;
 uint32_t rev_us=0u;

 s0_hit++;
 if(s0_have_last){
  uint32_t dticks=(ticks16-s0_last_ticks16)&0x001FFFFFu;
  rev_us=dticks<<4;
 }
 s0_last_ticks16=ticks16;
 s0_have_last=1u;

 p=drivehud_append_str(p,e,"SECTOR0 T0.0.4 TRACK=");
 p=drivehud_append_u32(p,e,track);
 p=drivehud_append_str(p,e," HIT=");
 p=drivehud_append_u32(p,e,s0_hit);
 p=drivehud_append_str(p,e," TIMESTAMP_US_MOD=");
 p=drivehud_append_u32(p,e,timestamp_us_mod);
 p=drivehud_append_str(p,e," REV_US=");
 p=drivehud_append_u32(p,e,rev_us);
 p=drivehud_append_str(p,e,"\r\n");
'@

ReplaceOnce $UsbMain `
    '(\}else if\(type==DRIVEHUD_EVENT_DENSITY\)\{\s*p=drivehud_append_str\(p,e,"DENSITY state="\);\s*p=drivehud_append_u32\(p,e,w&3u\);\s*p=drivehud_append_str\(p,e,"\\r\\n"\);\s*)\}else\{' `
    ('$1' + $usbBlock + '}else{') `
    "USB Sector-0 formatter"

# ---------------------------------------------------------------------------
# Separate build script. V031 build script remains untouched.
# ---------------------------------------------------------------------------
Copy-Item $Build031 $Build004 -Force
$b = Get-Content -LiteralPath $Build004 -Raw
$b = $b.Replace("V0.0.31", "T0.0.4")
$b = $b.Replace("V031", "T004")
$b = $b.Replace("1541HUD_OneROM_V0.0.31", "1541HUD_OneROM_T0.0.4")
[System.IO.File]::WriteAllText(
    $Build004, $b, (New-Object System.Text.UTF8Encoding($false))
)
Write-Host "Created: 1541hud/Build-1541HUD-T004.ps1"

# ---------------------------------------------------------------------------
# Sanity checks. T0.0.4 must remain the stable V0.0.30/V0.0.31 path plus
# Sector-0 only.
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "Sanity checks..."

$probe = Get-Content -LiteralPath $T004 -Raw
$usb   = Get-Content -LiteralPath $UsbMain -Raw
$mk    = Get-Content -LiteralPath $Makefile -Raw

$required = @(
    @{Ok=($probe -match 'ORA_DEFINE_USER_PLUGIN\(drivehud_probe_main,\s*0,0,4,0,\s*0,7,1\)'); Name="T0.0.4 plugin metadata"},
    @{Ok=($probe -match 'RAM_HDRSEC\s+0x0019u'); Name='$0019 detector'},
    @{Ok=($probe -match 'data\s*==\s*0u'); Name="Sector zero comparison"},
    @{Ok=($probe -match 'DRIVEHUD_EVENT_SECTOR0\s*<<\s*28'); Name="compact Sector-0 event"},
    @{Ok=($probe -match 'TIMER0_RAWL'); Name="timestamp source"},
    @{Ok=($usb -match 'SECTOR0 T0\.0\.4 TRACK='); Name="Sector-0 USB output"},
    @{Ok=($usb -match 'REV_US='); Name="revolution interval output"},
    @{Ok=($mk -match '1541hud_probe_t004\.c'); Name="Makefile source isolation"},
    @{Ok=($probe -match 'queue_track_write\(m,\s*data\)'); Name="original TRACK_WRITE preserved"},
    @{Ok=($probe -match 'queue_motor\(m,\s*motor\)'); Name="original MOTOR preserved"},
    @{Ok=($probe -match 'queue_phase\(m,\s*oldp,\s*phase,\s*delta,\s*motor\)'); Name="original PHASE preserved"},
    @{Ok=($probe -match 'queue_density\(m,\s*density\)'); Name="original DENSITY preserved"},
    @{Ok=($probe -match 'queue_write_protect\(m,\s*wp\)'); Name="original WRITE_PROTECT preserved"}
)

foreach ($c in $required) {
    if (-not $c.Ok) {
        throw "Sanity check failed: $($c.Name)"
    }
    Write-Host " OK: $($c.Name)"
}

# Explicitly reject all abandoned high-rate experimental pieces.
$forbiddenProbe = @(
    "DMA10",
    "PIO_SM2",
    "READRAW",
    "READDMA",
    "UC2A_SAMPLE",
    "sector_ring",
    "sector_dma_update_producer",
    "RAM_HDRTRK",
    "RAM_HDRCHK",
    "HDRRAM T0.0.3"
)

foreach ($term in $forbiddenProbe) {
    if ($probe -match [regex]::Escape($term)) {
        throw "Unexpected experimental/high-rate term in T0.0.4 probe: $term"
    }
}
Write-Host " OK: SM2/DMA10 and T0.0.3 high-rate diagnostics absent"

if ($usb -match 'READRAW|READDMA|UC2A T0\.0|HDRRAM T0\.0\.3') {
    throw "Old experimental USB formatter residue remains."
}
Write-Host " OK: old experimental USB formatter residue absent"

# The mailbox struct came directly from baseline; only an event #define was added.
Write-Host " OK: mailbox ABI restored from stable baseline"

# ---------------------------------------------------------------------------
# Build.
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "Building T0.0.4 SECTOR-0 ONLY..."
& powershell.exe -ExecutionPolicy Bypass -File $Build004
if ($LASTEXITCODE -ne 0) {
    throw "T0.0.4 build failed."
}

$BuildDir = Join-Path $Repo "build-1541hud"
$Uf2 = Join-Path $BuildDir "1541HUD_OneROM_T0.0.4.uf2"
$Bin = Join-Path $BuildDir "1541HUD_OneROM_T0.0.4.bin"

if (-not (Test-Path $Uf2)) {
    throw "Expected UF2 missing: $Uf2"
}
if (-not (Test-Path $Bin)) {
    throw "Expected BIN missing: $Bin"
}

Write-Host ""
Write-Host "T0.0.4 BUILD COMPLETE"
Get-FileHash -Algorithm SHA256 $Bin,$Uf2

# Exact source/binary preservation is mandatory for every hardware test.
Write-Host ""
Write-Host "Preserving exact T0.0.4 source/build bundle..."
& powershell.exe -ExecutionPolicy Bypass -File $Preserve -TestName "T0.0.4_SECTOR0_ONLY"
if ($LASTEXITCODE -ne 0) {
    throw "Build succeeded but source preservation failed. Do not flash."
}

Write-Host ""
Write-Host "============================================================"
Write-Host "T0.0.4 SECTOR-0 ONLY READY"
Write-Host "============================================================"
Write-Host "UF2: $Uf2"
Write-Host ""
Write-Host "Expected new line, approximately once per revolution while DOS is seeing sector 0:"
Write-Host "  SECTOR0 T0.0.4 TRACK=18 HIT=2 TIMESTAMP_US_MOD=123456 REV_US=199792"
Write-Host ""
Write-Host "REV_US on HIT=1 is 0 by definition."
Write-Host "Original STATE / STATUS / TRACK_WRITE / MOTOR / PHASE / DENSITY / WRITE_PROTECT remain."
Write-Host "No $0018/$001A/$0022 duplicate diagnostic lines are added."
Write-Host "No SM2, DMA10, raw GCR, or BYTE READY path is used."
