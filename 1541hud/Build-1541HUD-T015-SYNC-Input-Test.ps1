param(
    [string]$Repo = "",
    [string]$OneRomCli = "",
    [string]$Toolchain = "/usr/bin",
    [string]$Picotool = "/opt/picotool/build/picotool"
)

$ErrorActionPreference = "Stop"

function Get-WslPath {
    param([Parameter(Mandatory=$true)][string]$WindowsPath)
    $path = $WindowsPath -replace '^Microsoft\.PowerShell\.Core\\FileSystem::',''
    if ($path -match '^\\\\wsl(?:\$|\.localhost)\\[^\\]+\\(.*)$') {
        $rest = $Matches[1] -replace '\\','/'
        return "/" + $rest.TrimStart("/")
    }
    $full = [System.IO.Path]::GetFullPath($path)
    if ($full -match '^([A-Za-z]):[\\/](.*)$') {
        $drive = $Matches[1].ToLowerInvariant()
        $rest = $Matches[2] -replace '\\','/'
        return "/mnt/$drive/$rest"
    }
    throw "Could not convert Windows or WSL path to WSL path: $WindowsPath"
}

function Quote-Bash {
    param([Parameter(Mandatory=$true)][string]$Text)
    return "'" + ($Text -replace "'", "'""'""'") + "'"
}

Write-Host ""
Write-Host "1541HUD T0.0.15 - physical SYNC input diagnostic"
Write-Host ""
Write-Host "WIRING: UC2 pin 17 PB7/SYNC -> former CS1 wire -> OneROM GPIO24"
Write-Host "TEST: GPIO24 is input-only. Count falling SYNC edges and report once per second."
Write-Host ""

if ([string]::IsNullOrWhiteSpace($Repo)) {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $candidate = Join-Path $projectRoot "OneROM"
    if ((Test-Path -LiteralPath (Join-Path $candidate "firmware\ora\plugin.mk")) -and
        (Test-Path -LiteralPath (Join-Path $candidate "plugins"))) {
        $Repo = (Resolve-Path -LiteralPath $candidate).Path
    }
}
if ([string]::IsNullOrWhiteSpace($Repo)) { throw "Could not locate OneROM repository. Use -Repo." }
$Repo = (Resolve-Path -LiteralPath $Repo).Path

if ([string]::IsNullOrWhiteSpace($OneRomCli)) {
    if ($env:ONEROM_CLI -and (Test-Path -LiteralPath $env:ONEROM_CLI)) {
        $OneRomCli = (Resolve-Path -LiteralPath $env:ONEROM_CLI).Path
    } else {
        $cmd = Get-Command onerom.exe -ErrorAction SilentlyContinue
        if ($cmd) {
            $OneRomCli = $cmd.Source
        } else {
            $desktop = Join-Path $HOME "Desktop"
            if (Test-Path -LiteralPath $desktop) {
                $matches = Get-ChildItem -LiteralPath $desktop -Directory -Filter "onerom-cli-win-*" -ErrorAction SilentlyContinue | Sort-Object Name -Descending
                foreach ($folder in $matches) {
                    $candidate = Join-Path $folder.FullName "onerom.exe"
                    if (Test-Path -LiteralPath $candidate) {
                        $OneRomCli = (Resolve-Path -LiteralPath $candidate).Path
                        break
                    }
                }
            }
        }
    }
}
if ([string]::IsNullOrWhiteSpace($OneRomCli)) { throw "Could not locate onerom.exe. Use -OneRomCli or ONEROM_CLI." }

$Repo = $Repo -replace '^Microsoft\.PowerShell\.Core\\FileSystem::',''
$RepoWsl = Get-WslPath $Repo
$RepoQ = Quote-Bash $RepoWsl
$ToolchainQ = Quote-Bash $Toolchain

