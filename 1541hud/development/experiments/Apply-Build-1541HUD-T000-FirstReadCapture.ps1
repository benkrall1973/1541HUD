param(
    [string]$Repo = (Get-Location).Path
)

$ErrorActionPreference = "Stop"

function Replace-Exact {
    param(
        [string]$Path,
        [string]$Old,
        [string]$New,
        [string]$Label
    )
    $text = [System.IO.File]::ReadAllText($Path)
    if (-not $text.Contains($Old)) {
        throw "Patch point not found: $Label in $Path"
    }
    $text = $text.Replace($Old, $New)
    [System.IO.File]::WriteAllText($Path, $text, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Patched: $Label"
}

$Probe = Join-Path $Repo "plugins/user/1541hud-probe/src/1541hud_probe_t000.c"
$Mailbox = Join-Path $Repo "plugins/user/1541hud-probe/src/1541hud_mailbox.h"
$Compat = Join-Path $Repo "plugins/user/1541hud-probe/src/drivehud_mailbox.h"
$Usb = Join-Path $Repo "plugins/system/usb/src/usb_main.c"
$Build = Join-Path $Repo "1541hud/Build-1541HUD-T000.ps1"

foreach ($p in @($Probe,$Mailbox,$Compat,$Usb,$Build)) {
    if (-not (Test-Path $p)) { throw "Required file missing: $p" }
}

# Refuse to patch the stable source by accident.
if ($Probe -notmatch "t000") { throw "Refusing to patch non-T0.0.0 probe source." }

# Preserve a local pre-test diff.
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$BackupDir = Join-Path $Repo "build-1541hud/T0.0.0_FIRST_READ_CAPTURE_SOURCE_$Stamp"
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item $Probe $BackupDir
Copy-Item $Mailbox $BackupDir
Copy-Item $Compat $BackupDir
Copy-Item $Usb $BackupDir
Copy-Item $Build $BackupDir
Write-Host "Saved pre-test source snapshot: $BackupDir"

Replace-Exact $Probe @'
#define PIO_RXF3 (*(volatile uint32_t *)(PIO0_BASE + 0x02Cu))
#define PIO_INSTR_MEM(n) (*(volatile uint32_t *)(PIO0_BASE + 0x048u + ((n) * 4u)))
#define PIO_SM3_CLKDIV (*(volatile uint32_t *)(PIO0_BASE + 0x110u))
'@ @'
#define PIO_RXF2 (*(volatile uint32_t *)(PIO0_BASE + 0x028u))
#define PIO_RXF3 (*(volatile uint32_t *)(PIO0_BASE + 0x02Cu))
#define PIO_INSTR_MEM(n) (*(volatile uint32_t *)(PIO0_BASE + 0x048u + ((n) * 4u)))
#define PIO_SM2_CLKDIV (*(volatile uint32_t *)(PIO0_BASE + 0x0F8u))
#define PIO_SM2_EXECCTRL (*(volatile uint32_t *)(PIO0_BASE + 0x0FCu))
#define PIO_SM2_SHIFTCTRL (*(volatile uint32_t *)(PIO0_BASE + 0x100u))
#define PIO_SM2_ADDR (*(volatile uint32_t *)(PIO0_BASE + 0x104u))
#define PIO_SM2_INSTR (*(volatile uint32_t *)(PIO0_BASE + 0x108u))
#define PIO_SM2_PINCTRL (*(volatile uint32_t *)(PIO0_BASE + 0x10Cu))
#define PIO_SM3_CLKDIV (*(volatile uint32_t *)(PIO0_BASE + 0x110u))
'@ "PIO0 SM2 register definitions"

Replace-Exact $Probe @'
#define DMA_BASE 0x50000000u
#define DMA_CH 11u
'@ @'
#define DMA_BASE 0x50000000u
#define DMA_SECTOR_CH 10u
#define DMA_CH 11u
'@ "DMA10 channel definition"

Replace-Exact $Probe @'
#define DMA11 ((dma_ch_t *)(DMA_BASE + DMA_CH * 0x40u))
'@ @'
#define DMA10 ((dma_ch_t *)(DMA_BASE + DMA_SECTOR_CH * 0x40u))
#define DMA11 ((dma_ch_t *)(DMA_BASE + DMA_CH * 0x40u))

#define SECTOR_RING_WORDS 256u
#define SECTOR_RING_MASK (SECTOR_RING_WORDS - 1u)
#define SECTOR_REPORT_DIV 1024u
static volatile uint32_t sector_ring[SECTOR_RING_WORDS] __attribute__((aligned(1024)));
'@ "DMA10 ring"

Replace-Exact $Probe @'
#define DREQ_PIO0_RX3 7u
'@ @'
#define DREQ_PIO0_RX2 6u
#define DREQ_PIO0_RX3 7u
'@ "PIO0 RX2 DREQ"

Replace-Exact $Probe @'
static uint8_t uc2_orb_write(uint32_t v) {
 return (uint8_t)(uc2_selected(v) &&
 ((logical_addr13_from_gpio(v) & 0x0Fu) == 0u));
}
'@ @'
static uint8_t uc2_orb_write(uint32_t v) {
 return (uint8_t)(uc2_selected(v) &&
 ((logical_addr13_from_gpio(v) & 0x0Fu) == 0u));
}

static uint8_t uc2_porta_read(uint32_t v) {
 return (uint8_t)(uc2_selected(v) &&
 ((v & (1u << 9)) != 0u) &&
 ((logical_addr13_from_gpio(v) & 0x0Fu) == 1u));
}
'@ "UC2 Port-A read filter"

Replace-Exact $Probe @'
static uint32_t dma_update_producer(uint32_t produced_total,
 uint32_t *last_remaining) {
 uint32_t remaining = DMA11->transfer_count & DMA_COUNT_MASK;
 uint32_t advanced;
 if (remaining <= *last_remaining) {
 advanced = *last_remaining - remaining;
 } else {
 advanced = *last_remaining + (DMA_RELOAD - remaining);
 }
 *last_remaining = remaining;
 return produced_total + advanced;
}
'@ @'
static uint32_t dma_update_producer(uint32_t produced_total,
 uint32_t *last_remaining) {
 uint32_t remaining = DMA11->transfer_count & DMA_COUNT_MASK;
 uint32_t advanced;
 if (remaining <= *last_remaining) {
 advanced = *last_remaining - remaining;
 } else {
 advanced = *last_remaining + (DMA_RELOAD - remaining);
 }
 *last_remaining = remaining;
 return produced_total + advanced;
}

static uint32_t sector_dma_update_producer(uint32_t produced_total,
 uint32_t *last_remaining) {
 uint32_t remaining = DMA10->transfer_count & DMA_COUNT_MASK;
 uint32_t advanced;
 if (remaining <= *last_remaining) {
 advanced = *last_remaining - remaining;
 } else {
 advanced = *last_remaining + (DMA_RELOAD - remaining);
 }
 *last_remaining = remaining;
 return produced_total + advanced;
}
'@ "DMA10 producer tracking"

Replace-Exact $Probe @'
 PIO_CTRL &= ~(1u << 3);
 PIO_CTRL |= (1u << (4 + 3));

 /*
 * PIO slots 26..31:
'@ @'
 PIO_CTRL &= ~((1u << 2) | (1u << 3));
 PIO_CTRL |= (1u << (4 + 2)) | (1u << (4 + 3));

 /*
 * T0.0.0 first read-capture test.
 * PIO0 SM2 uses slots 20..25 and DMA10. It is independent of the
 * hardware-proven SM3/DMA11 write-cycle monitor below.
 *
 * 20 WAIT 1 GPIO8
 * 21 JMP 22 [20]
 * 22 JMP PIN,24 GPIO9 R/W high = read, capture
 * 23 WAIT 0 GPIO8       write cycle: skip capture
 * 24 IN PINS,32         read-cycle snapshot
 * 25 WAIT 0 GPIO8
 */
 PIO_INSTR_MEM(20) = 0x2088u;
 PIO_INSTR_MEM(21) = 0x1416u;
 PIO_INSTR_MEM(22) = 0x00D8u;
 PIO_INSTR_MEM(23) = 0x2008u;
 PIO_INSTR_MEM(24) = 0x4000u;
 PIO_INSTR_MEM(25) = 0x2008u;

 PIO_SM2_CLKDIV = (1u << 16);
 PIO_SM2_EXECCTRL = (25u << 12) | (20u << 7) | (9u << 24);
 PIO_SM2_SHIFTCTRL = (1u << 16);
 PIO_SM2_PINCTRL = 0u;
 PIO_SM2_INSTR = 0x0014u;

 /*
 * PIO slots 26..31:
'@ "SM2 read-cycle PIO program"

Replace-Exact $Probe @'
 DMA11->ctrl_trig = 0u;
'@ @'
 DMA10->ctrl_trig = 0u;
 DMA10->read_addr = (uint32_t)(uintptr_t)&PIO_RXF2;
 DMA10->write_addr = (uint32_t)(uintptr_t)&sector_ring[0];
 DMA10->transfer_count = DMA_TRIGGER_SELF_MAX;
 DMA10->ctrl_trig =
 DMA_EN | DMA_SIZE_32 | DMA_INCR_WRITE |
 DMA_RING_SIZE(10u) | DMA_RING_SEL |
 DMA_CHAIN_TO(DMA_SECTOR_CH) | DMA_TREQ(DREQ_PIO0_RX2) | DMA_IRQ_QUIET;

 DMA11->ctrl_trig = 0u;
'@ "DMA10 setup"

Replace-Exact $Probe @'
 PIO_CTRL |= (1u << 3);
'@ @'
 PIO_CTRL |= (1u << 2) | (1u << 3);
'@ "Enable SM2 and SM3"

Replace-Exact $Probe @'
 uint32_t last_remaining = DMA_RELOAD;
'@ @'
 uint32_t last_remaining = DMA_RELOAD;
 uint32_t sector_consumer_total = 0u;
 uint32_t sector_produced_total = 0u;
 uint32_t sector_last_remaining = DMA_RELOAD;
 uint32_t sector_uc2a_count = 0u;
'@ "Sector test counters"

Replace-Exact $Probe @'
 while (1) {
 produced_total = dma_update_producer(produced_total, &last_remaining);

 m->pio_pc = PIO_SM3_ADDR & 0x1Fu;
'@ @'
 while (1) {
 produced_total = dma_update_producer(produced_total, &last_remaining);
 sector_produced_total = sector_dma_update_producer(sector_produced_total,
 &sector_last_remaining);

 /* Never let the experimental read ring stall the proven monitor loop.
  * If software falls behind, discard old read snapshots and continue.
  */
 if ((sector_produced_total - sector_consumer_total) > SECTOR_RING_WORDS) {
 sector_consumer_total = sector_produced_total - SECTOR_RING_WORDS;
 }

 while (sector_consumer_total != sector_produced_total) {
 uint32_t sidx = sector_consumer_total & SECTOR_RING_MASK;
 uint32_t ss = sector_ring[sidx];
 sector_consumer_total++;

 if (uc2_porta_read(ss)) {
 uint8_t data = logical_data_from_gpio(ss);
 sector_uc2a_count++;

 /* T0.0.0 proof only: emit one sample per 1024 UC2 Port-A reads.
  * Lower 20 bits carry the modulo count; low byte carries raw disk byte.
  */
 if ((sector_uc2a_count & (SECTOR_REPORT_DIV - 1u)) == 0u) {
 queue_event(m,
 (DRIVEHUD_EVENT_UC2A_SAMPLE << 28) |
 ((sector_uc2a_count & 0x000FFFFFu) << 8) |
 (uint32_t)data);
 }
 }

 sector_produced_total = sector_dma_update_producer(sector_produced_total,
 &sector_last_remaining);
 }

 m->pio_pc = PIO_SM3_ADDR & 0x1Fu;
'@ "Consume DMA10 ring"

Replace-Exact $Mailbox @'
#define HUD1541_EVENT_DENSITY 5u
'@ @'
#define HUD1541_EVENT_DENSITY 5u
#define HUD1541_EVENT_UC2A_SAMPLE 6u
'@ "Mailbox event type 6"

Replace-Exact $Compat @'
#define DRIVEHUD_EVENT_DENSITY HUD1541_EVENT_DENSITY
'@ @'
#define DRIVEHUD_EVENT_DENSITY HUD1541_EVENT_DENSITY
#define DRIVEHUD_EVENT_UC2A_SAMPLE HUD1541_EVENT_UC2A_SAMPLE
'@ "Compatibility event alias"

Replace-Exact $Usb @'
 }else if(type==DRIVEHUD_EVENT_DENSITY){
 p=drivehud_append_str(p,e,"DENSITY state=");
 p=drivehud_append_u32(p,e,w&3u);
 p=drivehud_append_str(p,e,"\r\n");
 }else{
'@ @'
 }else if(type==DRIVEHUD_EVENT_DENSITY){
 p=drivehud_append_str(p,e,"DENSITY state=");
 p=drivehud_append_u32(p,e,w&3u);
 p=drivehud_append_str(p,e,"\r\n");
 }else if(type==DRIVEHUD_EVENT_UC2A_SAMPLE){
 uint32_t count=(w>>8)&0x000FFFFFu;
 uint8_t data=(uint8_t)(w&0xFFu);
 p=drivehud_append_str(p,e,"UC2A T0.0.0 count=");
 p=drivehud_append_u32(p,e,count);
 p=drivehud_append_str(p,e," data=$");
 p=drivehud_append_hex8(p,e,data);
 p=drivehud_append_str(p,e,"\r\n");
 }else{
'@ "USB UC2A telemetry"

Write-Host ""
Write-Host "Patch complete. Building T0.0.0..."
& powershell.exe -ExecutionPolicy Bypass -File $Build
if ($LASTEXITCODE -ne 0) { throw "T0.0.0 build failed with exit code $LASTEXITCODE" }

$Uf2 = Join-Path $Repo "build-1541hud/1541HUD_OneROM_T0.0.0.uf2"
$Bin = Join-Path $Repo "build-1541hud/1541HUD_OneROM_T0.0.0.bin"
if (-not (Test-Path $Uf2)) { throw "Build reported success but UF2 is missing: $Uf2" }
if (-not (Test-Path $Bin)) { throw "Build reported success but BIN is missing: $Bin" }

Write-Host ""
Write-Host "FIRST READ-CAPTURE TEST BUILT"
Get-FileHash -Algorithm SHA256 $Bin
Get-FileHash -Algorithm SHA256 $Uf2
Write-Host ""
Write-Host "Expected PuTTY proof records while the drive is reading:"
Write-Host "  UC2A T0.0.0 count=1024 data=`$XX"
Write-Host "  UC2A T0.0.0 count=2048 data=`$XX"
Write-Host ""
Write-Host "This test does NOT yet identify Sector 0. It only proves the isolated SM2/DMA10 UC2 Port-A read path."
