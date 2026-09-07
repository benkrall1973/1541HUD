param(
    [string]$Repo = (Get-Location).Path
)

$ErrorActionPreference = "Stop"

$Probe = Join-Path $Repo "plugins/user/1541hud-probe/src/1541hud_probe_t000.c"
$Build = Join-Path $Repo "1541hud/Build-1541HUD-T000.ps1"
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$BackupDir = Join-Path $Repo "build-1541hud/T0.0.0_MAILBOX_COLLISION_PRE_FIX_V2_$Stamp"

if (-not (Test-Path $Probe)) { throw "Missing experimental source: $Probe" }
if (-not (Test-Path $Build)) { throw "Missing T0.0.0 build script: $Build" }

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item $Probe (Join-Path $BackupDir "1541hud_probe_t000.c") -Force
git -C $Repo diff --binary -- plugins/user/1541hud-probe/src/1541hud_probe_t000.c |
    Set-Content -Encoding UTF8 (Join-Path $BackupDir "pre-fix-v2.patch")

$s = Get-Content -LiteralPath $Probe -Raw

function Apply-Regex {
    param(
        [string]$Pattern,
        [string]$Replacement,
        [string]$Label,
        [switch]$AlreadyOkay
    )
    $global:s
    $re = [regex]::new($Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($re.IsMatch($s)) {
        $s = $re.Replace($s, $Replacement, 1)
        Write-Host "Patched: $Label"
        return
    }
    if ($AlreadyOkay) {
        Write-Host "Already patched: $Label"
        return
    }
    throw "Patch point not found: $Label"
}

# 1) Remove static ring if still present. Tolerate v1 having already done this.
if ($s -match 'static\s+volatile\s+uint32_t\s+sector_ring\s*\[\s*SECTOR_RING_WORDS\s*\]') {
    $s = [regex]::Replace(
        $s,
        'static\s+volatile\s+uint32_t\s+sector_ring\s*\[\s*SECTOR_RING_WORDS\s*\]\s*__attribute__\s*\(\(aligned\(256\)\)\)\s*;',
        '/* T0.0.0 read ring is allocated dynamically; never place it in USER .bss.
 * USER static RAM begins at 0x20081C00, the same fixed address used by the
 * 1541HUD mailbox.
 */',
        1
    )
    Write-Host "Patched: remove static ring/mailbox collision"
} else {
    Write-Host "Already patched: remove static ring/mailbox collision"
}

# 2) pio_dma_init signature, tolerate v1 edit.
if ($s -match 'static\s+void\s+pio_dma_init\s*\(\s*volatile\s+drivehud_mailbox_t\s*\*m\s*\)') {
    $s = [regex]::Replace(
        $s,
        'static\s+void\s+pio_dma_init\s*\(\s*volatile\s+drivehud_mailbox_t\s*\*m\s*\)',
        'static void pio_dma_init(volatile drivehud_mailbox_t *m,
 volatile uint32_t *sector_ring)',
        1
    )
    Write-Host "Patched: pio_dma_init dynamic ring parameter"
} elseif ($s -match 'static\s+void\s+pio_dma_init\s*\(\s*volatile\s+drivehud_mailbox_t\s*\*m\s*,\s*volatile\s+uint32_t\s*\*sector_ring\s*\)') {
    Write-Host "Already patched: pio_dma_init dynamic ring parameter"
} else {
    throw "Cannot identify pio_dma_init signature"
}

# 3) Replace DMA10 setup by locating the DMA10 block between DMA10 ctrl reset and DMA11 ctrl reset.
$dmaPattern = '(?ms)^\s*DMA10->ctrl_trig\s*=\s*0u;\s*\r?\n.*?^\s*DMA11->ctrl_trig\s*=\s*0u;'
$dmaReplacement = @'
 DMA10->ctrl_trig = 0u;
 if (sector_ring != 0) {
 DMA10->read_addr = (uint32_t)(uintptr_t)&PIO_RXF2;
 DMA10->write_addr = (uint32_t)(uintptr_t)&sector_ring[0];
 DMA10->transfer_count = DMA_TRIGGER_SELF_MAX;
 DMA10->ctrl_trig =
 DMA_EN | DMA_SIZE_32 | DMA_INCR_WRITE |
 DMA_RING_SIZE(8u) | DMA_RING_SEL |
 DMA_CHAIN_TO(DMA_SECTOR_CH) | DMA_TREQ(DREQ_PIO0_RX2) | DMA_IRQ_QUIET;
 }

 DMA11->ctrl_trig = 0u;
