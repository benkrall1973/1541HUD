param(
    [string]$Repo = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
$Baseline = "caf46af18f14cb70bdeb80491f3f7d275b0c6c84"

$ProbeRel      = "plugins/user/1541hud-probe/src/1541hud_probe_v031.c"
$T005Rel       = "plugins/user/1541hud-probe/src/1541hud_probe_t005.c"
$MakefileRel   = "plugins/user/1541hud-probe/Makefile"
$User1541Rel   = "plugins/user/1541hud-probe/src/1541hud_mailbox.h"
$UserCompatRel = "plugins/user/1541hud-probe/src/drivehud_mailbox.h"
$Usb1541Rel    = "plugins/system/usb/include/1541hud_mailbox.h"
$UsbCompatRel  = "plugins/system/usb/include/drivehud_mailbox.h"
$UsbMainRel    = "plugins/system/usb/src/usb_main.c"

$T005       = Join-Path $Repo $T005Rel
$Makefile   = Join-Path $Repo $MakefileRel
$User1541   = Join-Path $Repo $User1541Rel
$UserCompat = Join-Path $Repo $UserCompatRel
$Usb1541    = Join-Path $Repo $Usb1541Rel
$UsbCompat  = Join-Path $Repo $UsbCompatRel
$UsbMain    = Join-Path $Repo $UsbMainRel

$Build031 = Join-Path $Repo "1541hud/Build-1541HUD-V031.ps1"
$Build005 = Join-Path $Repo "1541hud/Build-1541HUD-T005.ps1"
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
$pre = Join-Path $Repo "build-1541hud/T0.0.5_SECTOR_STREAM_PREP_$stamp"
New-Item -ItemType Directory -Force -Path $pre | Out-Null
git -C $Repo status --short | Set-Content -Encoding UTF8 (Join-Path $pre "pre-t005-git-status.txt")
git -C $Repo diff --binary | Set-Content -Encoding UTF8 (Join-Path $pre "pre-t005-working-tree.patch")
git -C $Repo diff --cached --binary | Set-Content -Encoding UTF8 (Join-Path $pre "pre-t005-staged.patch")

function GitShowToFile {
    param([string]$RelPath,[string]$OutPath)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutPath) | Out-Null
    $content = git -C $Repo show "${Baseline}:$RelPath"
    if ($LASTEXITCODE -ne 0) { throw "git show failed: $RelPath" }
    [System.IO.File]::WriteAllText($OutPath,(($content -join "`n")+"`n"),
        (New-Object System.Text.UTF8Encoding($false)))
}

Write-Host "Restoring clean V0.0.31 shared sources..."
GitShowToFile $ProbeRel      $T005
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

ReplaceOnce $T005 `
'ORA_DEFINE_USER_PLUGIN\s*\(\s*drivehud_probe_main\s*,\s*0\s*,\s*0\s*,\s*30\s*,\s*0\s*,\s*0\s*,\s*7\s*,\s*1\s*\)\s*;' `
'ORA_DEFINE_USER_PLUGIN(drivehud_probe_main, 0,0,5,0, 0,7,1);' `
"T0.0.5 metadata"

ReplaceOnce $Makefile `
'PLUGIN_SRC\s*:=\s*src/1541hud_probe_v031\.c' `
'PLUGIN_SRC := src/1541hud_probe_t005.c' `
"Makefile source"

foreach($p in @($User1541,$Usb1541)){
    InsertAfterLine $p '^#define\s+HUD1541_EVENT_DENSITY\s+5u\s*$' `
    '#define HUD1541_EVENT_SECTOR_STREAM 6u' "sector-stream event"
}
foreach($p in @($UserCompat,$UsbCompat)){
    InsertAfterLine $p '^#define\s+DRIVEHUD_EVENT_DENSITY\s+HUD1541_EVENT_DENSITY\s*$' `
    '#define DRIVEHUD_EVENT_SECTOR_STREAM HUD1541_EVENT_SECTOR_STREAM' "sector-stream alias"
}

InsertAfterLine $T005 '^#define\s+RESET_PIO0\s+\(1u\s*<<\s*11\)\s*$' @'
#define TIMER0_BASE 0x400B0000u
#define TIMER0_RAWL (*(volatile uint32_t *)(TIMER0_BASE + 0x28u))
'@ "timer"

InsertAfterLine $T005 '^#define\s+RAM_LWPT\s+0x001Eu\s*$' `
'#define RAM_HDRSEC 0x0019u' '$0019 address'

ReplaceOnce $T005 `
'(static void queue_density\(volatile drivehud_mailbox_t \*m,\s*uint8_t density\)\s*\{\s*queue_event\(m,\s*\(DRIVEHUD_EVENT_DENSITY << 28\)\s*\|\s*\(uint32_t\)\(density & 3u\)\);\s*\})' @'
$1

static void queue_sector_stream(volatile drivehud_mailbox_t *m,
 uint8_t track, uint8_t sector) {
 uint32_t ticks16 = (TIMER0_RAWL >> 4) & 0x0003FFFFu;
 queue_event(m,
 (DRIVEHUD_EVENT_SECTOR_STREAM << 28) |
 ((uint32_t)(track & 0x7Fu) << 21) |
 ((uint32_t)(sector & 0x1Fu) << 16) |
 ticks16);
}
'@ "compact sector-stream helper"

