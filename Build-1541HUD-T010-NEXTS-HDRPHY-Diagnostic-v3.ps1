param(
    [string]$Repo = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
$Baseline = "caf46af18f14cb70bdeb80491f3f7d275b0c6c84"

$ProbeRel      = "plugins/user/1541hud-probe/src/1541hud_probe_v031.c"
$T010Rel       = "plugins/user/1541hud-probe/src/1541hud_probe_t010.c"
$MakefileRel   = "plugins/user/1541hud-probe/Makefile"
$User1541Rel   = "plugins/user/1541hud-probe/src/1541hud_mailbox.h"
$UserCompatRel = "plugins/user/1541hud-probe/src/drivehud_mailbox.h"
$Usb1541Rel    = "plugins/system/usb/include/1541hud_mailbox.h"
$UsbCompatRel  = "plugins/system/usb/include/drivehud_mailbox.h"
$UsbMainRel    = "plugins/system/usb/src/usb_main.c"

$T010       = Join-Path $Repo $T010Rel
$Makefile   = Join-Path $Repo $MakefileRel
$User1541   = Join-Path $Repo $User1541Rel
$UserCompat = Join-Path $Repo $UserCompatRel
$Usb1541    = Join-Path $Repo $Usb1541Rel
$UsbCompat  = Join-Path $Repo $UsbCompatRel
$UsbMain    = Join-Path $Repo $UsbMainRel

$Build031 = Join-Path $Repo "1541hud/Build-1541HUD-V031.ps1"
$Build010 = Join-Path $Repo "1541hud/Build-1541HUD-T010.ps1"
$Preserve = Join-Path $Repo "Preserve-1541HUD-TestSource.ps1"

foreach ($f in @($Build031,$Preserve)) {
    if (-not (Test-Path $f)) { throw "Required file missing: $f" }
}

if (-not (Test-Path (Join-Path $Repo ".git"))) {
    throw "Run this from C:\1541HUD_LOCAL."
}
$branch = (git -C $Repo branch --show-current).Trim()
if ($branch -ne "dev-1541hud") {
    throw "Refusing to build outside dev-1541hud. Current branch: $branch"
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$pre = Join-Path $Repo "build-1541hud/T0.0.10_NEXTS_HDRPHY_PREP_$stamp"
New-Item -ItemType Directory -Force -Path $pre | Out-Null
git -C $Repo status --short | Set-Content -Encoding UTF8 (Join-Path $pre "pre-t010-git-status.txt")
git -C $Repo diff --binary | Set-Content -Encoding UTF8 (Join-Path $pre "pre-t010-working-tree.patch")
git -C $Repo diff --cached --binary | Set-Content -Encoding UTF8 (Join-Path $pre "pre-t010-staged.patch")

function GitShowToFile {
    param([string]$RelPath,[string]$OutPath)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutPath) | Out-Null
    $content = git -C $Repo show "${Baseline}:$RelPath"
    if ($LASTEXITCODE -ne 0) { throw "git show failed: $RelPath" }
    [System.IO.File]::WriteAllText($OutPath,(($content -join "`n")+"`n"),
        (New-Object System.Text.UTF8Encoding($false)))
}

Write-Host "Restoring clean V0.0.31 shared sources..."
GitShowToFile $ProbeRel      $T010
GitShowToFile $MakefileRel   $Makefile
GitShowToFile $User1541Rel   $User1541
GitShowToFile $UserCompatRel $UserCompat
GitShowToFile $Usb1541Rel    $Usb1541
GitShowToFile $UsbCompatRel  $UsbCompat
GitShowToFile $UsbMainRel    $UsbMain

function ReplaceOnce {
    param([string]$Path,[string]$Pattern,[string]$Replacement,[string]$Label)
    $s=Get-Content -LiteralPath $Path -Raw
    $re=[regex]::new($Pattern,[System.Text.RegularExpressions.RegexOptions]::Singleline)
    if(-not $re.IsMatch($s)){throw "Patch point not found: $Label"}
    $s=$re.Replace($s,$Replacement,1)
    [System.IO.File]::WriteAllText($Path,$s,(New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Patched: $Label"
}
function InsertAfterLine {
    param([string]$Path,[string]$AnchorRegex,[string]$Text,[string]$Label)
    $s=Get-Content -LiteralPath $Path -Raw
    $m=[regex]::Match($s,$AnchorRegex,[System.Text.RegularExpressions.RegexOptions]::Multiline)
    if(-not $m.Success){throw "Anchor not found: $Label"}
    $pos=$m.Index+$m.Length
    $s=$s.Substring(0,$pos)+"`n"+$Text+$s.Substring($pos)
    [System.IO.File]::WriteAllText($Path,$s,(New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Patched: $Label"
}

ReplaceOnce $T010 `
'ORA_DEFINE_USER_PLUGIN\s*\(\s*drivehud_probe_main\s*,\s*0\s*,\s*0\s*,\s*30\s*,\s*0\s*,\s*0\s*,\s*7\s*,\s*1\s*\)\s*;' `
'ORA_DEFINE_USER_PLUGIN(drivehud_probe_main, 0,0,9,0, 0,7,1);' `
"T0.0.10 metadata"

ReplaceOnce $Makefile `
'PLUGIN_SRC\s*:=\s*src/1541hud_probe_v031\.c' `
'PLUGIN_SRC := src/1541hud_probe_t010.c' `
"Makefile source"

foreach($p in @($User1541,$Usb1541)){
    InsertAfterLine $p '^#define\s+HUD1541_EVENT_DENSITY\s+5u\s*$' @'
#define HUD1541_EVENT_NEXTS_DIAG 6u
#define HUD1541_EVENT_HDRPHY_DIAG 7u
'@ "T0.0.10 diagnostic events"
}
foreach($p in @($UserCompat,$UsbCompat)){
    InsertAfterLine $p '^#define\s+DRIVEHUD_EVENT_DENSITY\s+HUD1541_EVENT_DENSITY\s*$' @'
#define DRIVEHUD_EVENT_NEXTS_DIAG HUD1541_EVENT_NEXTS_DIAG
#define DRIVEHUD_EVENT_HDRPHY_DIAG HUD1541_EVENT_HDRPHY_DIAG
'@ "T0.0.10 diagnostic aliases"
}

InsertAfterLine $T010 '^#define\s+RESET_PIO0\s+\(1u\s*<<\s*11\)\s*$' @'
#define TIMER0_BASE 0x400B0000u
#define TIMER0_RAWL (*(volatile uint32_t *)(TIMER0_BASE + 0x28u))
'@ "timer"

InsertAfterLine $T010 '^#define\s+RAM_LWPT\s+0x001Eu\s*$' @'
#define RAM_HDRID2 0x0016u
#define RAM_HDRID1 0x0017u
#define RAM_HDRTRK 0x0018u
#define RAM_HDRSEC 0x0019u
#define RAM_HDRCHK 0x001Au
#define RAM_NEXTS  0x004Du
'@ "T0.0.10 RAM addresses"

ReplaceOnce $T010 `
'(static void queue_density\(volatile drivehud_mailbox_t \*m,\s*uint8_t density\)\s*\{\s*queue_event\(m,\s*\(DRIVEHUD_EVENT_DENSITY << 28\)\s*\|\s*\(uint32_t\)\(density & 3u\)\);\s*\})' @'
$1

/* T0.0.10:
 * type 6 NEXTS: bits 27:21 track, 20:16 NEXTS, 15:0 timestamp/16us
 * type 7 HDRPHY: bits 27:21 decoded track, 20:16 decoded sector,
 *                15:0 timestamp captured at the $0019 write.
 */
static void queue_nexts_diag(volatile drivehud_mailbox_t *m,
 uint8_t track, uint8_t nexts) {
 uint32_t ticks16 = (TIMER0_RAWL >> 4) & 0x0000FFFFu;
 queue_event(m,
  (DRIVEHUD_EVENT_NEXTS_DIAG << 28) |
  ((uint32_t)(track & 0x7Fu) << 21) |
  ((uint32_t)(nexts & 0x1Fu) << 16) |
  ticks16);
}

static void queue_hdrphy_diag(volatile drivehud_mailbox_t *m,
 uint8_t track, uint8_t sector, uint16_t ticks16) {
 queue_event(m,
  (DRIVEHUD_EVENT_HDRPHY_DIAG << 28) |
  ((uint32_t)(track & 0x7Fu) << 21) |
  ((uint32_t)(sector & 0x1Fu) << 16) |
  (uint32_t)ticks16);
}
'@ "T0.0.10 queue helpers"

# Carry tiny header detector state as ordinary locals in drivehud_probe_main.
# This avoids the mailbox-corrupting .bss mistake from T0.0.6.
ReplaceOnce $T010 `
'(uint8_t\s*\*pos_valid\s*,\s*uint8_t\s*\*current_pos2\s*,\s*uint8_t\s*\*last_drvst\s*,\s*uint8_t\s*\*stepping\s*)\)\s*\{' @'
$1,
 uint8_t *hdr_state, uint8_t *hdr_track, uint8_t *hdr_sector,
 uint16_t *hdr_ticks16) {
'@ "decode_snapshot header-state parameters"

# Insert diagnostic decode immediately before the existing DRVST handling.
ReplaceOnce $T010 `
'(\n\s*if\s*\(\s*ram_write_at\(snapshot,\s*RAM_DRVST\)\s*\)\s*\{)' @'

 /* NEXTS is the primary RPM timing source. Only label it with a raw,
  * nonzero $0022 track. This mirrors the T0.0.8 qualification rule.
  */
 if (ram_write_at(snapshot, RAM_NEXTS)) {
  uint8_t data = logical_data_from_gpio(snapshot);
  if (*track_write_valid &&
      *last_track_write >= 1u &&
      *last_track_write <= 127u) {
   queue_nexts_diag(m, *last_track_write, data);
  }
 }

 /* Physical decoded-header signature from stock/Jiffy/Speed/Dolphin ROM:
  * actual decode order: $18 -> $19 -> $1A -> $17 -> $16
  * expected/pre-search image: $16 -> $17 -> $18 -> $19 -> $1A
  *
  * Ignore non-header RAM writes between these stores. A new $18 always
  * restarts the candidate. Timestamp is captured at $19 and emitted only
  * after the trailing $17,$16 proves the physical-decode ordering.
  */
 if (ram_write_at(snapshot, RAM_HDRTRK)) {
  *hdr_track = logical_data_from_gpio(snapshot);
  *hdr_state = 1u;
 } else if (ram_write_at(snapshot, RAM_HDRSEC)) {
  if (*hdr_state == 1u) {
   *hdr_sector = logical_data_from_gpio(snapshot);
   *hdr_ticks16 = (uint16_t)((TIMER0_RAWL >> 4) & 0xFFFFu);
   *hdr_state = 2u;
  } else {
   *hdr_state = 0u;
  }
 } else if (ram_write_at(snapshot, RAM_HDRCHK)) {
  *hdr_state = (*hdr_state == 2u) ? 3u : 0u;
 } else if (ram_write_at(snapshot, RAM_HDRID1)) {
  *hdr_state = (*hdr_state == 3u) ? 4u : 0u;
 } else if (ram_write_at(snapshot, RAM_HDRID2)) {
  if (*hdr_state == 4u &&
      *hdr_track >= 1u && *hdr_track <= 127u &&
      *hdr_sector <= 31u) {
   queue_hdrphy_diag(m, *hdr_track, *hdr_sector, *hdr_ticks16);
  }
  *hdr_state = 0u;
 }
$1
'@ "NEXTS plus physical-header signature decoder"

# Add local state beside the existing local runtime state.
InsertAfterLine $T010 `
'^\s*uint8_t\s+last_drvst\s*=\s*0u\s*,\s*stepping\s*=\s*0u\s*;\s*$' @'
 uint8_t hdr_state = 0u, hdr_track = 0u, hdr_sector = 0u;
 uint16_t hdr_ticks16 = 0u;
'@ "T0.0.10 local header detector state"

ReplaceOnce $T010 `
'(&pos_valid,\s*&current_pos2,\s*\n\s*&last_drvst,\s*&stepping)\s*\);' @'
&pos_valid, &current_pos2,
 &last_drvst, &stepping,
 &hdr_state, &hdr_track, &hdr_sector, &hdr_ticks16);
'@ "decode_snapshot call"

$usbBlock=@'
}else if(type==DRIVEHUD_EVENT_NEXTS_DIAG){
 uint32_t track=(w>>21)&0x7Fu;
 uint32_t nexts=(w>>16)&0x1Fu;
 uint32_t timestamp_us_mod=(w&0xFFFFu)<<4;
 p=drivehud_append_str(p,e,"NEXTS T0.0.10 T=");
 p=drivehud_append_u32(p,e,track);
 p=drivehud_append_str(p,e," N=");
 p=drivehud_append_u32(p,e,nexts);
 p=drivehud_append_str(p,e," US=");
 p=drivehud_append_u32(p,e,timestamp_us_mod);
 p=drivehud_append_str(p,e,"\r\n");
}else if(type==DRIVEHUD_EVENT_HDRPHY_DIAG){
 uint32_t track=(w>>21)&0x7Fu;
 uint32_t sector=(w>>16)&0x1Fu;
 uint32_t timestamp_us_mod=(w&0xFFFFu)<<4;
 p=drivehud_append_str(p,e,"HDRPHY T0.0.10 T=");
 p=drivehud_append_u32(p,e,track);
 p=drivehud_append_str(p,e," S=");
 p=drivehud_append_u32(p,e,sector);
 p=drivehud_append_str(p,e," US=");
 p=drivehud_append_u32(p,e,timestamp_us_mod);
 p=drivehud_append_str(p,e,"\r\n");
'@

ReplaceOnce $UsbMain `
'(\}else if\(type==DRIVEHUD_EVENT_DENSITY\)\{\s*p=drivehud_append_str\(p,e,"DENSITY state="\);\s*p=drivehud_append_u32\(p,e,w&3u\);\s*p=drivehud_append_str\(p,e,"\\r\\n"\);\s*)\}else\{' `
('$1'+$usbBlock+'}else{') "USB T0.0.10 diagnostic formatter"

Copy-Item $Build031 $Build010 -Force
$b=Get-Content $Build010 -Raw
$b=$b.Replace("V0.0.31","T0.0.10")
$b=$b.Replace("V031","T010")
$b=$b.Replace("1541HUD_OneROM_V0.0.31","1541HUD_OneROM_T0.0.10")
[System.IO.File]::WriteAllText($Build010,$b,(New-Object System.Text.UTF8Encoding($false)))

$probe=Get-Content $T010 -Raw
$usb=Get-Content $UsbMain -Raw
$mk=Get-Content $Makefile -Raw

$checks=@(
 @{ok=($probe -match '0,0,9,0');n="T0.0.10 metadata"},
 @{ok=($probe -match 'RAM_HDRID2\s+0x0016u');n='$0016 observed'},
 @{ok=($probe -match 'RAM_HDRID1\s+0x0017u');n='$0017 observed'},
 @{ok=($probe -match 'RAM_HDRTRK\s+0x0018u');n='$0018 observed'},
 @{ok=($probe -match 'RAM_HDRSEC\s+0x0019u');n='$0019 observed'},
 @{ok=($probe -match 'RAM_HDRCHK\s+0x001Au');n='$001A observed'},
 @{ok=($probe -match 'RAM_NEXTS\s+0x004Du');n='$004D NEXTS observed'},
 @{ok=($probe -match 'queue_nexts_diag');n="NEXTS helper"},
 @{ok=($probe -match 'queue_hdrphy_diag');n="HDRPHY helper"},
 @{ok=($probe -match 'hdr_state\s*=\s*0u');n="header detector state local"},
 @{ok=($usb -match 'NEXTS T0\.0\.10 T=');n="NEXTS USB output"},
 @{ok=($usb -match 'HDRPHY T0\.0\.10 T=');n="HDRPHY USB output"},
 @{ok=($mk -match '1541hud_probe_t010\.c');n="isolated T010 source"},
 @{ok=($probe -match 'queue_track_write\(m,\s*data\)');n="V30 TRACK_WRITE preserved"},
 @{ok=($probe -match 'queue_motor\(m,\s*motor\)');n="V30 MOTOR preserved"},
 @{ok=($probe -match 'queue_phase\(m,\s*oldp,\s*phase,\s*delta,\s*motor\)');n="V30 PHASE preserved"},
 @{ok=($probe -match '\*last_track_write\s*>=\s*1u');n="raw nonzero $0022 NEXTS qualification"}
)
foreach($c in $checks){
 if(-not $c.ok){throw "Sanity failed: $($c.n)"}
 Write-Host " OK: $($c.n)"
}

if($probe -match 'static\s+(?:uint8_t|uint16_t|uint32_t)\s+(?:hdr_|nexts_)'){
 throw "Forbidden T0.0.10 persistent diagnostic .bss state present"
}
Write-Host " OK: no new persistent diagnostic plugin .bss state"

foreach($term in @("DMA10","PIO_SM2","READRAW","READDMA","UC2A_SAMPLE","JOBDIAG","REVCNT","CSECT")){
 if($probe -match [regex]::Escape($term)){throw "Forbidden residue: $term"}
}
if($usb -match 'JOBDIAG|ROTDIAG|READRAW|READDMA|HDRRAM T0\.0\.3|SECTOR T0\.0\.5'){
 throw "Old experimental USB formatter residue remains"
}
Write-Host " OK: noisy/old experiments absent"

Write-Host ""
Write-Host "Building T0.0.10..."
& powershell.exe -ExecutionPolicy Bypass -File $Build010
if($LASTEXITCODE -ne 0){throw "Build failed"}

$dir=Join-Path $Repo "build-1541hud"
$uf2=Join-Path $dir "1541HUD_OneROM_T0.0.10.uf2"
$bin=Join-Path $dir "1541HUD_OneROM_T0.0.10.bin"
if(-not(Test-Path $uf2)){throw "UF2 missing"}
if(-not(Test-Path $bin)){throw "BIN missing"}

Get-FileHash -Algorithm SHA256 $bin,$uf2

Write-Host ""
Write-Host "Preserving exact T0.0.10 source/build..."
& powershell.exe -ExecutionPolicy Bypass -File $Preserve -TestName "T0.0.10_NEXTS_HDRPHY_DIAGNOSTIC"
if($LASTEXITCODE -ne 0){throw "Preservation failed. Do not flash."}

Write-Host ""
Write-Host "T0.0.10 READY"
Write-Host "UF2: $uf2"
Write-Host "Expected diagnostic lines:"
Write-Host '  NEXTS T0.0.10 T=18 N=7 US=...'
Write-Host '  HDRPHY T0.0.10 T=18 S=5 US=...'
Write-Host ""
Write-Host "Test order:"
Write-Host "  1. Cycle v1.5 on tracks 1, 18, 25, 35"
Write-Host "  2. Epyx FastLoad cartridge"
Write-Host "  3. MACH 5 cartridge"
Write-Host ""
Write-Host "No new PIO, DMA channel, wiring, or persistent diagnostic .bss state."
Write-Host "Original V0.0.30/V0.0.31 GUI events remain."