'@
if ($s -match '(?s)DMA10->ctrl_trig\s*=\s*0u;.*?if\s*\(\s*sector_ring\s*!=\s*0\s*\).*?DMA11->ctrl_trig\s*=\s*0u;') {
    Write-Host "Already patched: conditional DMA10 setup"
} elseif ([regex]::IsMatch($s, $dmaPattern)) {
    $s = [regex]::Replace($s, $dmaPattern, $dmaReplacement, 1)
    Write-Host "Patched: conditional DMA10 setup"
} else {
    throw "Could not locate DMA10 setup block"
}

# 4) Conditional SM2 enable.
if ($s -match 'if\s*\(\s*sector_ring\s*!=\s*0\s*\)\s*PIO_CTRL\s*\|=\s*\(1u\s*<<\s*2\)') {
    Write-Host "Already patched: conditional SM2 enable"
} elseif ($s -match 'PIO_CTRL\s*\|=\s*\(1u\s*<<\s*2\)\s*\|\s*\(1u\s*<<\s*3\)\s*;') {
    $s = [regex]::Replace(
        $s,
        'PIO_CTRL\s*\|=\s*\(1u\s*<<\s*2\)\s*\|\s*\(1u\s*<<\s*3\)\s*;',
        'PIO_CTRL |= (1u << 3);
 if (sector_ring != 0) PIO_CTRL |= (1u << 2);',
        1
    )
    Write-Host "Patched: conditional SM2 enable"
} else {
    throw "Could not locate combined SM2/SM3 enable"
}

# 5) Add allocator/ring locals.
if ($s -match 'ora_alloc_fn_t\s+alloc\s*;') {
    Write-Host "Already patched: allocator/ring locals"
} else {
    $s = [regex]::Replace(
        $s,
        'ora_gpio_query_fn_t\s+gpio_query\s*;\s*\r?\n\s*volatile\s+drivehud_mailbox_t\s*\*m\s*=\s*DRIVEHUD_MAILBOX\s*;',
        'ora_gpio_query_fn_t gpio_query;
 ora_alloc_fn_t alloc;
 volatile drivehud_mailbox_t *m = DRIVEHUD_MAILBOX;
 volatile uint32_t *sector_ring = 0;
 void *sector_alloc_raw = 0;',
        1
    )
    Write-Host "Patched: allocator/ring locals"
}

# 6) Look up allocator.
if ($s -match 'lookup\s*\(\s*ORA_ID_ALLOC\s*\)') {
    Write-Host "Already patched: ORA_ID_ALLOC lookup"
} else {
    $s = [regex]::Replace(
        $s,
        'gpio_query\s*=\s*\(ora_gpio_query_fn_t\)lookup\s*\(\s*ORA_ID_GPIO_QUERY\s*\)\s*;',
        'gpio_query = (ora_gpio_query_fn_t)lookup(ORA_ID_GPIO_QUERY);
 alloc = (ora_alloc_fn_t)lookup(ORA_ID_ALLOC);',
        1
    )
    Write-Host "Patched: ORA_ID_ALLOC lookup"
}

# 7) Replace startup call with allocation block.
if ($s -match 'sector_alloc_raw\s*=\s*alloc') {
    Write-Host "Already patched: dynamic ring allocation"
} else {
    $startPattern = '(?ms)m->flags\s*=\s*DRIVEHUD_FLAG_INPUTS_SAFE\s*;\s*\r?\n\s*pio_dma_init\s*\(\s*m\s*(?:,\s*sector_ring\s*)?\)\s*;'
    $startReplacement = @'
m->flags = DRIVEHUD_FLAG_INPUTS_SAFE;

 /*
  * T0.0.0 experimental read ring.
  * USER static RAM starts at 0x20081C00, which is also the HUD mailbox.
  * Allocate outside .bss and align to 256 bytes for DMA ring wrapping.
  * If allocation fails, leave SM2/DMA10 disabled and preserve the proven SM3 path.
  */
 if (alloc != 0) {
 sector_alloc_raw = alloc((SECTOR_RING_WORDS * sizeof(uint32_t)) + 255u);
 if (sector_alloc_raw != 0) {
 uintptr_t a = ((uintptr_t)sector_alloc_raw + 255u) &
 ~(uintptr_t)255u;
 sector_ring = (volatile uint32_t *)a;
 for (i = 0u; i < SECTOR_RING_WORDS; ++i) sector_ring[i] = 0u;
 }
 }

 pio_dma_init(m, sector_ring);
'@
    if (-not [regex]::IsMatch($s, $startPattern)) { throw "Could not locate startup pio_dma_init call" }
    $s = [regex]::Replace($s, $startPattern, $startReplacement, 1)
    Write-Host "Patched: dynamic ring allocation"
}