ReplaceOnce $T005 `
'(\n\s*if\s*\(\s*ram_write_at\(snapshot,\s*RAM_DRVST\)\s*\)\s*\{)' @'

 if (ram_write_at(snapshot, RAM_HDRSEC)) {
 uint8_t sector = logical_data_from_gpio(snapshot);
 uint8_t track = (*track_write_valid &&
                  *last_track_write >= 1u &&
                  *last_track_write <= 127u)
                   ? *last_track_write : 0u;
 queue_sector_stream(m, track, sector);
 }
$1
'@ '$0019 all-sector observation'

$usbBlock=@'
}else if(type==DRIVEHUD_EVENT_SECTOR_STREAM){
 uint32_t track=(w>>21)&0x7Fu;
 uint32_t sector=(w>>16)&0x1Fu;
 uint32_t timestamp_us_mod=(w&0xFFFFu)<<4;
 p=drivehud_append_str(p,e,"SECTOR T0.0.5 T=");
 p=drivehud_append_u32(p,e,track);
 p=drivehud_append_str(p,e," S=");
 p=drivehud_append_u32(p,e,sector);
 p=drivehud_append_str(p,e," US=");
 p=drivehud_append_u32(p,e,timestamp_us_mod);
 if(sector==0u)p=drivehud_append_str(p,e," ZERO");
 p=drivehud_append_str(p,e,"\r\n");
'@

ReplaceOnce $UsbMain `
'(\}else if\(type==DRIVEHUD_EVENT_DENSITY\)\{\s*p=drivehud_append_str\(p,e,"DENSITY state="\);\s*p=drivehud_append_u32\(p,e,w&3u\);\s*p=drivehud_append_str\(p,e,"\\r\\n"\);\s*)\}else\{' `
('$1'+$usbBlock+'}else{') "USB sector formatter"

Copy-Item $Build031 $Build005 -Force
$b=Get-Content $Build005 -Raw
$b=$b.Replace("V0.0.31","T0.0.5")
$b=$b.Replace("V031","T005")
$b=$b.Replace("1541HUD_OneROM_V0.0.31","1541HUD_OneROM_T0.0.5")
[System.IO.File]::WriteAllText($Build005,$b,(New-Object System.Text.UTF8Encoding($false)))

$probe=Get-Content $T005 -Raw
$usb=Get-Content $UsbMain -Raw
$mk=Get-Content $Makefile -Raw

$checks=@(
 @{ok=($probe -match '0,0,5,0');n="T0.0.5 metadata"},
 @{ok=($probe -match 'RAM_HDRSEC\s+0x0019u');n='$0019 only'},
 @{ok=($probe -match 'queue_sector_stream');n="sector stream helper"},
 @{ok=($usb -match 'SECTOR T0\.0\.5 T=');n="USB output"},
 @{ok=($mk -match '1541hud_probe_t005\.c');n="isolated source"},
 @{ok=($probe -match 'queue_track_write\(m,\s*data\)');n="V30 TRACK_WRITE preserved"},
 @{ok=($probe -match 'queue_motor\(m,\s*motor\)');n="V30 MOTOR preserved"},
 @{ok=($probe -match 'queue_phase\(m,\s*oldp,\s*phase,\s*delta,\s*motor\)');n="V30 PHASE preserved"}
)
foreach($c in $checks){if(-not $c.ok){throw "Sanity failed: $($c.n)"};Write-Host " OK: $($c.n)"}

foreach($term in @("DMA10","PIO_SM2","READRAW","READDMA","UC2A_SAMPLE","RAM_HDRTRK","RAM_HDRCHK","HDRRAM T0.0.3")){
    if($probe -match [regex]::Escape($term)){throw "Forbidden residue: $term"}
}
if($usb -match 'READRAW|READDMA|HDRRAM T0\.0\.3|SECTOR0 T0\.0\.4'){
    throw "Old experimental USB formatter residue remains"
}
Write-Host " OK: old experiments absent"

Write-Host ""
Write-Host "Building T0.0.5..."
& powershell.exe -ExecutionPolicy Bypass -File $Build005
if($LASTEXITCODE -ne 0){throw "Build failed"}

$dir=Join-Path $Repo "build-1541hud"
$uf2=Join-Path $dir "1541HUD_OneROM_T0.0.5.uf2"
$bin=Join-Path $dir "1541HUD_OneROM_T0.0.5.bin"
if(-not(Test-Path $uf2)){throw "UF2 missing"}
if(-not(Test-Path $bin)){throw "BIN missing"}

Get-FileHash -Algorithm SHA256 $bin,$uf2

Write-Host ""
Write-Host "Preserving exact T0.0.5 source/build..."
& powershell.exe -ExecutionPolicy Bypass -File $Preserve -TestName "T0.0.5_SECTOR_STREAM"
if($LASTEXITCODE -ne 0){throw "Preservation failed. Do not flash."}

Write-Host ""
Write-Host "T0.0.5 READY"
Write-Host "UF2: $uf2"
Write-Host "Expected:"
Write-Host "  SECTOR T0.0.5 T=18 S=9 US=..."
Write-Host "  SECTOR T0.0.5 T=18 S=0 US=... ZERO"
Write-Host ""
Write-Host "Only $0019 produces new diagnostic traffic."
Write-Host "Original V0.0.30/V0.0.31 GUI events remain."
