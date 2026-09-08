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

if ([string]::IsNullOrWhiteSpace($Repo)) {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $candidate = Join-Path $projectRoot "OneROM"
    if (Test-Path -LiteralPath (Join-Path $candidate "firmware\ora\plugin.mk")) {
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

$T015Builder = Join-Path $PSScriptRoot "Build-1541HUD-T015-SYNC-Input-Test.ps1"
if (!(Test-Path -LiteralPath $T015Builder)) { throw "T0.0.15 builder missing: $T015Builder" }

Write-Host ""
Write-Host "1541HUD V0.0.32 - final release build"
Write-Host ""
Write-Host "Step 1: reproduce the hardware-tested T0.0.15 source stack."
& $T015Builder -Repo $Repo -OneRomCli $OneRomCli -Toolchain $Toolchain -Picotool $Picotool
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$PluginDir = Join-Path $Repo "plugins\user\1541hud-probe"
$UsbDir = Join-Path $Repo "plugins\system\usb"
$BuildDir = Join-Path $Repo "build-1541hud"
$T015PluginSource = Join-Path $PluginDir "src\1541hud_probe_t015_sync.c"
$T015UsbSource = Join-Path $UsbDir "src\usb_main_t015_sync.c"
$FinalPluginSource = Join-Path $PluginDir "src\1541hud_probe_v0032.c"
$FinalUsbSource = Join-Path $UsbDir "src\usb_main_v0032.c"
$PreservedPlugin = Join-Path $BuildDir "1541hud_probe_v0032_SOURCE.c"
$PreservedUsb = Join-Path $BuildDir "usb_main_v0032_SOURCE.c"
$OutBase = Join-Path $BuildDir "1541HUD_OneROM_V0.0.32"
$Companion = Join-Path $BuildDir "1541hud_companion_8k.bin"

foreach ($required in @($T015PluginSource,$T015UsbSource,$Companion)) {
    if (!(Test-Path -LiteralPath $required)) { throw "Required T0.0.15 artifact missing: $required" }
}

Write-Host "Step 2: create final V0.0.32 source copies without modifying preserved T0.x or RC1 sources."
$plugin = [System.IO.File]::ReadAllText($T015PluginSource)
$plugin = $plugin.Replace(
    "/* 1541HUD T0.0.15 PHYSICAL SYNC INPUT TEST - generated from T0.0.11 canonical source. */",
    "/* 1541HUD V0.0.32 final release, promoted from hardware-tested V0.0.32-RC1 behavior. */"
)
[System.IO.File]::WriteAllText($FinalPluginSource,$plugin,[System.Text.UTF8Encoding]::new($false))

$usb = [System.IO.File]::ReadAllText($T015UsbSource)
$usb = $usb.Replace("STATE V0.0.30", "STATE V0.0.32")
$usb = $usb.Replace("STATUS V0.0.30", "STATUS V0.0.32")
$usb = $usb.Replace("HDRPHY T0.0.11", "HDRPHY V0.0.32")
$usb = $usb.Replace("RPM T0.0.11", "RPM V0.0.32")
$usb = $usb.Replace("SYNC T0.0.15", "SYNC V0.0.32")
[System.IO.File]::WriteAllText($FinalUsbSource,$usb,[System.Text.UTF8Encoding]::new($false))

Copy-Item -LiteralPath $FinalPluginSource -Destination $PreservedPlugin -Force
Copy-Item -LiteralPath $FinalUsbSource -Destination $PreservedUsb -Force

$RepoWsl = Get-WslPath $Repo
$RepoQ = Quote-Bash $RepoWsl
$ToolchainQ = Quote-Bash $Toolchain

Write-Host "Step 3: rebuild the USER plugin from the final V0.0.32 source copy."
$userBuild = "cd $RepoQ && make -C plugins/user/1541hud-probe clean && make -C plugins/user/1541hud-probe TOOLCHAIN=$ToolchainQ PLUGIN_SRC=src/1541hud_probe_v0032.c"
& wsl bash -lc $userBuild
if ($LASTEXITCODE -ne 0) { throw "V0.0.32 USER plugin build failed" }

Write-Host "Step 4: rebuild USB with unified final V0.0.32 telemetry identity."
$usbSrc = "src/usb_descriptors.c src/usb_picobootx.c src/usb_rom.c src/usb_led.c src/usb_gpio.c src/usb_main_v0032.c"
$usbSrcQ = Quote-Bash $usbSrc
$usbBuild = "cd $RepoQ && make -C plugins/system/usb clean && make -C plugins/system/usb TOOLCHAIN=$ToolchainQ SRC=$usbSrcQ"
& wsl bash -lc $usbBuild
if ($LASTEXITCODE -ne 0) { throw "V0.0.32 USB SYSTEM plugin build failed" }

$baseFirmware = Join-Path $Repo "firmware\build\onerom-rp235x.bin"
$userPlugin = Join-Path $PluginDir "build\plugin_user.bin"
$systemPlugin = Join-Path $UsbDir "build\usb_system_plugin.bin"
foreach ($artifact in @($baseFirmware,$userPlugin,$systemPlugin)) {
    if (!(Test-Path -LiteralPath $artifact)) { throw "Required build artifact missing: $artifact" }
}

Write-Host "Step 5: compose Fire-24-E V0.0.32 firmware."
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
$uf2Command = (Quote-Bash $Picotool) + " uf2 convert " + (Quote-Bash $OutBinWsl) + " " + (Quote-Bash $OutUf2Wsl)
& wsl bash -lc $uf2Command
if ($LASTEXITCODE -ne 0) { throw "UF2 conversion failed" }

Write-Host ""
Write-Host "V0.0.32 build complete."
Write-Host "Expected telemetry identity: V0.0.32"
Write-Host "UF2: $OutBase.uf2"
Write-Host ""
Get-Item "$OutBase.bin","$OutBase.uf2",$PreservedPlugin,$PreservedUsb | Format-Table Name,Length,LastWriteTime
Write-Host "SHA256:"
Get-FileHash "$OutBase.bin","$OutBase.uf2",$PreservedPlugin,$PreservedUsb -Algorithm SHA256