# 8) Guard/bound experimental loop using broad anchors.
if ($s -match 'uint32_t\s+budget\s*=\s*16u') {
    Write-Host "Already patched: bounded experimental consumer"
} else {
    $loopPattern = '(?ms)(produced_total\s*=\s*dma_update_producer\s*\(\s*produced_total\s*,\s*&last_remaining\s*\)\s*;\s*\r?\n)(.*?)(\r?\n\s*m->pio_pc\s*=\s*PIO_SM3_ADDR\s*&\s*0x1Fu\s*;)'
    $m = [regex]::Match($s, $loopPattern)
    if (-not $m.Success) { throw "Could not locate experimental consumer block" }

    $middle = $m.Groups[2].Value
    if ($middle -notmatch 'sector_dma_update_producer' -or $middle -notmatch 'sector_ring') {
        throw "Located loop block does not look like experimental DMA10 consumer"
    }

    $replacement = $m.Groups[1].Value + @'
 if (sector_ring != 0) {
 sector_produced_total = sector_dma_update_producer(sector_produced_total,
 &sector_last_remaining);

 if ((sector_produced_total - sector_consumer_total) > SECTOR_RING_WORDS) {
 sector_consumer_total = sector_produced_total - SECTOR_RING_WORDS;
 }

 {
 uint32_t budget = 16u;
 while (sector_consumer_total != sector_produced_total && budget != 0u) {
 uint32_t sidx = sector_consumer_total & SECTOR_RING_MASK;
 uint32_t ss = sector_ring[sidx];
 sector_consumer_total++;
 budget--;

 if (uc2_porta_read(ss)) {
 uint8_t data = logical_data_from_gpio(ss);
 sector_uc2a_count++;

 if ((sector_uc2a_count & (SECTOR_REPORT_DIV - 1u)) == 0u) {
 queue_event(m,
 (DRIVEHUD_EVENT_UC2A_SAMPLE << 28) |
 ((sector_uc2a_count & 0x000FFFFFu) << 8) |
 (uint32_t)data);
 }
 }
 }

 sector_produced_total = sector_dma_update_producer(sector_produced_total,
 &sector_last_remaining);
 }
 }
'@ + $m.Groups[3].Value

    $s = $s.Substring(0, $m.Index) + $replacement + $s.Substring($m.Index + $m.Length)
    Write-Host "Patched: bounded experimental consumer"
}

Set-Content -LiteralPath $Probe -Value $s -NoNewline

Write-Host ""
Write-Host "Sanity checks..."

if (Select-String -Path $Probe -Pattern 'static volatile uint32_t sector_ring[' -SimpleMatch -Quiet) {
    throw "Static sector ring still present."
}
if (-not (Select-String -Path $Probe -Pattern 'ORA_ID_ALLOC' -SimpleMatch -Quiet)) {
    throw "Allocator lookup missing."
}
if (-not (Select-String -Path $Probe -Pattern 'pio_dma_init(m, sector_ring);' -SimpleMatch -Quiet)) {
    throw "Dynamic ring not passed to pio_dma_init."
}

Write-Host "Building repaired T0.0.0..."
& powershell.exe -ExecutionPolicy Bypass -File $Build
if ($LASTEXITCODE -ne 0) { throw "T0.0.0 build failed after mailbox-collision fix." }

$Uf2 = Join-Path $Repo "build-1541hud/1541HUD_OneROM_T0.0.0.uf2"
$Bin = Join-Path $Repo "build-1541hud/1541HUD_OneROM_T0.0.0.bin"

if (-not (Test-Path $Uf2)) { throw "Expected UF2 missing: $Uf2" }
if (-not (Test-Path $Bin)) { throw "Expected BIN missing: $Bin" }

Write-Host ""
Write-Host "MAILBOX COLLISION FIX BUILT"
Write-Host "Pre-fix V2 snapshot: $BackupDir"
Write-Host ""
Get-FileHash -Algorithm SHA256 $Bin,$Uf2
Write-Host ""
Write-Host "Do not flash yet. Review build output first."
