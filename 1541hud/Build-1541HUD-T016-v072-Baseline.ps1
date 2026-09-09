param(
    [string]$Repo = "",
    [string]$OneRomCli = "",
    [string]$Toolchain = "/opt/arm-gnu-toolchain-15.3.rel1/bin",
    [string]$Picotool = "/opt/picotool/build/picotool"
)
$ErrorActionPreference = "Stop"
function Get-WslPath { param([Parameter(Mandatory=$true)][string]$WindowsPath)
    $path = $WindowsPath -replace '^Microsoft\.PowerShell\.Core\\FileSystem::',''
    if ($path -match '^\\\\wsl(?:\$|\.localhost)\\[^\\]+\\(.*)$') { return "/" + (($Matches[1] -replace '\\','/').TrimStart('/')) }
    $full=[System.IO.Path]::GetFullPath($path)
    if ($full -match '^([A-Za-z]):[\\/](.*)$') { return "/mnt/"+$Matches[1].ToLowerInvariant()+"/"+($Matches[2]-replace '\\','/') }
    throw "Could not convert path to WSL path: $WindowsPath"
}
function Quote-Bash { param([Parameter(Mandatory=$true)][string]$Text) return ([char]39)+$Text+([char]39) }

if ([string]::IsNullOrWhiteSpace($Repo)) {
    $projectRoot=Split-Path -Parent $PSScriptRoot
    $candidate=Join-Path $projectRoot "OneROM"
    if (Test-Path -LiteralPath (Join-Path $candidate "firmware\ora\plugin.mk")) { $Repo=(Resolve-Path -LiteralPath $candidate).Path }
}
if ([string]::IsNullOrWhiteSpace($Repo)) { throw "Could not locate OneROM repository. Use -Repo." }
$Repo=(Resolve-Path -LiteralPath $Repo).Path
if ([string]::IsNullOrWhiteSpace($OneRomCli)) {
    if ($env:ONEROM_CLI -and (Test-Path -LiteralPath $env:ONEROM_CLI)) { $OneRomCli=(Resolve-Path -LiteralPath $env:ONEROM_CLI).Path }
    else { $cmd=Get-Command onerom.exe -ErrorAction SilentlyContinue; if ($cmd) { $OneRomCli=$cmd.Source } }
}
if ([string]::IsNullOrWhiteSpace($OneRomCli)) { throw "Could not locate onerom.exe. Use -OneRomCli or ONEROM_CLI." }

$RepoWsl=Get-WslPath $Repo; $RepoQ=Quote-Bash $RepoWsl; $ToolchainQ=Quote-Bash $Toolchain
$PluginDir=Join-Path $Repo "plugins\user\1541hud-probe"
$UsbDir=Join-Path $Repo "plugins\system\usb"
$BuildDir=Join-Path $Repo "build-1541hud"
$PluginSource=Join-Path $PluginDir "src\1541hud_probe_t016_v072_baseline.c"
$UsbSource=Join-Path $UsbDir "src\usb_main_t016_1541hud_baseline.c"
$Companion=Join-Path $BuildDir "1541hud_companion_8k.bin"
$OutBase=Join-Path $BuildDir "1541HUD_OneROM_T0.0.16_v0.7.2_Baseline"
$PreservedPlugin=Join-Path $BuildDir "1541hud_probe_t016_v072_baseline_SOURCE.c"
$PreservedUsb=Join-Path $BuildDir "usb_main_t016_1541hud_baseline_SOURCE.c"
New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
foreach($required in @($PluginSource,$UsbSource)){ if(!(Test-Path -LiteralPath $required)){throw "Required source missing: $required"} }
Copy-Item $PluginSource $PreservedPlugin -Force; Copy-Item $UsbSource $PreservedUsb -Force
[byte[]]$bytes=New-Object byte[] 8192; for($i=0;$i -lt $bytes.Length;$i++){$bytes[$i]=0xFF}; [IO.File]::WriteAllBytes($Companion,$bytes)

Write-Host "1541HUD T0.0.16 - OneROM v0.7.2 baseline port"
Write-Host "No intended monitor behavior changes from V0.0.32."
Write-Host "Building clean v0.7.2 passive base firmware..."
& wsl bash -lc "cd $RepoQ && make firmware TOOLCHAIN=$ToolchainQ EXTRA_C_FLAGS=-DHUD1541_PASSIVE_UB4"
if($LASTEXITCODE -ne 0){throw "v0.7.2 passive base firmware build failed"}
Write-Host "Building T0.0.16 USER plugin..."
& wsl bash -lc "cd $RepoQ && make -C plugins/user/1541hud-probe clean && make -C plugins/user/1541hud-probe TOOLCHAIN=$ToolchainQ PLUGIN_SRC=src/1541hud_probe_t016_v072_baseline.c"
if($LASTEXITCODE -ne 0){throw "T0.0.16 USER plugin build failed"}
Write-Host "Building v0.7.2 USB plugin with preserved 1541HUD CDC bridge..."
$usbSrc="src/usb_descriptors.c src/usb_picobootx.c src/usb_rom.c src/usb_led.c src/usb_gpio.c src/usb_log.c src/usb_main_t016_1541hud_baseline.c"
$usbSrcQ=Quote-Bash $usbSrc
& wsl bash -lc "cd $RepoQ && make -C plugins/system/usb clean && make -C plugins/system/usb TOOLCHAIN=$ToolchainQ SRC=$usbSrcQ"
if($LASTEXITCODE -ne 0){throw "T0.0.16 USB SYSTEM plugin build failed"}
$baseFirmware=Join-Path $Repo "firmware\build\onerom-rp235x.bin"
$userPlugin=Join-Path $PluginDir "build\plugin_user.bin"
$systemPlugin=Join-Path $UsbDir "build\usb_system_plugin.bin"
foreach($artifact in @($baseFirmware,$userPlugin,$systemPlugin)){if(!(Test-Path $artifact)){throw "Required build artifact missing: $artifact"}}
& $OneRomCli firmware build --board fire-24-e --base-firmware $baseFirmware --slot "file=$Companion,type=2364,cs1=active-low" --plugin "file=$systemPlugin" --plugin "file=$userPlugin" --out "$OutBase.bin"
if($LASTEXITCODE -ne 0){throw "OneROM firmware composition failed"}
$OutBinWsl=Get-WslPath "$OutBase.bin"; $OutUf2Wsl=Get-WslPath "$OutBase.uf2"
& wsl bash -lc ((Quote-Bash $Picotool)+" uf2 convert "+(Quote-Bash $OutBinWsl)+" "+(Quote-Bash $OutUf2Wsl))
if($LASTEXITCODE -ne 0){throw "UF2 conversion failed"}
Write-Host "T0.0.16 build complete. Expected telemetry identity: T0.0.16"
Get-Item "$OutBase.bin","$OutBase.uf2",$PreservedPlugin,$PreservedUsb | Format-Table Name,Length,LastWriteTime
Get-FileHash "$OutBase.bin","$OutBase.uf2",$PreservedPlugin,$PreservedUsb -Algorithm SHA256