$PluginDir = Join-Path $Repo "plugins\user\1541hud-probe"
$BaseSource = Join-Path $PluginDir "src\1541hud_probe_t011.c"
$TestSource = Join-Path $PluginDir "src\1541hud_probe_t015_sync.c"
$UsbDir = Join-Path $Repo "plugins\system\usb"
$UsbBase = Join-Path $UsbDir "src\usb_main.c"
$UsbTest = Join-Path $UsbDir "src\usb_main_t015_sync.c"
$BuildDir = Join-Path $Repo "build-1541hud"
$OutBase = Join-Path $BuildDir "1541HUD_OneROM_T0.0.15_SYNC_Input_Test"
$PreservedSource = Join-Path $BuildDir "1541hud_probe_t015_sync_SOURCE.c"
$PreservedUsb = Join-Path $BuildDir "usb_main_t015_sync_SOURCE.c"
$Companion = Join-Path $BuildDir "1541hud_companion_8k.bin"

foreach ($required in @($BaseSource,$UsbBase)) {
    if (!(Test-Path -LiteralPath $required)) { throw "Required canonical source missing: $required" }
}
New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null

# Generate T0.0.15 from the hardware-proven T0.0.11 source.
$src = [System.IO.File]::ReadAllText($BaseSource)

$old = @'
#define TIMER0_BASE 0x400B0000u
#define TIMER0_RAWL (*(volatile uint32_t *)(TIMER0_BASE + 0x28u))
'@
$new = @'
#define TIMER0_BASE 0x400B0000u
#define TIMER0_RAWL (*(volatile uint32_t *)(TIMER0_BASE + 0x28u))

/* T0.0.15: former CS1 GPIO24 is now a passive physical SYNC input. */
#define SIO_BASE 0xD0000000u
#define SIO_GPIO_IN (*(volatile uint32_t *)(SIO_BASE + 0x004u))
#define MASK_SYNC (1u << 24)
#define DRIVEHUD_EVENT_SYNC_DIAG 8u
'@
if (!$src.Contains($old)) { throw "Expected TIMER0 block not found." }
$src = $src.Replace($old,$new)

$old = @'
#define MASK_CS1 (1u << 24)
#define MASK_nCS2 (1u << 25)
'@
$new = @'
/* T0.0.15: GPIO24 is SYNC, so UC2 decode uses /CS2 only. */
#define MASK_nCS2 (1u << 25)
'@
if (!$src.Contains($old)) { throw "Expected CS1 mask block not found." }
$src = $src.Replace($old,$new)

$old = @'
static uint8_t uc2_selected(uint32_t v) {
 return (uint8_t)(((v & MASK_CS1) != 0u) && ((v & MASK_nCS2) == 0u));
}
'@
$new = @'
static uint8_t uc2_selected(uint32_t v) {
 /* Hardware-proven T0.0.14 result: CS1 is not required for current decode. */
 return (uint8_t)((v & MASK_nCS2) == 0u);
}
'@
if (!$src.Contains($old)) { throw "Expected uc2_selected block not found." }
$src = $src.Replace($old,$new)

