param(
    [string]$Repo = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
$Baseline = "caf46af18f14cb70bdeb80491f3f7d275b0c6c84"

$ProbeRel      = "plugins/user/1541hud-probe/src/1541hud_probe_v031.c"
$T009Rel       = "plugins/user/1541hud-probe/src/1541hud_probe_t009.c"
$MakefileRel   = "plugins/user/1541hud-probe/Makefile"
$User1541Rel   = "plugins/user/1541hud-probe/src/1541hud_mailbox.h"
$UserCompatRel = "plugins/user/1541hud-probe/src/drivehud_mailbox.h"
$Usb1541Rel    = "plugins/system/usb/include/1541hud_mailbox.h"
$UsbCompatRel  = "plugins/system/usb/include/drivehud_mailbox.h"
$UsbMainRel    = "plugins/system/usb/src/usb_main.c"

$T009       = Join-Path $Repo $T009Rel
$Makefile   = Join-Path $Repo $MakefileRel
$User1541   = Join-Path $Repo $User1541Rel
$UserCompat = Join-Path $Repo $UserCompatRel
$Usb1541    = Join-Path $Repo $Usb1541Rel
$UsbCompat  = Join-Path $Repo $UsbCompatRel
$UsbMain    = Join-Path $Repo $UsbMainRel

$Build031 = Join-Path $Repo "1541hud/Build-1541HUD-V031.ps1"
$Build009 = Join-Path $Repo "1541hud/Build-1541HUD-T009.ps1"
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
$pre = Join-Path $Repo "build-1541hud/T0.0.9_ROTATION_DIAG_PREP_$stamp"
New-Item -ItemType Directory -Force -Path $pre | Out-Null
git -C $Repo status --short | Set-Content -Encoding UTF8 (Join-Path $pre "pre-t009-git-status.txt")
git -C $Repo diff --binary | Set-Content -Encoding UTF8 (Join-Path $pre "pre-t009-working-tree.patch")
git -C $Repo diff --cached --binary | Set-Content -Encoding UTF8 (Join-Path $pre "pre-t009-staged.patch")

function GitShowToFile {
    param([string]$RelPath,[string]$OutPath)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutPath) | Out-Null
    $content = git -C $Repo show "${Baseline}:$RelPath"
    if ($LASTEXITCODE -ne 0) { throw "git show failed: $RelPath" }
    [System.IO.File]::WriteAllText($OutPath,(($content -join "`n")+"`n"),
        (New-Object System.Text.UTF8Encoding($false)))
}

Write-Host "Restoring clean V0.0.31 shared sources..."
GitShowToFile $ProbeRel      $T009
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

ReplaceOnce $T009 `
'ORA_DEFINE_USER_PLUGIN\s*\(\s*drivehud_probe_main\s*,\s*0\s*,\s*0\s*,\s*30\s*,\s*0\s*,\s*0\s*,\s*7\s*,\s*1\s*\)\s*;' `
'ORA_DEFINE_USER_PLUGIN(drivehud_probe_main, 0,0,8,0, 0,7,1);' `
"T0.0.9 metadata"

ReplaceOnce $Makefile `
'PLUGIN_SRC\s*:=\s*src/1541hud_probe_v031\.c' `
'PLUGIN_SRC := src/1541hud_probe_t009.c' `
"Makefile source"

foreach($p in @($User1541,$Usb1541)){
    InsertAfterLine $p '^#define\s+HUD1541_EVENT_DENSITY\s+5u\s*$' `
    '#define HUD1541_EVENT_SECTOR0_QUAL 6u' "sector0-qualified event"
}
foreach($p in @($UserCompat,$UsbCompat)){
    InsertAfterLine $p '^#define\s+DRIVEHUD_EVENT_DENSITY\s+HUD1541_EVENT_DENSITY\s*$' `
    '#define DRIVEHUD_EVENT_SECTOR0_QUAL HUD1541_EVENT_SECTOR0_QUAL' "sector0-qualified alias"
}

foreach($p in @($User1541,$Usb1541)){
    InsertAfterLine $p '^#define\s+HUD1541_EVENT_SECTOR0_QUAL\s+6u\s*$' @'
#define HUD1541_EVENT_ROT_DIAG 7u
#define HUD1541_EVENT_JOB_DIAG 8u
'@ "T0.0.9 rotation diagnostic events"
}
foreach($p in @($UserCompat,$UsbCompat)){
    InsertAfterLine $p '^#define\s+DRIVEHUD_EVENT_SECTOR0_QUAL\s+HUD1541_EVENT_SECTOR0_QUAL\s*$' @'
#define DRIVEHUD_EVENT_ROT_DIAG HUD1541_EVENT_ROT_DIAG
#define DRIVEHUD_EVENT_JOB_DIAG HUD1541_EVENT_JOB_DIAG
'@ "T0.0.9 rotation diagnostic aliases"
}

