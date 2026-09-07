param(
    [string]$Repo = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
$Baseline = "caf46af18f14cb70bdeb80491f3f7d275b0c6c84"

$ProbeRel      = "plugins/user/1541hud-probe/src/1541hud_probe_v031.c"
$T011Rel       = "plugins/user/1541hud-probe/src/1541hud_probe_t011.c"
$MakefileRel   = "plugins/user/1541hud-probe/Makefile"
$User1541Rel   = "plugins/user/1541hud-probe/src/1541hud_mailbox.h"
$UserCompatRel = "plugins/user/1541hud-probe/src/drivehud_mailbox.h"
$Usb1541Rel    = "plugins/system/usb/include/1541hud_mailbox.h"
$UsbCompatRel  = "plugins/system/usb/include/drivehud_mailbox.h"
$UsbMainRel    = "plugins/system/usb/src/usb_main.c"
$CoreRel       = "1541hud/gui/hud_core_v030.py"
$GuiRel        = "1541hud/gui/1541HUD_T0.0.11_RPM_Test.py"

$T011       = Join-Path $Repo $T011Rel
$Makefile   = Join-Path $Repo $MakefileRel
$User1541   = Join-Path $Repo $User1541Rel
$UserCompat = Join-Path $Repo $UserCompatRel
$Usb1541    = Join-Path $Repo $Usb1541Rel
$UsbCompat  = Join-Path $Repo $UsbCompatRel
$UsbMain    = Join-Path $Repo $UsbMainRel
$Gui        = Join-Path $Repo $GuiRel

$Build031 = Join-Path $Repo "1541hud/Build-1541HUD-V031.ps1"
$Build011 = Join-Path $Repo "1541hud/Build-1541HUD-T011.ps1"
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
$pre = Join-Path $Repo "build-1541hud/T0.0.11_FINAL_RPM_PREP_$stamp"
New-Item -ItemType Directory -Force -Path $pre | Out-Null
git -C $Repo status --short | Set-Content -Encoding UTF8 (Join-Path $pre "pre-t011-git-status.txt")
git -C $Repo diff --binary | Set-Content -Encoding UTF8 (Join-Path $pre "pre-t011-working-tree.patch")
git -C $Repo diff --cached --binary | Set-Content -Encoding UTF8 (Join-Path $pre "pre-t011-staged.patch")

function GitShowToFile {
    param([string]$RelPath,[string]$OutPath)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutPath) | Out-Null
    $content = git -C $Repo show "${Baseline}:$RelPath"
    if ($LASTEXITCODE -ne 0) { throw "git show failed: $RelPath" }
    [System.IO.File]::WriteAllText(
        $OutPath,(($content -join "`n")+"`n"),
        (New-Object System.Text.UTF8Encoding($false))
    )
}

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

Write-Host "Restoring clean V0.0.31 shared sources..."
GitShowToFile $ProbeRel      $T011
GitShowToFile $MakefileRel   $Makefile
GitShowToFile $User1541Rel   $User1541
GitShowToFile $UserCompatRel $UserCompat
GitShowToFile $Usb1541Rel    $Usb1541
GitShowToFile $UsbCompatRel  $UsbCompat
GitShowToFile $UsbMainRel    $UsbMain

ReplaceOnce $T011 `
'ORA_DEFINE_USER_PLUGIN\s*\(\s*drivehud_probe_main\s*,\s*0\s*,\s*0\s*,\s*30\s*,\s*0\s*,\s*0\s*,\s*7\s*,\s*1\s*\)\s*;' `
'ORA_DEFINE_USER_PLUGIN(drivehud_probe_main, 0,0,10,0, 0,7,1);' `
"T0.0.11 metadata"

ReplaceOnce $Makefile `
'PLUGIN_SRC\s*:=\s*src/1541hud_probe_v031\.c' `
'PLUGIN_SRC := src/1541hud_probe_t011.c' `
"Makefile source"