$anchor = @'
static void publish_track_state(volatile drivehud_mailbox_t *m,
'@
$insert = @'
/* Count one event per asserted SYNC pulse by watching the high->low edge.
 * Report the raw edge count once per second. This first test intentionally
 * does not alter the proven HDRPHY/RPM algorithm.
 */
static void sync_poll(volatile drivehud_mailbox_t *m,
 uint8_t *last_level, uint32_t *count, uint32_t *next_report_us) {
 uint8_t level = (SIO_GPIO_IN & MASK_SYNC) ? 1u : 0u;
 uint32_t now = TIMER0_RAWL;

 if (*last_level && !level) (*count)++;
 *last_level = level;

 if ((int32_t)(now - *next_report_us) >= 0) {
  uint32_t packed = (DRIVEHUD_EVENT_SYNC_DIAG << 28) |
                    ((uint32_t)(level & 1u) << 27) |
                    (*count & 0x07FFFFFFu);
  queue_event(m, packed);
  *count = 0u;
  *next_report_us = now + 1000000u;
 }
}

static void publish_track_state(volatile drivehud_mailbox_t *m,
'@
if (!$src.Contains($anchor)) { throw "publish_track_state anchor not found." }
$src = $src.Replace($anchor,$insert)

$old = @'
 uint8_t last_drvst = 0u, stepping = 0u;

 /* Physical-header/RPM state is deliberately local to the plugin main
'@
$new = @'
 uint8_t last_drvst = 0u, stepping = 0u;
 uint8_t sync_last_level = (SIO_GPIO_IN & MASK_SYNC) ? 1u : 0u;
 uint32_t sync_count = 0u;
 uint32_t sync_next_report_us = TIMER0_RAWL + 1000000u;

 /* Physical-header/RPM state is deliberately local to the plugin main
'@
if (!$src.Contains($old)) { throw "Main local-state anchor not found." }
$src = $src.Replace($old,$new)

$old = @'
 while (1) {
 produced_total = dma_update_producer(produced_total, &last_remaining);
'@
$new = @'
 while (1) {
 sync_poll(m, &sync_last_level, &sync_count, &sync_next_report_us);
 produced_total = dma_update_producer(produced_total, &last_remaining);
'@
if (!$src.Contains($old)) { throw "Outer loop anchor not found." }
$src = $src.Replace($old,$new)

$old = @'
 while (consumer_total != produced_total) {
 uint32_t idx = consumer_total & (DRIVEHUD_RING_WORDS - 1u);
'@
$new = @'
 while (consumer_total != produced_total) {
 sync_poll(m, &sync_last_level, &sync_count, &sync_next_report_us);
 uint32_t idx = consumer_total & (DRIVEHUD_RING_WORDS - 1u);
'@
if (!$src.Contains($old)) { throw "Inner loop anchor not found." }
$src = $src.Replace($old,$new)

$banner = "/* 1541HUD T0.0.15 PHYSICAL SYNC INPUT TEST - generated from T0.0.11 canonical source. */`r`n"
[System.IO.File]::WriteAllText($TestSource,$banner+$src,[System.Text.UTF8Encoding]::new($false))
Copy-Item -LiteralPath $TestSource -Destination $PreservedSource -Force

# Generate a test-only USB formatter. Canonical usb_main.c remains untouched.
$usb = [System.IO.File]::ReadAllText($UsbBase)
$old = @'
#include "drivehud_mailbox.h"
'@
$new = @'
#include "drivehud_mailbox.h"
#define DRIVEHUD_EVENT_SYNC_DIAG 8u
'@
if (!$usb.Contains($old)) { throw "USB include anchor not found." }
$usb = $usb.Replace($old,$new)

$old = @'
 p=drivehud_append_u32(p,e,rpm100%100u);
 p=drivehud_append_str(p,e,"\r\n");}else{
'@
$new = @'
 p=drivehud_append_u32(p,e,rpm100%100u);
 p=drivehud_append_str(p,e,"\r\n");
 }else if(type==DRIVEHUD_EVENT_SYNC_DIAG){
 uint32_t level=(w>>27)&1u;
 uint32_t count=w&0x07FFFFFFu;
 p=drivehud_append_str(p,e,"SYNC T0.0.15 COUNT=");
 p=drivehud_append_u32(p,e,count);
 p=drivehud_append_str(p,e," LEVEL=");
 p=drivehud_append_u32(p,e,level);
 p=drivehud_append_str(p,e,"\r\n");
 }else{
'@
if (!$usb.Contains($old)) { throw "USB RPM tail anchor not found." }
$usb = $usb.Replace($old,$new)
[System.IO.File]::WriteAllText($UsbTest,$usb,[System.Text.UTF8Encoding]::new($false))
Copy-Item -LiteralPath $UsbTest -Destination $PreservedUsb -Force

Write-Host "Generated/preserved T0.0.15 sources:"
Get-FileHash $PreservedSource,$PreservedUsb -Algorithm SHA256

Write-Host "Creating passive 8K FF companion ROM..."
[byte[]]$bytes = New-Object byte[] 8192
for ($i=0;$i -lt $bytes.Length;$i++){ $bytes[$i]=0xFF }
[System.IO.File]::WriteAllBytes($Companion,$bytes)

Write-Host "Building passive OneROM base firmware..."
$baseBuild = "cd $RepoQ && make firmware TOOLCHAIN=$ToolchainQ EXTRA_C_FLAGS=-DHUD1541_PASSIVE_UB4"
& wsl bash -lc $baseBuild
if ($LASTEXITCODE -ne 0) { throw "Passive OneROM base firmware build failed" }

Write-Host "Building T0.0.15 SYNC USER plugin..."
$userBuild = "cd $RepoQ && make -C plugins/user/1541hud-probe clean && make -C plugins/user/1541hud-probe TOOLCHAIN=$ToolchainQ PLUGIN_SRC=src/1541hud_probe_t015_sync.c"
& wsl bash -lc $userBuild
if ($LASTEXITCODE -ne 0) { throw "T0.0.15 USER plugin build failed" }

Write-Host "Building T0.0.15 test USB SYSTEM plugin..."
$usbSrc = "src/usb_descriptors.c src/usb_picobootx.c src/usb_rom.c src/usb_led.c src/usb_gpio.c src/usb_main_t015_sync.c"
$usbBuild = "cd $RepoQ && make -C plugins/system/usb clean && make -C plugins/system/usb TOOLCHAIN=$ToolchainQ SRC=\"$usbSrc\""
& wsl bash -lc $usbBuild
if ($LASTEXITCODE -ne 0) { throw "T0.0.15 USB SYSTEM plugin build failed" }

$baseFirmware = Join-Path $Repo "firmware\build\onerom-rp235x.bin"
$userPlugin = Join-Path $Repo "plugins\user\1541hud-probe\build\plugin_user.bin"
$systemPlugin = Join-Path $Repo "plugins\system\usb\build\usb_system_plugin.bin"
foreach ($artifact in @($baseFirmware,$userPlugin,$systemPlugin)) {
    if (!(Test-Path -LiteralPath $artifact)) { throw "Required build artifact missing: $artifact" }
}

Write-Host "Composing Fire-24-E T0.0.15 test firmware..."
& $OneRomCli firmware build `
    --board fire-24-e `
    --base-firmware $baseFirmware `
    --slot "file=$Companion,type=2364,cs1=active-low" `
    --plugin "file=$systemPlugin" `
    --plugin "file=$userPlugin" `
    --out "$OutBase.bin"
if ($LASTEXITCODE -ne 0) { throw "OneROM firmware composition failed" }

$OutBinWsl = Get-WslPath "$OutBase.bin"
$OutUf2Wsl = Get-WslPath "$OutBase.uf2"
Write-Host "Converting BIN to UF2..."
$uf2Command = (Quote-Bash $Picotool) + " uf2 convert " + (Quote-Bash $OutBinWsl) + " " + (Quote-Bash $OutUf2Wsl)
& wsl bash -lc $uf2Command
if ($LASTEXITCODE -ne 0) { throw "UF2 conversion failed" }

Write-Host ""
Write-Host "Build complete."
Write-Host "Expected telemetry: SYNC T0.0.15 COUNT=<falling edges in last second> LEVEL=<0|1>"
Write-Host "UF2: $OutBase.uf2"
Get-Item "$OutBase.bin","$OutBase.uf2",$PreservedSource,$PreservedUsb | Format-Table Name,Length,LastWriteTime
Write-Host "SHA256:"
Get-FileHash "$OutBase.bin","$OutBase.uf2",$PreservedSource,$PreservedUsb -Algorithm SHA256
