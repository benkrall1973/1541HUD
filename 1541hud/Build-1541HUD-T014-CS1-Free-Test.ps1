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
Write-Host "1541HUD T0.0.14 - CS1-free decode test"
Write-Host ""
Write-Host "TEST PURPOSE: prove whether the current decoder can operate from UC2 /CS2 alone."
Write-Host "FIRST TEST WITH THE CS1 WIRE STILL CONNECTED. Do not move the wire yet."
Write-Host ""

if ([string]::IsNullOrWhiteSpace($Repo)) {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $candidate = Join-Path $projectRoot "OneROM"
    if ((Test-Path -LiteralPath (Join-Path $candidate "firmware\ora\plugin.mk")) -and
        (Test-Path -LiteralPath (Join-Path $candidate "plugins"))) {
        $Repo = (Resolve-Path -LiteralPath $candidate).Path
    }
}

if ([string]::IsNullOrWhiteSpace($Repo)) {
    throw "Could not locate OneROM repository. Use -Repo."
}
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
                $matches = Get-ChildItem -LiteralPath $desktop -Directory -Filter "onerom-cli-win-*" -ErrorAction SilentlyContinue |
                    Sort-Object Name -Descending
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
if ([string]::IsNullOrWhiteSpace($OneRomCli)) {
    throw "Could not locate onerom.exe. Use -OneRomCli or ONEROM_CLI."
}

$Repo = $Repo -replace '^Microsoft\.PowerShell\.Core\\FileSystem::',''
$RepoWsl = Get-WslPath $Repo
$RepoQ = Quote-Bash $RepoWsl
$ToolchainQ = Quote-Bash $Toolchain

$PluginDir = Join-Path $Repo "plugins\user\1541hud-probe"
$BaseSource = Join-Path $PluginDir "src\1541hud_probe_t011.c"
$TestSource = Join-Path $PluginDir "src\1541hud_probe_t014_cs1_free.c"
$BuildDir = Join-Path $Repo "build-1541hud"
$OutBase = Join-Path $BuildDir "1541HUD_OneROM_T0.0.14_CS1_Free_Test"
$PreservedSource = Join-Path $BuildDir "1541hud_probe_t014_cs1_free_SOURCE.c"
$Companion = Join-Path $BuildDir "1541hud_companion_8k.bin"

if (!(Test-Path -LiteralPath $BaseSource)) {
    throw "Canonical T0.0.11 source missing: $BaseSource"
}
New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null

# Generate the exact T0.0.14 test source from the preserved T0.0.11 source.
# The ONLY decode-logic change is that UC2 selection no longer requires CS1.
$src = [System.IO.File]::ReadAllText($BaseSource)
$old = @'
#define MASK_CS1 (1u << 24)
#define MASK_nCS2 (1u << 25)
'@
$new = @'
/* T0.0.14 TEST: GPIO24/CS1 deliberately unused by decode logic. */
#define MASK_nCS2 (1u << 25)
'@
if (!$src.Contains($old)) { throw "Expected CS1 mask block not found; refusing to generate test source." }
$src = $src.Replace($old, $new)

$old = @'
static uint8_t uc2_selected(uint32_t v) {
 return (uint8_t)(((v & MASK_CS1) != 0u) && ((v & MASK_nCS2) == 0u));
}
'@
$new = @'
static uint8_t uc2_selected(uint32_t v) {
 /* T0.0.14 TEST: determine UC2 selection from /CS2 alone.
  * If this preserves all monitor functions with CS1 connected and then
  * disconnected, GPIO24 can be repurposed for the physical SYNC signal.
  */
 return (uint8_t)((v & MASK_nCS2) == 0u);
}
'@
if (!$src.Contains($old)) { throw "Expected uc2_selected() block not found; refusing to generate test source." }
$src = $src.Replace($old, $new)

$banner = "/* 1541HUD T0.0.14 CS1-FREE DECODE TEST - generated from T0.0.11 canonical source. */`r`n"
[System.IO.File]::WriteAllText($TestSource, $banner + $src, [System.Text.UTF8Encoding]::new($false))
Copy-Item -LiteralPath $TestSource -Destination $PreservedSource -Force

Write-Host "Generated and preserved exact T0.0.14 test source:"
Write-Host "  $PreservedSource"
Write-Host "Source SHA256:"
Get-FileHash $PreservedSource -Algorithm SHA256

Write-Host "Creating passive 8K FF companion ROM..."
[byte[]]$bytes = New-Object byte[] 8192
for ($i = 0; $i -lt $bytes.Length; $i++) { $bytes[$i] = 0xFF }
[System.IO.File]::WriteAllBytes($Companion, $bytes)

Write-Host "Building passive OneROM base firmware..."
$baseBuild = "cd $RepoQ && make firmware TOOLCHAIN=$ToolchainQ EXTRA_C_FLAGS=-DHUD1541_PASSIVE_UB4"
& wsl bash -lc $baseBuild
if ($LASTEXITCODE -ne 0) { throw "Passive OneROM base firmware build failed" }

Write-Host "Building T0.0.14 CS1-free USER plugin..."
$userBuild = "cd $RepoQ && make -C plugins/user/1541hud-probe clean && make -C plugins/user/1541hud-probe TOOLCHAIN=$ToolchainQ PLUGIN_SRC=src/1541hud_probe_t014_cs1_free.c"
& wsl bash -lc $userBuild
if ($LASTEXITCODE -ne 0) { throw "T0.0.14 USER plugin build failed" }

Write-Host "Building USB SYSTEM plugin..."
$usbBuild = "cd $RepoQ && make -C plugins/system/usb clean && make -C plugins/system/usb TOOLCHAIN=$ToolchainQ"
& wsl bash -lc $usbBuild
if ($LASTEXITCODE -ne 0) { throw "USB SYSTEM plugin build failed" }

$baseFirmware = Join-Path $Repo "firmware\build\onerom-rp235x.bin"
$userPlugin = Join-Path $Repo "plugins\user\1541hud-probe\build\plugin_user.bin"
$systemPlugin = Join-Path $Repo "plugins\system\usb\build\usb_system_plugin.bin"
foreach ($artifact in @($baseFirmware, $userPlugin, $systemPlugin)) {
    if (!(Test-Path -LiteralPath $artifact)) { throw "Required build artifact missing: $artifact" }
}

Write-Host "Composing Fire-24-E T0.0.14 test firmware..."
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
Write-Host "Build complete. FIRST TEST: leave CS1 wire physically connected."
Write-Host "If every proven HUD function still works, power down and disconnect ONLY CS1, then retest the same image."
Get-Item "$OutBase.bin", "$OutBase.uf2", $PreservedSource | Format-Table Name,Length,LastWriteTime
Write-Host "SHA256:"
Get-FileHash "$OutBase.bin" -Algorithm SHA256
Get-FileHash "$OutBase.uf2" -Algorithm SHA256
Get-FileHash $PreservedSource -Algorithm SHA256