foreach($p in @($User1541,$Usb1541)){
    InsertAfterLine $p '^#define\s+HUD1541_EVENT_DENSITY\s+5u\s*$' @'
#define HUD1541_EVENT_HDRPHY_DIAG 6u
#define HUD1541_EVENT_RPM_DIAG 7u
'@ "T0.0.11 events"
}
foreach($p in @($UserCompat,$UsbCompat)){
    InsertAfterLine $p '^#define\s+DRIVEHUD_EVENT_DENSITY\s+HUD1541_EVENT_DENSITY\s*$' @'
#define DRIVEHUD_EVENT_HDRPHY_DIAG HUD1541_EVENT_HDRPHY_DIAG
#define DRIVEHUD_EVENT_RPM_DIAG HUD1541_EVENT_RPM_DIAG
'@ "T0.0.11 aliases"
}

InsertAfterLine $T011 '^#define\s+RESET_PIO0\s+\(1u\s*<<\s*11\)\s*$' @'
#define TIMER0_BASE 0x400B0000u
#define TIMER0_RAWL (*(volatile uint32_t *)(TIMER0_BASE + 0x28u))
'@ "timer"

InsertAfterLine $T011 '^#define\s+RAM_LWPT\s+0x001Eu\s*$' @'
#define RAM_HDRID2 0x0016u
#define RAM_HDRID1 0x0017u
#define RAM_HDRTRK 0x0018u
#define RAM_HDRSEC 0x0019u
#define RAM_HDRCHK 0x001Au
'@ "physical header RAM addresses"