InsertAfterLine $T009 '^#define\s+RESET_PIO0\s+\(1u\s*<<\s*11\)\s*$' @'
#define TIMER0_BASE 0x400B0000u
#define TIMER0_RAWL (*(volatile uint32_t *)(TIMER0_BASE + 0x28u))
'@ "timer"

InsertAfterLine $T009 '^#define\s+RAM_LWPT\s+0x001Eu\s*$' `
'#define RAM_HDRSEC 0x0019u' '$0019 address'

InsertAfterLine $T009 '^#define\s+RAM_HDRSEC\s+0x0019u\s*$' @'
#define RAM_CSECT  0x004Cu
#define RAM_NEXTS  0x004Du
#define RAM_REVCNT 0x006Au
#define RAM_JOB0   0x0000u
#define RAM_JOB1   0x0001u
#define RAM_JOB2   0x0002u
#define RAM_JOB3   0x0003u
#define RAM_JOB4   0x0004u
#define RAM_JOB5   0x0005u
'@ "T0.0.9 RAM diagnostic addresses"

ReplaceOnce $T009 `
'(static void queue_density\(volatile drivehud_mailbox_t \*m,\s*uint8_t density\)\s*\{\s*queue_event\(m,\s*\(DRIVEHUD_EVENT_DENSITY << 28\)\s*\|\s*\(uint32_t\)\(density & 3u\)\);\s*\})' @'
$1

static void queue_sector0_qual(volatile drivehud_mailbox_t *m,
 uint8_t track) {
 uint32_t ticks16 = (TIMER0_RAWL >> 4) & 0x0000FFFFu;
 queue_event(m,
 (DRIVEHUD_EVENT_SECTOR0_QUAL << 28) |
 ((uint32_t)(track & 0x7Fu) << 21) |
 ticks16);
}


/* T0.0.9 diagnostic packing:
 * ROT_DIAG type 7: bits 25:24 kind, 23:16 value, 15:0 timestamp/16us
 *   kind 0=CSECT($004C), 1=NEXTS($004D), 2=REVCNT($006A)
 * JOB_DIAG type 8: bits 26:24 job index, 23:16 value, 15:0 timestamp/16us
 */
static void queue_rot_diag(volatile drivehud_mailbox_t *m,
 uint8_t kind, uint8_t value) {
 uint32_t ticks16 = (TIMER0_RAWL >> 4) & 0x0000FFFFu;
 queue_event(m,
  (DRIVEHUD_EVENT_ROT_DIAG << 28) |
  ((uint32_t)(kind & 3u) << 24) |
  ((uint32_t)value << 16) | ticks16);
}

static void queue_job_diag(volatile drivehud_mailbox_t *m,
 uint8_t job_index, uint8_t value) {
 uint32_t ticks16 = (TIMER0_RAWL >> 4) & 0x0000FFFFu;
 queue_event(m,
  (DRIVEHUD_EVENT_JOB_DIAG << 28) |
  ((uint32_t)(job_index & 7u) << 24) |
  ((uint32_t)value << 16) | ticks16);
}
'@ "compact sector0-qualified helper"

