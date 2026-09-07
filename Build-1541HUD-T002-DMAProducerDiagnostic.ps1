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
$pre = Join-Path $Repo "build-1541hud/T0.0.2_DMA_PRODUCER_PREP_$stamp"
New-Item -ItemType Directory -Force -Path $pre | Out-Null
Copy-Item $T001 (Join-Path $pre "1541hud_probe_t001.c") -Force
Copy-Item $Makefile (Join-Path $pre "Makefile") -Force
Copy-Item $UsbMain (Join-Path $pre "usb_main.c") -Force
git -C $Repo diff --binary | Set-Content -Encoding UTF8 (Join-Path $pre "pre-t002-working-tree.patch")

Write-Host "Creating isolated T0.0.2 source from current T0.0.1..."
Copy-Item $T001 $T002 -Force

function Replace-OnceRegex {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Replacement,
        [string]$Label
    )
    $s = Get-Content -LiteralPath $Path -Raw
    $re = [regex]::new($Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $re.IsMatch($s)) { throw "Patch point not found: $Label ($Path)" }
    $s = $re.Replace($s, $Replacement, 1)
    Set-Content -LiteralPath $Path -Value $s -NoNewline
    Write-Host "Patched: $Label"
}

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

# ----------------------------------------------------------------------
# Version isolation
# ----------------------------------------------------------------------
Replace-OnceRegex $T002 `
    'ORA_DEFINE_USER_PLUGIN\s*\(\s*drivehud_probe_main\s*,\s*0\s*,\s*0\s*,\s*1\s*,\s*0\s*,\s*0\s*,\s*7\s*,\s*1\s*\)\s*;' `
    'ORA_DEFINE_USER_PLUGIN(drivehud_probe_main, 0,0,2,0, 0,7,1);' `
    "T0.0.2 plugin version"

$mk = Get-Content -LiteralPath $Makefile -Raw
if ($mk -match 'PLUGIN_SRC\s*:=\s*src/1541hud_probe_t002\.c') {
    Write-Host "Already present: Makefile T0.0.2 source"
} elseif ($mk -match 'PLUGIN_SRC\s*:=\s*src/1541hud_probe_t001\.c') {
    $mk = $mk -replace 'PLUGIN_SRC\s*:=\s*src/1541hud_probe_t001\.c',
        'PLUGIN_SRC := src/1541hud_probe_t002.c'
    Set-Content -LiteralPath $Makefile -Value $mk -NoNewline
    Write-Host "Patched: Makefile T0.0.2 source"
} else {
    throw "Makefile is not pointing at T0.0.1 as expected."
}

Copy-Item $Build001 $Build002 -Force
$b = Get-Content -LiteralPath $Build002 -Raw
$b = $b.Replace("T0.0.1", "T0.0.2")
$b = $b.Replace("T001", "T002")
Set-Content -LiteralPath $Build002 -Value $b -NoNewline
Write-Host "Created: Build-1541HUD-T002.ps1"

# ----------------------------------------------------------------------
# Event type 8: DMA10 producer diagnostic
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
# Probe diagnostic
#
# Read DMA10's live write address once per outer loop and emit a sparse
# diagnostic whenever the observed producer count crosses another 4096 words.
#
# This does NOT depend on the experimental consumer or UC2 filter.
# ----------------------------------------------------------------------

$s = Get-Content -LiteralPath $T002 -Raw

if ($s -notmatch 'read_dma_last_report') {
    $anchor = [regex]::Match($s, '(?m)^(?<indent>\s*)uint32_t\s+raw_read_count\s*=\s*0u\s*;')
    if (-not $anchor.Success) {
        throw "Could not find raw_read_count local in T0.0.2."
    }
    $indent = $anchor.Groups['indent'].Value
    $insert = $anchor.Value + "`r`n" +
              $indent + "uint32_t read_dma_last_report = 0u;" + "`r`n" +
              $indent + "uint32_t read_dma_base_addr = sector_ring ? (uint32_t)(uintptr_t)sector_ring : 0u;"
    $s = $s.Substring(0,$anchor.Index) + $insert + $s.Substring($anchor.Index + $anchor.Length)
    Set-Content -LiteralPath $T002 -Value $s -NoNewline
    Write-Host "Patched: DMA producer diagnostic locals"
} else {
    Write-Host "Already present: DMA producer diagnostic locals"
}

$s = Get-Content -LiteralPath $T002 -Raw
if ($s -notmatch 'DRIVEHUD_EVENT_READ_DMA\s*<<\s*28') {
    # Insert immediately before the bounded experimental consumer loop.
    $pattern = '(?ms)(\s*uint32_t\s+budget\s*=\s*16u\s*;\s*\r?\n\s*while\s*\(\s*sector_consumer_total\s*!=\s*sector_produced_total\s*&&\s*budget\s*\)\s*\{)'
    $m = [regex]::Match($s, $pattern)
    if (-not $m.Success) {
        throw "Could not locate bounded DMA10 consumer loop."
    }

    $diag = @'

 if (sector_ring && read_dma_base_addr != 0u) {
 uint32_t live_wa = DMA10->write_addr;
 uint32_t produced_words = (live_wa - read_dma_base_addr) >> 2;
 if ((produced_words - read_dma_last_report) >= 4096u) {
 read_dma_last_report = produced_words;
 queue_event(m,
 (DRIVEHUD_EVENT_READ_DMA << 28) |
 (produced_words & 0x0FFFFFFFu));
 }
 }

'@

    $s = $s.Substring(0,$m.Index) + $diag + $m.Groups[1].Value + $s.Substring($m.Index + $m.Length)
    Set-Content -LiteralPath $T002 -Value $s -NoNewline
    Write-Host "Patched: direct DMA10 producer telemetry"
} else {
    Write-Host "Already present: direct DMA10 producer telemetry"
}

# ----------------------------------------------------------------------
# USB formatter for event 8
# ----------------------------------------------------------------------
$u = Get-Content -LiteralPath $UsbMain -Raw
if ($u -notmatch 'READDMA T0\.0\.2 produced=') {
    $anchorPattern = '(?ms)(\}\s*else\s+if\s*\(\s*type\s*==\s*DRIVEHUD_EVENT_READRAW\s*\)\s*\{.*?p\s*=\s*drivehud_append_str\s*\(\s*p\s*,\s*e\s*,\s*"\\r\\n"\s*\)\s*;\s*\})'
    $m = [regex]::Match($u, $anchorPattern)
    if (-not $m.Success) {
        throw "Could not locate intact READRAW formatter block."
    }

    $block = @'
else if(type==DRIVEHUD_EVENT_READ_DMA){
 uint32_t produced=w&0x0FFFFFFFu;
 p=drivehud_append_str(p,e,"READDMA T0.0.2 produced=");
 p=drivehud_append_u32(p,e,produced);
 p=drivehud_append_str(p,e,"\r\n");
}
'@

    $u = $u.Substring(0,$m.Index + $m.Length) + $block + $u.Substring($m.Index + $m.Length)
    Set-Content -LiteralPath $UsbMain -Value $u -NoNewline
    Write-Host "Patched: USB READDMA formatter"
} else {
    Write-Host "Already present: USB READDMA formatter"
}

# ----------------------------------------------------------------------
# Sanity checks
# ----------------------------------------------------------------------
Write-Host ""
Write-Host "Sanity checks..."

$checks = @(
    @{Path=$T002; Pattern='ORA_DEFINE_USER_PLUGIN\(drivehud_probe_main,\s*0,0,2,0,\s*0,7,1\)'; Name='T0.0.2 plugin version'},
    @{Path=$T002; Pattern='DRIVEHUD_EVENT_READ_DMA\s*<<\s*28'; Name='direct DMA producer event'},
    @{Path=$T002; Pattern='DMA10->write_addr'; Name='DMA10 write-address inspection'},
    @{Path=$T002; Pattern='uint32_t\s+budget\s*=\s*16u'; Name='bounded DMA10 consumer retained'},
    @{Path=$T002; Pattern='sector_alloc_raw\s*=\s*alloc'; Name='dynamic ring collision fix retained'},
    @{Path=$UsbMain; Pattern='READDMA T0\.0\.2 produced='; Name='READDMA USB formatter'},
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
Write-Host "Building T0.0.2 DMA PRODUCER DIAGNOSTIC..."
& powershell.exe -ExecutionPolicy Bypass -File $Build002
if ($LASTEXITCODE -ne 0) { throw "T0.0.2 build failed." }

$BuildDir = Join-Path $Repo "build-1541hud"
$Uf2 = Join-Path $BuildDir "1541HUD_OneROM_T0.0.2.uf2"
$Bin = Join-Path $BuildDir "1541HUD_OneROM_T0.0.2.bin"

if (-not (Test-Path $Uf2)) { throw "Expected UF2 missing: $Uf2" }
if (-not (Test-Path $Bin)) { throw "Expected BIN missing: $Bin" }

Write-Host ""
Write-Host "Preserving exact T0.0.2 source/build bundle..."
& powershell.exe -ExecutionPolicy Bypass -File $Preserve -TestName "T0.0.2_DMA_PRODUCER_DIAGNOSTIC"
if ($LASTEXITCODE -ne 0) { throw "Build succeeded but source preservation failed." }

Write-Host ""
Write-Host "T0.0.2 DMA PRODUCER DIAGNOSTIC COMPLETE"
Get-FileHash -Algorithm SHA256 $Bin,$Uf2
Write-Host ""
Write-Host "UF2: $Uf2"
Write-Host ""
Write-Host "Expected diagnostic telemetry:"
Write-Host "  READDMA T0.0.2 produced=4096"
Write-Host "  READDMA T0.0.2 produced=8192"
Write-Host ""
Write-Host "Interpretation:"
Write-Host "  produced increases -> PIO/DMA path moves; consumer/ring logic is suspect"
Write-Host "  no READDMA      -> PIO/DMA path itself is not moving"