ReplaceOnce $T011 `
'(static void queue_density\(volatile drivehud_mailbox_t \*m,\s*uint8_t density\)\s*\{\s*queue_event\(m,\s*\(DRIVEHUD_EVENT_DENSITY << 28\)\s*\|\s*\(uint32_t\)\(density & 3u\)\);\s*\})' @'
$1

/* T0.0.11 diagnostic payloads:
 * HDRPHY type 6:
 *   27..21 decoded physical track
 *   20..16 decoded sector
 *   15..0  timestamp / 16 us
 *
 * RPM type 7:
 *   27..21 physical track
 *   20..16 inferred revolution count (1..4)
 *   15..0  RPM * 100
 */
static void queue_hdrphy_diag(volatile drivehud_mailbox_t *m,
 uint8_t track, uint8_t sector, uint16_t ticks16) {
 queue_event(m,
  (DRIVEHUD_EVENT_HDRPHY_DIAG << 28) |
  ((uint32_t)(track & 0x7Fu) << 21) |
  ((uint32_t)(sector & 0x1Fu) << 16) |
  (uint32_t)ticks16);
}

static void queue_rpm_diag(volatile drivehud_mailbox_t *m,
 uint8_t track, uint8_t revolutions, uint16_t rpm100) {
 queue_event(m,
  (DRIVEHUD_EVENT_RPM_DIAG << 28) |
  ((uint32_t)(track & 0x7Fu) << 21) |
  ((uint32_t)(revolutions & 0x1Fu) << 16) |
  (uint32_t)rpm100);
}
'@ "T0.0.11 queue helpers"

ReplaceOnce $T011 `
'(uint8_t\s*\*pos_valid\s*,\s*uint8_t\s*\*current_pos2\s*,\s*uint8_t\s*\*last_drvst\s*,\s*uint8_t\s*\*stepping\s*)\)\s*\{' @'
$1,
 uint8_t *hdr_state, uint8_t *hdr_track, uint8_t *hdr_sector,
 uint16_t *hdr_ticks16,
 volatile uint8_t *rpm_seen, volatile uint16_t *rpm_ticks) {
'@ "decode_snapshot RPM parameters"

# Clear pending RPM samples when spindle turns off.
ReplaceOnce $T011 `
'(\} else if \(motor != \*last_motor\) \{\s*\*last_motor = motor;\s*queue_motor\(m, motor\);\s*)\}' @'
$1
 if (!motor) {
  uint32_t rpm_i;
  for (rpm_i = 0u; rpm_i < 32u; ++rpm_i) rpm_seen[rpm_i] = 0u;
 }
 }
'@ "motor-off RPM reset"

# Clear pending RPM samples on any physical half-step.
ReplaceOnce $T011 `
'(\} else if \(phase != \*last_phase\) \{\s*uint8_t oldp = \*last_phase;\s*uint8_t delta = \(uint8_t\)\(\(phase - oldp\) & 3u\);\s*)\*last_phase = phase;' @'
$1
 {
  uint32_t rpm_i;
  for (rpm_i = 0u; rpm_i < 32u; ++rpm_i) rpm_seen[rpm_i] = 0u;
 }
 *last_phase = phase;
'@ "half-track RPM reset"

ReplaceOnce $T011 `
'(\n\s*if\s*\(\s*ram_write_at\(snapshot,\s*RAM_DRVST\)\s*\)\s*\{)' @'

 /* Actual decoded GCR header signature:
  * physical decode = $18 -> $19 -> $1A -> $17 -> $16
  * pre-search image = $16 -> $17 -> $18 -> $19 -> $1A
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
   uint8_t sec = *hdr_sector;
   uint16_t now = *hdr_ticks16;
   queue_hdrphy_diag(m, *hdr_track, sec, now);

   if (rpm_seen[sec]) {
    uint16_t dt = (uint16_t)(now - rpm_ticks[sec]);

    /* 16 us timer ticks. At 300 RPM one revolution is ~12,500 ticks.
     * Infer 1..4 revolutions by nearest integer multiple, then require
     * the resulting speed to be plausible for a 1541.
     *
     * RPM*100 = 60,000,000*100*revs / (dt*16)
     *         = 375,000,000*revs / dt
     */
    if (dt >= 10000u) {
     uint32_t revs = ((uint32_t)dt + 6250u) / 12500u;
     if (revs >= 1u && revs <= 4u) {
      uint32_t rpm100 =
       ((375000000u * revs) + ((uint32_t)dt / 2u)) / (uint32_t)dt;

      if (rpm100 >= 28000u && rpm100 <= 32000u) {
       queue_rpm_diag(m, *hdr_track, (uint8_t)revs, (uint16_t)rpm100);
      }
     }
    }
   }

   rpm_seen[sec] = 1u;
   rpm_ticks[sec] = now;
  }
  *hdr_state = 0u;
 }
$1
'@ "physical-header RPM estimator"

InsertAfterLine $T011 `
'^\s*uint8_t\s+last_drvst\s*=\s*0u\s*,\s*stepping\s*=\s*0u\s*;\s*$' @'
 uint8_t hdr_state = 0u, hdr_track = 0u, hdr_sector = 0u;
 uint16_t hdr_ticks16 = 0u;
 volatile uint8_t rpm_seen[32];
 volatile uint16_t rpm_ticks[32];
 {
  uint32_t rpm_i;
  for (rpm_i = 0u; rpm_i < 32u; ++rpm_i) {
   rpm_seen[rpm_i] = 0u;
   rpm_ticks[rpm_i] = 0u;
  }
 }
'@ "local RPM state"

ReplaceOnce $T011 `
'(&pos_valid,\s*&current_pos2,\s*&last_drvst,\s*&stepping)\s*\);' @'
&pos_valid, &current_pos2,
 &last_drvst, &stepping,
 &hdr_state, &hdr_track, &hdr_sector, &hdr_ticks16,
 rpm_seen, rpm_ticks);
'@ "decode_snapshot call"

$usbBlock=@'
}else if(type==DRIVEHUD_EVENT_HDRPHY_DIAG){
 uint32_t track=(w>>21)&0x7Fu;
 uint32_t sector=(w>>16)&0x1Fu;
 uint32_t timestamp_us_mod=(w&0xFFFFu)<<4;
 p=drivehud_append_str(p,e,"HDRPHY T0.0.11 T=");
 p=drivehud_append_u32(p,e,track);
 p=drivehud_append_str(p,e," S=");
 p=drivehud_append_u32(p,e,sector);
 p=drivehud_append_str(p,e," US=");
 p=drivehud_append_u32(p,e,timestamp_us_mod);
 p=drivehud_append_str(p,e,"\r\n");
}else if(type==DRIVEHUD_EVENT_RPM_DIAG){
 uint32_t track=(w>>21)&0x7Fu;
 uint32_t revs=(w>>16)&0x1Fu;
 uint32_t rpm100=w&0xFFFFu;
 p=drivehud_append_str(p,e,"RPM T0.0.11 T=");
 p=drivehud_append_u32(p,e,track);
 p=drivehud_append_str(p,e," REV=");
 p=drivehud_append_u32(p,e,revs);
 p=drivehud_append_str(p,e," RPM=");
 p=drivehud_append_u32(p,e,rpm100/100u);
 p=drivehud_append_str(p,e,".");
 if((rpm100%100u)<10u) p=drivehud_append_str(p,e,"0");
 p=drivehud_append_u32(p,e,rpm100%100u);
 p=drivehud_append_str(p,e,"\r\n");
'@

ReplaceOnce $UsbMain `
'(\}else if\(type==DRIVEHUD_EVENT_DENSITY\)\{\s*p=drivehud_append_str\(p,e,"DENSITY state="\);\s*p=drivehud_append_u32\(p,e,w&3u\);\s*p=drivehud_append_str\(p,e,"\\r\\n"\);\s*)\}else\{' `
('$1'+$usbBlock+'}else{') "USB T0.0.11 RPM formatter"

# Separate test GUI. It subclasses the proven V0.0.30 core and adds only RPM.
$guiText = @'
import re
import tkinter as tk
from tkinter import ttk

from hud_core_v030 import DriveHUD as _ProvenDriveHUDCore

rpm_re = re.compile(
    r"RPM\s+T0\.0\.11\s+T=(\d+)\s+REV=(\d+)\s+RPM=(\d+\.\d{2})"
)


class HUD1541RPMTest(_ProvenDriveHUDCore):
    """1541HUD T0.0.11 final RPM validation GUI."""

    def __init__(self, root):
        super().__init__(root)
        self.root.title("1541HUD T0.0.11 - Final RPM Test")
        self.root.geometry("560x520")

        self.rpm_var = tk.StringVar(value="---.--")

        frame = ttk.Frame(self.root)
        frame.pack(fill="x", padx=18, pady=(0, 8))
        ttk.Label(
            frame, text="RPM", font=("Segoe UI", 12, "bold")
        ).pack(side="left", padx=(12, 28))
        ttk.Label(
            frame, textvariable=self.rpm_var,
            font=("Consolas", 22, "bold")
        ).pack(side="left")

    def process_motor(self, state):
        super().process_motor(state)
        if not self.motor_on:
            self.rpm_var.set("---.--")

    def process_line(self, line):
        m = rpm_re.search(line)
        if m:
            if self.motor_on:
                self.rpm_var.set(m.group(3))
            return
        super().process_line(line)


if __name__ == "__main__":
    root = tk.Tk()
    app = HUD1541RPMTest(root)
    root.mainloop()
'@
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Gui) | Out-Null
[System.IO.File]::WriteAllText(
    $Gui,$guiText,(New-Object System.Text.UTF8Encoding($false))
)
Write-Host "Created: $GuiRel"

Copy-Item $Build031 $Build011 -Force
$b=Get-Content $Build011 -Raw
$b=$b.Replace("V0.0.31","T0.0.11")
$b=$b.Replace("V031","T011")
$b=$b.Replace("1541HUD_OneROM_V0.0.31","1541HUD_OneROM_T0.0.11")
[System.IO.File]::WriteAllText($Build011,$b,(New-Object System.Text.UTF8Encoding($false)))

$probe=Get-Content $T011 -Raw
$usb=Get-Content $UsbMain -Raw
$mk=Get-Content $Makefile -Raw
$guiCheck=Get-Content $Gui -Raw

$checks=@(
 @{ok=($probe -match '0,0,10,0');n="T0.0.11 metadata"},
 @{ok=($probe -match 'RAM_HDRID2\s+0x0016u');n='$0016 observed'},
 @{ok=($probe -match 'RAM_HDRID1\s+0x0017u');n='$0017 observed'},
 @{ok=($probe -match 'RAM_HDRTRK\s+0x0018u');n='$0018 observed'},
 @{ok=($probe -match 'RAM_HDRSEC\s+0x0019u');n='$0019 observed'},
 @{ok=($probe -match 'RAM_HDRCHK\s+0x001Au');n='$001A observed'},
 @{ok=($probe -match 'queue_hdrphy_diag');n="HDRPHY helper"},
 @{ok=($probe -match 'queue_rpm_diag');n="RPM helper"},
 @{ok=($probe -match '375000000u');n="RPM hundredth calculation"},
 @{ok=($probe -notmatch '\bmemset\b');n="no libc memset dependency"},
 @{ok=($probe -match 'volatile\s+uint8_t\s+rpm_seen\[32\]');n="RPM history local"},
 @{ok=($usb -match 'RPM T0\.0\.11 T=');n="RPM USB output"},
 @{ok=($usb -match 'rpm100/100u');n="hundredth formatter"},
 @{ok=($mk -match '1541hud_probe_t011\.c');n="isolated T011 source"},
 @{ok=($probe -match 'queue_track_write\(m,\s*data\)');n="TRACK_WRITE preserved"},
 @{ok=($probe -match 'queue_motor\(m,\s*motor\)');n="MOTOR preserved"},
 @{ok=($probe -match 'queue_phase\(m,\s*oldp,\s*phase,\s*delta,\s*motor\)');n="PHASE preserved"},
 @{ok=($probe -match 'queue_density\(m,\s*density\)');n="DENSITY preserved"},
 @{ok=($probe -match 'queue_write_protect\(m,\s*[A-Za-z_][A-Za-z0-9_]*\)');n="WRITE_PROTECT preserved"},
 @{ok=($guiCheck -match 'from hud_core_v030 import');n="proven GUI core reused"},
 @{ok=($guiCheck -match '---\.\--|---\.\--');n="RPM blanking placeholder"}
)
foreach($c in $checks){
 if(-not $c.ok){throw "Sanity failed: $($c.n)"}
 Write-Host " OK: $($c.n)"
}

if($probe -match 'static\s+(?:uint8_t|uint16_t|uint32_t)\s+(?:hdr_|rpm_)'){
 throw "Forbidden persistent T0.0.11 diagnostic .bss state present"
}
Write-Host " OK: no new persistent diagnostic plugin .bss state"

foreach($term in @("DMA10","PIO_SM2","READRAW","READDMA","UC2A_SAMPLE","JOBDIAG","REVCNT","CSECT")){
 if($probe -match [regex]::Escape($term)){throw "Forbidden residue: $term"}
}
Write-Host " OK: abandoned/noisy experiments absent"

Write-Host ""
Write-Host "Building T0.0.11..."
& powershell.exe -ExecutionPolicy Bypass -File $Build011
if($LASTEXITCODE -ne 0){throw "Build failed"}

$dir=Join-Path $Repo "build-1541hud"
$uf2=Join-Path $dir "1541HUD_OneROM_T0.0.11.uf2"
$bin=Join-Path $dir "1541HUD_OneROM_T0.0.11.bin"
if(-not(Test-Path $uf2)){throw "UF2 missing"}
if(-not(Test-Path $bin)){throw "BIN missing"}

Get-FileHash -Algorithm SHA256 $bin,$uf2

Write-Host ""
Write-Host "Preserving exact T0.0.11 source/build..."
& powershell.exe -ExecutionPolicy Bypass -File $Preserve -TestName "T0.0.11_FINAL_RPM_GUI_TEST"
if($LASTEXITCODE -ne 0){throw "Preservation failed. Do not flash."}

Write-Host ""
Write-Host "T0.0.11 FINAL RPM TEST READY"
Write-Host "UF2: $uf2"
Write-Host "GUI: $Gui"
Write-Host ""
Write-Host "Expected RPM line:"
Write-Host "  RPM T0.0.11 T=18 REV=2 RPM=300.43"
Write-Host ""
Write-Host "Run GUI with:"
Write-Host "  python .\1541hud\gui\1541HUD_T0.0.11_RPM_Test.py"
Write-Host ""
Write-Host "RPM precision: 0.01 RPM."
Write-Host "Motor OFF blanks RPM. Head movement clears pending measurements."
Write-Host "No new PIO, DMA channel, wiring, or persistent diagnostic .bss state."