ReplaceOnce $T009 `
'(\n\s*if\s*\(\s*ram_write_at\(snapshot,\s*RAM_DRVST\)\s*\)\s*\{)' @'

 if (ram_write_at(snapshot, RAM_HDRSEC)) {
 uint8_t sector = logical_data_from_gpio(snapshot);
 if (sector == 0u &&
     *track_write_valid &&
     *last_track_write >= 1u &&
     *last_track_write <= 127u) {
 queue_sector0_qual(m, *last_track_write);
 }
 }

 {
  uint8_t data = logical_data_from_gpio(snapshot);
  if (ram_write_at(snapshot, RAM_CSECT))  queue_rot_diag(m, 0u, data);
  if (ram_write_at(snapshot, RAM_NEXTS))  queue_rot_diag(m, 1u, data);
  if (ram_write_at(snapshot, RAM_REVCNT)) queue_rot_diag(m, 2u, data);
  if (ram_write_at(snapshot, RAM_JOB0)) queue_job_diag(m, 0u, data);
  if (ram_write_at(snapshot, RAM_JOB1)) queue_job_diag(m, 1u, data);
  if (ram_write_at(snapshot, RAM_JOB2)) queue_job_diag(m, 2u, data);
  if (ram_write_at(snapshot, RAM_JOB3)) queue_job_diag(m, 3u, data);
  if (ram_write_at(snapshot, RAM_JOB4)) queue_job_diag(m, 4u, data);
  if (ram_write_at(snapshot, RAM_JOB5)) queue_job_diag(m, 5u, data);
 }
$1
'@ '$0019 Sector-0 observation qualified by raw nonzero $0022'

$usbBlock=@'
}else if(type==DRIVEHUD_EVENT_SECTOR0_QUAL){
 uint32_t track=(w>>21)&0x7Fu;
 uint32_t timestamp_us_mod=(w&0xFFFFu)<<4;
 p=drivehud_append_str(p,e,"SECTOR0 T0.0.9 T=");
 p=drivehud_append_u32(p,e,track);
 p=drivehud_append_str(p,e," US=");
 p=drivehud_append_u32(p,e,timestamp_us_mod);
 p=drivehud_append_str(p,e,"\r\n");
}else if(type==DRIVEHUD_EVENT_ROT_DIAG){
 uint32_t kind=(w>>24)&3u;
 uint32_t value=(w>>16)&0xFFu;
 uint32_t timestamp_us_mod=(w&0xFFFFu)<<4;
 p=drivehud_append_str(p,e,"ROTDIAG T0.0.9 ");
 if(kind==0u) p=drivehud_append_str(p,e,"CSECT=");
 else if(kind==1u) p=drivehud_append_str(p,e,"NEXTS=");
 else if(kind==2u) p=drivehud_append_str(p,e,"REVCNT=");
 else p=drivehud_append_str(p,e,"UNK=");
 p=drivehud_append_u32(p,e,value);
 p=drivehud_append_str(p,e," US=");
 p=drivehud_append_u32(p,e,timestamp_us_mod);
 p=drivehud_append_str(p,e,"\r\n");
}else if(type==DRIVEHUD_EVENT_JOB_DIAG){
 uint32_t job=(w>>24)&7u;
 uint32_t value=(w>>16)&0xFFu;
 uint32_t timestamp_us_mod=(w&0xFFFFu)<<4;
 p=drivehud_append_str(p,e,"JOBDIAG T0.0.9 J=");
 p=drivehud_append_u32(p,e,job);
 p=drivehud_append_str(p,e," V=");
 p=drivehud_append_u32(p,e,value);
 p=drivehud_append_str(p,e," US=");
 p=drivehud_append_u32(p,e,timestamp_us_mod);
 p=drivehud_append_str(p,e,"\r\n");
'@

ReplaceOnce $UsbMain `
'(\}else if\(type==DRIVEHUD_EVENT_DENSITY\)\{\s*p=drivehud_append_str\(p,e,"DENSITY state="\);\s*p=drivehud_append_u32\(p,e,w&3u\);\s*p=drivehud_append_str\(p,e,"\\r\\n"\);\s*)\}else\{' `
('$1'+$usbBlock+'}else{') "USB T0.0.9 rotation diagnostic formatter"

Copy-Item $Build031 $Build009 -Force
$b=Get-Content $Build009 -Raw
$b=$b.Replace("V0.0.31","T0.0.9")
$b=$b.Replace("V031","T009")
$b=$b.Replace("1541HUD_OneROM_V0.0.31","1541HUD_OneROM_T0.0.9")
[System.IO.File]::WriteAllText($Build009,$b,(New-Object System.Text.UTF8Encoding($false)))

$probe=Get-Content $T009 -Raw
$usb=Get-Content $UsbMain -Raw
$mk=Get-Content $Makefile -Raw

$checks=@(
 @{ok=($probe -match '0,0,8,0');n="T0.0.9 metadata"},
 @{ok=($probe -match 'RAM_HDRSEC\s+0x0019u');n='$0019 observed'},
 @{ok=($probe -match 'RAM_CSECT\s+0x004Cu');n='$004C CSECT observed'},
 @{ok=($probe -match 'RAM_NEXTS\s+0x004Du');n='$004D NEXTS observed'},
 @{ok=($probe -match 'RAM_REVCNT\s+0x006Au');n='$006A REVCNT observed'},
 @{ok=($probe -match 'RAM_JOB5\s+0x0005u');n='$0000-$0005 JOBS observed'},
 @{ok=($probe -match 'queue_sector0_qual');n="T008 Sector0 logic preserved"},
 @{ok=($probe -match 'queue_rot_diag');n="rotation diagnostic helper"},
 @{ok=($probe -match 'queue_job_diag');n="job diagnostic helper"},
 @{ok=($usb -match 'SECTOR0 T0\.0\.9 T=');n="Sector0 USB output"},
 @{ok=($usb -match 'ROTDIAG T0\.0\.9');n="rotation diagnostic USB output"},
 @{ok=($usb -match 'JOBDIAG T0\.0\.9');n="job diagnostic USB output"},
 @{ok=($mk -match '1541hud_probe_t009\.c');n="isolated T009 source"},
 @{ok=($probe -match 'queue_track_write\(m,\s*data\)');n="V30 TRACK_WRITE preserved"},
 @{ok=($probe -match 'queue_motor\(m,\s*motor\)');n="V30 MOTOR preserved"},
 @{ok=($probe -match 'queue_phase\(m,\s*oldp,\s*phase,\s*delta,\s*motor\)');n="V30 PHASE preserved"},
 @{ok=($probe -match '\*last_track_write\s*>=\s*1u');n="raw nonzero $0022 Sector0 qualification"},
 @{ok=($probe -match 'sector\s*==\s*0u');n="Sector-0-only filter"}
)
foreach($c in $checks){if(-not $c.ok){throw "Sanity failed: $($c.n)"};Write-Host " OK: $($c.n)"}

if($probe -match 'static\s+(?:uint8_t|uint16_t|uint32_t)\s+(?:sector0_|rot_|job_)'){ throw "Forbidden T0.0.9 persistent diagnostic .bss state present" }
Write-Host " OK: no new persistent diagnostic plugin .bss state"

foreach($term in @("DMA10","PIO_SM2","READRAW","READDMA","UC2A_SAMPLE","RAM_HDRTRK","RAM_HDRCHK","HDRRAM T0.0.3","SECTOR T0.0.5","SECTOR0 T0.0.6")){
    if($probe -match [regex]::Escape($term)){throw "Forbidden residue: $term"}
}
if($usb -match 'READRAW|READDMA|HDRRAM T0\.0\.3|SECTOR0 T0\.0\.4|SECTOR T0\.0\.5|SECTOR0 T0\.0\.6'){
    throw "Old experimental USB formatter residue remains"
}
Write-Host " OK: old experiments absent"

Write-Host ""
Write-Host "Building T0.0.9..."
& powershell.exe -ExecutionPolicy Bypass -File $Build009
if($LASTEXITCODE -ne 0){throw "Build failed"}

$dir=Join-Path $Repo "build-1541hud"
$uf2=Join-Path $dir "1541HUD_OneROM_T0.0.9.uf2"
$bin=Join-Path $dir "1541HUD_OneROM_T0.0.9.bin"
if(-not(Test-Path $uf2)){throw "UF2 missing"}
if(-not(Test-Path $bin)){throw "BIN missing"}

Get-FileHash -Algorithm SHA256 $bin,$uf2

Write-Host ""
Write-Host "Preserving exact T0.0.9 source/build..."
& powershell.exe -ExecutionPolicy Bypass -File $Preserve -TestName "T0.0.9_ROTATION_RAM_DIAGNOSTIC"
if($LASTEXITCODE -ne 0){throw "Preservation failed. Do not flash."}

Write-Host ""
Write-Host "T0.0.9 READY"
Write-Host "UF2: $uf2"
Write-Host "Expected:"
Write-Host "  SECTOR0 T0.0.9 T=18 US=..."
Write-Host '  ROTDIAG T0.0.9 CSECT=... US=...'
Write-Host '  ROTDIAG T0.0.9 NEXTS=... US=...'
Write-Host '  ROTDIAG T0.0.9 REVCNT=... US=...'
Write-Host '  JOBDIAG T0.0.9 J=0 V=... US=...'
Write-Host '  [secondary $0022=0 Sector-0 writes remain suppressed]'
Write-Host ""
Write-Host "Sector0 remains qualified exactly as T0.0.8. Additional diagnostic traffic observes only writes to $004C, $004D, $006A, and $0000-$0005."
Write-Host "Original V0.0.30/V0.0.31 GUI events remain."
