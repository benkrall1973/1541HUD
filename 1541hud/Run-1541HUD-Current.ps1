$ErrorActionPreference = "Stop"

$Gui = Join-Path $PSScriptRoot "gui\1541HUD_V0.0.32.py"
if (!(Test-Path -LiteralPath $Gui)) {
    throw "Current 1541HUD GUI not found: $Gui"
}

$py = Get-Command py.exe -ErrorAction SilentlyContinue
if ($py) {
    & $py.Source $Gui
    exit $LASTEXITCODE
}

$python = Get-Command python.exe -ErrorAction SilentlyContinue
if ($python) {
    & $python.Source $Gui
    exit $LASTEXITCODE
}

throw "Python was not found on PATH."
