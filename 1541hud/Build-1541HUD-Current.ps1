param(
    [string]$OneRomCli = "",
    [string]$Toolchain = "/usr/bin",
    [string]$Picotool = "/opt/picotool/build/picotool"
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$OneRomRepo = Join-Path $ProjectRoot "OneROM"
$Builder = Join-Path $PSScriptRoot "Build-1541HUD-V0032-RC1.ps1"

if (!(Test-Path -LiteralPath (Join-Path $OneRomRepo "firmware\ora\plugin.mk"))) {
    throw "OneROM build tree not found at: $OneRomRepo"
}

if (!(Test-Path -LiteralPath $Builder)) {
    throw "V0.0.32-RC1 current builder not found at: $Builder"
}

$builderParams = @{
    Repo      = $OneRomRepo
    Toolchain = $Toolchain
    Picotool  = $Picotool
}

if (![string]::IsNullOrWhiteSpace($OneRomCli)) {
    $builderParams["OneRomCli"] = $OneRomCli
}

& $Builder @builderParams
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
