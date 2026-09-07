param(
    [string]$Repo = (Get-Location).Path
)

$ErrorActionPreference = "Stop"

$T001 = Join-Path $Repo "plugins/user/1541hud-probe/src/1541hud_probe_t001.c"
$T002 = Join-Path $Repo "plugins/user/1541hud-probe/src/1541hud_probe_t002.c"
$Makefile = Join-Path $Repo "plugins/user/1541hud-probe/Makefile"

$User1541 = Join-Path $Repo "plugins/user/1541hud-probe/src/1541hud_mailbox.h"
$UserCompat = Join-Path $Repo "plugins/user/1541hud-probe/src/drivehud_mailbox.h"
$Usb1541 = Join-Path $Repo "plugins/system/usb/include/1541hud_mailbox.h"
$UsbCompat = Join-Path $Repo "plugins/system/usb/include/drivehud_mailbox.h"
$UsbMain = Join-Path $Repo "plugins/system/usb/src/usb_main.c"

$Build001 = Join-Path $Repo "1541hud/Build-1541HUD-T001.ps1"
$Build002 = Join-Path $Repo "1541hud/Build-1541HUD-T002.ps1"
$Preserve = Join-Path $Repo "Preserve-1541HUD-TestSource.ps1"

foreach ($f in @($T001,$Makefile,$User1541,$UserCompat,$Usb1541,$UsbCompat,$UsbMain,$Build001,$Preserve)) {
    if (-not (Test-Path $f)) { throw "Required file missing: $f" }
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$pre = Join-Path $Repo "build-1541hud/T0.0.2_PRODUCER_DIAG_V2_PREP_$stamp"
New-Item -ItemType Directory -Force -Path $pre | Out-Null

if (Test-Path $T002) { Copy-Item $T002 (Join-Path $pre "1541hud_probe_t002.partial.c") -Force }
Copy-Item $T001 (Join-Path $pre "1541hud_probe_t001.c") -Force
Copy-Item $Makefile (Join-Path $pre "Makefile") -Force
Copy-Item $UsbMain (Join-Path $pre "usb_main.c") -Force
git -C $Repo diff --binary | Set-Content -Encoding UTF8 (Join-Path $pre "pre-v2-working-tree.patch")

function Ensure-LineAfter {
    param(
        [string]$Path,
        [string]$ExistingRegex,
        [string]$NewLine,
        [string]$AlreadyRegex,
        [string]$Label
    )
    $s = Get-Content -LiteralPath $Path -Raw
    if ($s -match $AlreadyRegex) {
        Write-Host "Already present: $Label"
        return
    }
    $m = [regex]::Match($s, $ExistingRegex)
    if (-not $m.Success) { throw "Anchor not found: $Label ($Path)" }
    $insertAt = $m.Index + $m.Length
    $s = $s.Substring(0,$insertAt) + "`r`n" + $NewLine + $s.Substring($insertAt)
    Set-Content -LiteralPath $Path -Value $s -NoNewline
    Write-Host "Added: $Label"
}

Write-Host "Recreating T0.0.2 cleanly from known-good T0.0.1..."
Copy-Item $T001 $T002 -Force

# ----------------------------------------------------------------------
# Version metadata
# ----------------------------------------------------------------------
$s = Get-Content -LiteralPath $T002 -Raw
$reVer = [regex]::new(
    'ORA_DEFINE_USER_PLUGIN\s*\(\s*drivehud_probe_main\s*,\s*0\s*,\s*0\s*,\s*1\s*,\s*0\s*,\s*0\s*,\s*7\s*,\s*1\s*\)\s*;',
    [System.Text.RegularExpressions.RegexOptions]::Singleline
)
if (-not $reVer.IsMatch($s)) { throw "T0.0.1 plugin version declaration not found." }
$s = $reVer.Replace($s, 'ORA_DEFINE_USER_PLUGIN(drivehud_probe_main, 0,0,2,0, 0,7,1);', 1)
Set-Content -LiteralPath $T002 -Value $s -NoNewline
Write-Host "Patched: T0.0.2 plugin version"

# ----------------------------------------------------------------------
# Makefile / build-script isolation
# ----------------------------------------------------------------------
$mk = Get-Content -LiteralPath $Makefile -Raw
if ($mk -match 'PLUGIN_SRC\s*:=\s*src/1541hud_probe_t002\.c') {
    Write-Host "Already present: Makefile T0.0.2 source"
} elseif ($mk -match 'PLUGIN_SRC\s*:=\s*src/1541hud_probe_t001\.c') {
    $mk = $mk -replace 'PLUGIN_SRC\s*:=\s*src/1541hud_probe_t001\.c',
        'PLUGIN_SRC := src/1541hud_probe_t002.c'
    Set-Content -LiteralPath $Makefile -Value $mk -NoNewline
    Write-Host "Patched: Makefile T0.0.2 source"
} else {
    throw "Makefile source is neither T0.0.1 nor T0.0.2."
}

Copy-Item $Build001 $Build002 -Force
$b = Get-Content -LiteralPath $Build002 -Raw
$b = $b.Replace("T0.0.1", "T0.0.2")
$b = $b.Replace("T001", "T002")
Set-Content -LiteralPath $Build002 -Value $b -NoNewline
Write-Host "Created: Build-1541HUD-T002.ps1"

# ----------------------------------------------------------------------
# Event type 8: cumulative producer diagnostic
# ----------------------------------------------------------------------
Ensure-LineAfter $User1541 `
    '(?m)^#define\s+HUD1541_EVENT_READRAW\s+7u\s*$' `
    '#define HUD1541_EVENT_READ_DMA 8u' `
    'HUD1541_EVENT_READ_DMA\s+8u' `
    "USER shared event 8"

Ensure-LineAfter $Usb1541 `
    '(?m)^#define\s+HUD1541_EVENT_READRAW\s+7u\s*$' `
    '#define HUD1541_EVENT_READ_DMA 8u' `
    'HUD1541_EVENT_READ_DMA\s+8u' `
    "USB shared event 8"

Ensure-LineAfter $UserCompat `
    '(?m)^#define\s+DRIVEHUD_EVENT_READRAW\s+HUD1541_EVENT_READRAW\s*$' `
    '#define DRIVEHUD_EVENT_READ_DMA HUD1541_EVENT_READ_DMA' `
    'DRIVEHUD_EVENT_READ_DMA\s+HUD1541_EVENT_READ_DMA' `
    "USER compatibility alias event 8"

Ensure-LineAfter $UsbCompat `
    '(?m)^#define\s+DRIVEHUD_EVENT_READRAW\s+HUD1541_EVENT_READRAW\s*$' `
    '#define DRIVEHUD_EVENT_READ_DMA HUD1541_EVENT_READ_DMA' `
    'DRIVEHUD_EVENT_READ_DMA\s+HUD1541_EVENT_READ_DMA' `
    "USB compatibility alias event 8"

# ----------------------------------------------------------------------
# Add a last-reported counter next to raw_read_count.
# ----------------------------------------------------------------------
$s = Get-Content -LiteralPath $T002 -Raw
if ($s -notmatch '\bread_dma_last_report\b') {
    $m = [regex]::Match($s, '(?m)^(?<indent>\s*)uint32_t\s+raw_read_count\s*=\s*0u\s*;')
    if (-not $m.Success) { throw "Could not find raw_read_count local." }
    $indent = $m.Groups['indent'].Value
    $replacement = $m.Value + "`r`n" + $indent + "uint32_t read_dma_last_report = 0u;"
    $s = $s.Substring(0,$m.Index) + $replacement + $s.Substring($m.Index + $m.Length)
    Set-Content -LiteralPath $T002 -Value $s -NoNewline
    Write-Host "Patched: producer diagnostic counter"
} else {
    Write-Host "Already present: producer diagnostic counter"
}

# ----------------------------------------------------------------------
# Instrument the EXISTING cumulative producer update.
#
# This is deliberately keyed to sector_dma_update_producer(), rather than
# the ring write address itself. DMA ring addressing wraps every 64 words;
# the helper is the code that converts those wraps into cumulative movement.
# Emit whenever cumulative producer movement advances by >=64 words.
# ----------------------------------------------------------------------
$s = Get-Content -LiteralPath $T002 -Raw

if ($s -notmatch 'READDMA_PRODUCER_DIAGNOSTIC') {
    $patterns = @(
        '(?m)^(?<indent>\s*)sector_produced_total\s*=\s*sector_dma_update_producer\s*\([^;]+;\s*$',
        '(?m)^(?<indent>\s*)uint32_t\s+sector_produced_total\s*=\s*sector_dma_update_producer\s*\([^;]+;\s*$'
    )

    $m = $null
    foreach ($pat in $patterns) {
        $candidate = [regex]::Match($s, $pat)
        if ($candidate.Success) { $m = $candidate; break }
    }

    if ($null -eq $m -or -not $m.Success) {
        throw "Could not find sector_dma_update_producer() assignment. No source was built."
    }

    $indent = $m.Groups['indent'].Value
    $diag = @"
$m
${indent}/* READDMA_PRODUCER_DIAGNOSTIC */
${indent}if ((sector_produced_total - read_dma_last_report) >= 64u) {
${indent}    read_dma_last_report = sector_produced_total;
${indent}    queue_event(m,
${indent}        (DRIVEHUD_EVENT_READ_DMA << 28) |
${indent}        (sector_produced_total & 0x0FFFFFFFu));
${indent}}
"@

    # PowerShell expanded $m as Match.ToString(), i.e. the exact matched line.
    $s = $s.Substring(0,$m.Index) + $diag + $s.Substring($m.Index + $m.Length)
    Set-Content -LiteralPath $T002 -Value $s -NoNewline
    Write-Host "Patched: cumulative DMA producer telemetry"
} else {
    Write-Host "Already present: cumulative DMA producer telemetry"
}

# ----------------------------------------------------------------------
# USB event formatter. Insert after READRAW formatter, but do it by finding
# the start of READRAW and the next "}else"/"} else" boundary, not by relying
# on exact whitespace from previous patches.
# ----------------------------------------------------------------------
$u = Get-Content -LiteralPath $UsbMain -Raw

# Remove any partial/bad T0.0.2 formatter from the failed first attempt.
$u = [regex]::Replace(
    $u,
    '(?ms)\}?\s*else\s+if\s*\(\s*type\s*==\s*DRIVEHUD_EVENT_READ_DMA\s*\)\s*\{.*?READDMA T0\.0\.2 produced=.*?p\s*=\s*drivehud_append_str\s*\(\s*p\s*,\s*e\s*,\s*"\\r\\n"\s*\)\s*;\s*\}',
    '',
    1
)

if ($u -notmatch 'READDMA T0\.0\.2 produced=') {
    $start = [regex]::Match($u, 'else\s+if\s*\(\s*type\s*==\s*DRIVEHUD_EVENT_READRAW\s*\)\s*\{')
    if (-not $start.Success) { throw "READRAW USB formatter start not found." }

    $searchStart = $start.Index + $start.Length
    $next = [regex]::Match($u.Substring($searchStart), '\}\s*else|\}\s*\r?\n\s*else')
    if (-not $next.Success) {
        # Fallback: find the first closing brace followed by event_tail logic.
        $next = [regex]::Match($u.Substring($searchStart), '\}\s*\r?\n\s*m->event_tail')
        if (-not $next.Success) { throw "Could not find end of READRAW formatter." }
    }

    $insertAt = $searchStart + $next.Index + 1

    $block = @'
else if(type==DRIVEHUD_EVENT_READ_DMA){
 uint32_t produced=w&0x0FFFFFFFu;
 p=drivehud_append_str(p,e,"READDMA T0.0.2 produced=");
 p=drivehud_append_u32(p,e,produced);
 p=drivehud_append_str(p,e,"\r\n");
}
'@

    $u = $u.Substring(0,$insertAt) + $block + $u.Substring($insertAt)
    Set-Content -LiteralPath $UsbMain -Value $u -NoNewline
    Write-Host "Patched: USB READDMA formatter"
}

# ----------------------------------------------------------------------
# Sanity checks
# ----------------------------------------------------------------------
Write-Host ""
Write-Host "Sanity checks..."

$checks = @(
    @{Path=$T002; Pattern='ORA_DEFINE_USER_PLUGIN\(drivehud_probe_main,\s*0,0,2,0,\s*0,7,1\)'; Name='T0.0.2 plugin version'},
    @{Path=$T002; Pattern='READDMA_PRODUCER_DIAGNOSTIC'; Name='producer instrumentation marker'},
    @{Path=$T002; Pattern='sector_produced_total\s*=\s*sector_dma_update_producer'; Name='existing producer helper retained'},
    @{Path=$T002; Pattern='DRIVEHUD_EVENT_READ_DMA\s*<<\s*28'; Name='READDMA producer event'},
    @{Path=$T002; Pattern='uint32_t\s+budget\s*=\s*16u'; Name='bounded experimental consumer retained'},
    @{Path=$T002; Pattern='sector_alloc_raw\s*=\s*alloc'; Name='dynamic ring/mailbox fix retained'},
    @{Path=$UsbMain; Pattern='READDMA T0\.0\.2 produced='; Name='USB formatter'},
    @{Path=$Makefile; Pattern='1541hud_probe_t002\.c'; Name='Makefile source isolation'}
)

foreach ($c in $checks) {
    $txt = Get-Content -LiteralPath $c.Path -Raw
    if ($txt -notmatch $c.Pattern) { throw "Sanity check failed: $($c.Name)" }
    Write-Host " OK: $($c.Name)"
}

if ((Get-Content -LiteralPath $T002 -Raw) -match 'static\s+volatile\s+uint32_t\s+sector_ring\s*\[') {
    throw "Static sector ring reappeared. Refusing to build."
}

Write-Host ""
Write-Host "Building corrected T0.0.2 producer diagnostic..."
& powershell.exe -ExecutionPolicy Bypass -File $Build002
if ($LASTEXITCODE -ne 0) { throw "T0.0.2 build failed." }

$BuildDir = Join-Path $Repo "build-1541hud"
$Uf2 = Join-Path $BuildDir "1541HUD_OneROM_T0.0.2.uf2"
$Bin = Join-Path $BuildDir "1541HUD_OneROM_T0.0.2.bin"

if (-not (Test-Path $Uf2)) { throw "Expected UF2 missing: $Uf2" }
if (-not (Test-Path $Bin)) { throw "Expected BIN missing: $Bin" }

Write-Host ""
Write-Host "T0.0.2 BUILD COMPLETE"
Get-FileHash -Algorithm SHA256 $Bin,$Uf2

Write-Host ""
Write-Host "Preserving exact T0.0.2 source/build bundle..."
& powershell.exe -ExecutionPolicy Bypass -File $Preserve -TestName "T0.0.2_DMA_PRODUCER_DIAGNOSTIC"
if ($LASTEXITCODE -ne 0) {
    throw "Build succeeded but source preservation did not report success."
}

Write-Host ""
Write-Host "============================================================"
Write-Host "T0.0.2 DMA PRODUCER DIAGNOSTIC READY"
Write-Host "============================================================"
Write-Host "UF2: $Uf2"
Write-Host ""
Write-Host "Expected new telemetry if cumulative DMA producer advances:"
Write-Host "  READDMA T0.0.2 produced=64"
Write-Host "  READDMA T0.0.2 produced=128"
Write-Host "  ..."
Write-Host ""
Write-Host "READRAW may also appear if the existing consumer begins moving."
Write-Host "Normal STATE / STATUS / TRACK_WRITE / MOTOR / PHASE / DENSITY must remain."
