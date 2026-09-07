param(
    [string]$OneRomCli = "",
    [string]$Toolchain = "/usr/bin",
    [string]$Picotool = "/opt/picotool/build/picotool"
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$OneRomRepo = Join-Path $ProjectRoot "OneROM"
$Builder = Join-Path $PSScriptRoot "Build-1541HUD-T011.ps1"

if (!(Test-Path -LiteralPath (Join-Path $OneRomRepo "firmware\ora\plugin.mk"))) {
    throw "OneROM build tree not found at: $OneRomRepo"
}

if (!(Test-Path -LiteralPath $Builder)) {
    throw "T0.0.11 canonical builder not found at: $Builder"
}

$arguments = @(
    "-Repo", $OneRomRepo,
    "-Toolchain", $Toolchain,
    "-Picotool", $Picotool
)

if (![string]::IsNullOrWhiteSpace($OneRomCli)) {
    $arguments += @("-OneRomCli", $OneRomCli)
}

& $Builder @arguments
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
