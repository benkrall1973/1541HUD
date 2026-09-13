/* 1541HUD T0.0.19 OneROM v0.7.2 EVENT LOG EXPERIMENT.
 * Isolated copy of T0.0.18: native application log records are emitted only
 * on observed motor, DOS-track, and HOME-anchor changes. The mailbox path is
 * unchanged.
 */
/* 1541HUD T0.0.16 OneROM v0.7.2 BASELINE PORT.
 * Monitor behavior is intentionally preserved from hardware-proven V0.0.32.
 * Only the OneROM baseline/minimum firmware identity changes in this test.
 */
/*
 * DriveHUD UB4 passive monitor V0.0.30
 *
 * Data path:
 * 1541 write cycles
 * -> PIO0 SM3 deterministic sampling
 * -> DMA11 circular ring
 * -> bus-event decoder
 * -> compact mailbox queue
 * -> USB CDC formatter
 * -> DriveHUD GUI
 *
 * The monitor is passive. It never drives the 1541 bus.
 *
 * Current decoded state:
 * - physical stepper phase and half-track movement
 * - spindle motor state
 * - HOME anchor from DOS track state
 * - write-protect state from DOS RAM
 * - actual hardware density selection D0-D3 from VIA2 PB5/PB6 writes
 */

#include "plugin.h"
#include "drivehud_mailbox.h"

ORA_DEFINE_USER_PLUGIN(drivehud_probe_main, 0,0,19,0, 0,7,2);

static const char t019_log_name[] = "1541HUD";
static const char t019_motor_on[] = "1541HUD T0.0.19 EVENT MOTOR=1\r\n";
static const char t019_motor_off[] = "1541HUD T0.0.19 EVENT MOTOR=0\r\n";
static const char t019_home[] = "1541HUD T0.0.19 EVENT HOME=1\r\n";

static uint32_t t019_track_record(char *out, uint8_t track) {
 static const char prefix[] = "1541HUD T0.0.19 EVENT TRACK=";
 uint32_t i = 0u;
 uint8_t tens = (uint8_t)(track / 10u);
 uint8_t ones = (uint8_t)(track % 10u);
 for (i = 0u; i < (uint32_t)(sizeof(prefix) - 1u); ++i) out[i] = prefix[i];
 if (tens != 0u) out[i++] = (char)('0' + tens);
 out[i++] = (char)('0' + ones);
 out[i++] = '\r';
 out[i++] = '\n';
 return i;
}

#define RESETS_BASE 0x40020000u
#define RESET_RESET (*(volatile uint32_t *)(RESETS_BASE + 0x00u))
#define RESET_DONE (*(volatile uint32_t *)(RESETS_BASE + 0x08u))
#define RESET_DMA (1u << 2)
#define RESET_PIO0 (1u << 11)

#define TIMER0_BASE 0x400B0000u
#define TIMER0_RAWL (*(volatile uint32_t *)(TIMER0_BASE + 0x28u))

/* T0.0.16 baseline: former CS1 GPIO24 remains the proven passive physical SYNC input. */
#define SIO_BASE 0xD0000000u
#define SIO_GPIO_IN (*(volatile uint32_t *)(SIO_BASE + 0x004u))
#define MASK_SYNC (1u << 24)
#define DRIVEHUD_EVENT_SYNC_DIAG 8u
#define PIO0_BASE 0x50200000u
#define PIO_CTRL (*(volatile uint32_t *)(PIO0_BASE + 0x000u))
#define PIO_FLEVEL (*(volatile uint32_t *)(PIO0_BASE + 0x00Cu))
#define PIO_RXF3 (*(volatile uint32_t *)(PIO0_BASE + 0x02Cu))
#define PIO_INSTR_MEM(n) (*(volatile uint32_t *)(PIO0_BASE + 0x048u + ((n) * 4u)))
#define PIO_SM3_CLKDIV (*(volatile uint32_t *)(PIO0_BASE + 0x110u))
#define PIO_SM3_EXECCTRL (*(volatile uint32_t *)(PIO0_BASE + 0x114u))
#define PIO_SM3_SHIFTCTRL (*(volatile uint32_t *)(PIO0_BASE + 0x118u))
#define PIO_SM3_ADDR (*(volatile uint32_t *)(PIO0_BASE + 0x11Cu))
#define PIO_SM3_INSTR (*(volatile uint32_t *)(PIO0_BASE + 0x120u))
#define PIO_SM3_PINCTRL (*(volatile uint32_t *)(PIO0_BASE + 0x124u))

#define DMA_BASE 0x50000000u
#define DMA_CH 11u

typedef struct {
 volatile uint32_t read_addr;
 volatile uint32_t write_addr;
 volatile uint32_t transfer_count;
 volatile uint32_t ctrl_trig;
} dma_ch_t;

#define DMA11 ((dma_ch_t *)(DMA_BASE + DMA_CH * 0x40u))

#define DMA_EN (1u << 0)
#define DMA_SIZE_32 (2u << 2)
#define DMA_INCR_WRITE (1u << 6)
#define DMA_RING_SIZE(n) (((n) & 0xFu) << 8)
#define DMA_RING_SEL (1u << 12)
#define DMA_CHAIN_TO(x) (((x) & 0xFu) << 13)
#define DMA_TREQ(x) (((x) & 0x3Fu) << 17)
#define DMA_IRQ_QUIET (1u << 23)
#define DMA_BUSY (1u << 24)
#define DREQ_PIO0_RX3 7u

/* Hardware-proven decode: GPIO24 is SYNC, UC2 selection uses /CS2 only. */
#define MASK_nCS2 (1u << 25)

#define DMA_COUNT_MASK 0x0fffffffu
#define DMA_RELOAD 0x0fffffffu
#define DMA_TRIGGER_SELF_MAX 0x1fffffffu

#define RAM_LWPT 0x001Eu
#define RAM_HDRID2 0x0016u
#define RAM_HDRID1 0x0017u
#define RAM_HDRTRK 0x0018u
#define RAM_HDRSEC 0x0019u
#define RAM_HDRCHK 0x001Au
#define RAM_DRVST 0x0020u
#define RAM_DRVTRK 0x0022u

#define TRACK_STATE_LAST_TRACK_MASK 0x000000FFu
#define TRACK_STATE_TRACK_WRITE_VALID (1u << 8)
#define TRACK_STATE_POS2_SHIFT 16u
#define TRACK_STATE_POS2_MASK (0xFFu << TRACK_STATE_POS2_SHIFT)
#define TRACK_STATE_POS_VALID (1u << 24)
#define TRACK_STATE_STEPPING (1u << 25)

static uint8_t logical_data_from_gpio(uint32_t v) {
 return (uint8_t)((((v >> 7) & 1u) << 0) |
 (((v >> 6) & 1u) << 1) |
 (((v >> 5) & 1u) << 2) |
 (((v >> 0) & 1u) << 3) |
 (((v >> 1) & 1u) << 4) |
 (((v >> 2) & 1u) << 5) |
 (((v >> 3) & 1u) << 6) |
 (((v >> 4) & 1u) << 7));
}

static uint32_t logical_addr13_from_gpio(uint32_t v) {
 return (((v >> 23) & 1u) << 0) |
 (((v >> 22) & 1u) << 1) |
 (((v >> 21) & 1u) << 2) |
 (((v >> 20) & 1u) << 3) |
 (((v >> 19) & 1u) << 4) |
 (((v >> 18) & 1u) << 5) |
 (((v >> 17) & 1u) << 6) |
 (((v >> 16) & 1u) << 7) |
 (((v >> 15) & 1u) << 8) |
 (((v >> 14) & 1u) << 9) |
 (((v >> 13) & 1u) << 10) |
 (((v >> 11) & 1u) << 11) |
 (((v >> 12) & 1u) << 12);
}

static uint8_t uc2_selected(uint32_t v) {
 /* Hardware-proven T0.0.14 result: CS1 is not required for current decode. */
 return (uint8_t)((v & MASK_nCS2) == 0u);
}

static uint8_t uc2_orb_write(uint32_t v) {
 return (uint8_t)(uc2_selected(v) &&
 ((logical_addr13_from_gpio(v) & 0x0Fu) == 0u));
}

static uint8_t ram_write_at(uint32_t v, uint32_t addr) {
 return (uint8_t)(!uc2_selected(v) &&
 (logical_addr13_from_gpio(v) == addr));
}

static uint8_t all_bus_gpios_are_inputs(ora_gpio_query_fn_t q) {
 static const uint8_t pins[] = {
 0,1,2,3,4,5,6,7,8,9,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25
 };
 uint32_t i;
 for (i = 0; i < (uint32_t)sizeof(pins); ++i) {
 ora_gpio_info_t info;
 info.size = sizeof(info);
 if (q(pins[i], &info) != ORA_RESULT_OK || info.is_output) return 0u;
 }
 return 1u;
}

static void queue_event(volatile drivehud_mailbox_t *m, uint32_t word) {
 uint32_t head = m->event_head;
 uint32_t next = (head + 1u) % DRIVEHUD_EVENT_WORDS;
 if (next == m->event_tail) {
 m->event_overflow++;
 m->flags |= DRIVEHUD_FLAG_EVENT_OVERFLOW;
 return;
 }
 m->events[head] = word;
 __asm volatile("dmb sy" ::: "memory");
 m->event_head = next;
}

static void queue_motor(volatile drivehud_mailbox_t *m, uint8_t state) {
 queue_event(m, (DRIVEHUD_EVENT_MOTOR << 28) | (uint32_t)(state & 1u));
}

static void queue_phase(volatile drivehud_mailbox_t *m,
 uint8_t oldp, uint8_t newp,
 uint8_t delta, uint8_t motor_snapshot) {
 queue_event(m,
 (DRIVEHUD_EVENT_PHASE << 28) |
 ((uint32_t)(oldp & 3u) << 0) |
 ((uint32_t)(newp & 3u) << 2) |
 ((uint32_t)(delta & 3u) << 4) |
 ((uint32_t)(motor_snapshot & 1u) << 6));
}

static void queue_track_write(volatile drivehud_mailbox_t *m, uint8_t track) {
 queue_event(m, (DRIVEHUD_EVENT_TRACK_WRITE << 28) | (uint32_t)track);
}

static void queue_write_protect(volatile drivehud_mailbox_t *m, uint8_t state) {
 queue_event(m, (DRIVEHUD_EVENT_WRITE_PROTECT << 28) | (uint32_t)(state & 1u));
}

static void queue_density(volatile drivehud_mailbox_t *m, uint8_t density) {
 queue_event(m, (DRIVEHUD_EVENT_DENSITY << 28) | (uint32_t)(density & 3u));
}

/* T0.0.11 diagnostic payloads:
 * HDRPHY type 6:
 *   27..21 decoded physical track
 *   20..16 decoded sector
 *   15..0  timestamp / 16 us
 *
 * RPM type 7:
 *   27..21 physical track
 *   20..16 inferred revolution count (1..4)
 *   15..0  RPM * 100
 */
static void queue_hdrphy_diag(volatile drivehud_mailbox_t *m,
 uint8_t track, uint8_t sector, uint16_t ticks16) {
 queue_event(m,
  (DRIVEHUD_EVENT_HDRPHY_DIAG << 28) |
  ((uint32_t)(track & 0x7Fu) << 21) |
  ((uint32_t)(sector & 0x1Fu) << 16) |
  (uint32_t)ticks16);
}

static void queue_rpm_diag(volatile drivehud_mailbox_t *m,
 uint8_t track, uint8_t revolutions, uint16_t rpm100) {
 queue_event(m,
  (DRIVEHUD_EVENT_RPM_DIAG << 28) |
  ((uint32_t)(track & 0x7Fu) << 21) |
  ((uint32_t)(revolutions & 0x1Fu) << 16) |
  (uint32_t)rpm100);
}

/* Count one event per asserted SYNC pulse by watching the high->low edge.
 * Report the raw edge count once per second. This preserves the hardware-proven
 * V0.0.32 SYNC behavior without altering HDRPHY/RPM.
 */
static void sync_poll(volatile drivehud_mailbox_t *m,
 uint8_t *last_level, uint32_t *count, uint32_t *next_report_us) {
 uint8_t level = (SIO_GPIO_IN & MASK_SYNC) ? 1u : 0u;
 uint32_t now = TIMER0_RAWL;

 if (*last_level && !level) (*count)++;
 *last_level = level;

 if ((int32_t)(now - *next_report_us) >= 0) {
  uint32_t packed = (DRIVEHUD_EVENT_SYNC_DIAG << 28) |
                    ((uint32_t)(level & 1u) << 27) |
                    (*count & 0x07FFFFFFu);
  queue_event(m, packed);
  *count = 0u;
  *next_report_us = now + 1000000u;
 }
}

static void publish_track_state(volatile drivehud_mailbox_t *m,
 uint8_t last_track, uint8_t track_write_valid,
 uint8_t pos2, uint8_t pos_valid,
 uint8_t stepping) {
 uint32_t s = (uint32_t)last_track;
 if (track_write_valid) s |= TRACK_STATE_TRACK_WRITE_VALID;
 s |= ((uint32_t)pos2 << TRACK_STATE_POS2_SHIFT) & TRACK_STATE_POS2_MASK;
 if (pos_valid) s |= TRACK_STATE_POS_VALID;
 if (stepping) s |= TRACK_STATE_STEPPING;
 m->track_state = s;
}

static uint8_t clamp_pos2_in(uint8_t pos2) {
 /* No artificial Track-41 ceiling. Only prevent uint8 wrap. */
 return (pos2 < 254u) ? (uint8_t)(pos2 + 1u) : pos2;
}

static uint8_t clamp_pos2_out(uint8_t pos2) {
 return (pos2 > 2u) ? (uint8_t)(pos2 - 1u) : 2u;
}

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

static void update_ring_health(volatile drivehud_mailbox_t *m,
 uint32_t produced_total,
 uint32_t *consumer_total) {
 uint32_t available = produced_total - *consumer_total;
 if (available > DRIVEHUD_RING_WORDS) {
 uint32_t lost = available - DRIVEHUD_RING_WORDS;
 m->ring_overrun += lost;
 m->ring_pressure++;
 m->flags |= DRIVEHUD_FLAG_RING_PRESSURE | DRIVEHUD_FLAG_RING_OVERRUN;
 *consumer_total = produced_total - DRIVEHUD_RING_WORDS;
 m->consumer_total = *consumer_total;
 } else if (available >= 48u) {
 m->ring_pressure++;
 m->flags |= DRIVEHUD_FLAG_RING_PRESSURE;
 }
}

static void pio_dma_init(volatile drivehud_mailbox_t *m) {
 RESET_RESET &= ~(RESET_PIO0 | RESET_DMA);
 while ((RESET_DONE & (RESET_PIO0 | RESET_DMA)) !=
 (RESET_PIO0 | RESET_DMA)) {}

 PIO_CTRL &= ~(1u << 3);
 PIO_CTRL |= (1u << (4 + 3));

 /*
 * PIO slots 26..31:
 * 26 WAIT 1 GPIO8
 * 27 JMP 28 [20]
 * 28 JMP PIN,31 GPIO9 R/W high = read, skip capture
 * 29 IN PINS,32 snapshot write cycle
 * 30 WAIT 0 GPIO8
 * 31 WAIT 0 GPIO8
 *
 * The sampling point is hardware-validated. Do not retune casually.
 */
 PIO_INSTR_MEM(26) = 0x2088u;
 PIO_INSTR_MEM(27) = 0x141Cu;
 PIO_INSTR_MEM(28) = 0x00DFu;
 PIO_INSTR_MEM(29) = 0x4000u;
 PIO_INSTR_MEM(30) = 0x2008u;
 PIO_INSTR_MEM(31) = 0x2008u;

 PIO_SM3_CLKDIV = (1u << 16);
 PIO_SM3_EXECCTRL = (31u << 12) | (26u << 7) | (9u << 24);
 PIO_SM3_SHIFTCTRL = (1u << 16);
 PIO_SM3_PINCTRL = 0u;
 PIO_SM3_INSTR = 0x001Au;

 DMA11->ctrl_trig = 0u;
 DMA11->read_addr = (uint32_t)(uintptr_t)&PIO_RXF3;
 DMA11->write_addr = (uint32_t)(uintptr_t)&m->ring[0];
 DMA11->transfer_count = DMA_TRIGGER_SELF_MAX;
 DMA11->ctrl_trig =
 DMA_EN | DMA_SIZE_32 | DMA_INCR_WRITE |
 DMA_RING_SIZE(8u) | DMA_RING_SEL |
 DMA_CHAIN_TO(DMA_CH) | DMA_TREQ(DREQ_PIO0_RX3) | DMA_IRQ_QUIET;

 PIO_CTRL |= (1u << 3);
 m->flags |= DRIVEHUD_FLAG_PIO_RUNNING | DRIVEHUD_FLAG_DMA_RUNNING;
}

static void decode_snapshot(volatile drivehud_mailbox_t *m,
 uint32_t snapshot,
 uint8_t *phase_valid, uint8_t *last_phase,
 uint8_t *motor_valid, uint8_t *last_motor,
 uint8_t *wp_valid, uint8_t *last_wp,
 uint8_t *density_valid, uint8_t *last_density,
 uint8_t *track_write_valid, uint8_t *last_track_write,
 uint8_t *pos_valid, uint8_t *current_pos2,
 uint8_t *last_drvst, uint8_t *stepping,
 uint8_t *hdr_state, uint8_t *hdr_track, uint8_t *hdr_sector,
 uint16_t *hdr_ticks16,
 volatile uint8_t *rpm_seen, volatile uint16_t *rpm_ticks) {
 if (uc2_orb_write(snapshot)) {
 uint8_t orb = logical_data_from_gpio(snapshot);
 uint8_t motor = (uint8_t)((orb >> 2) & 1u);
 uint8_t phase = (uint8_t)(orb & 3u);
 uint8_t density = (uint8_t)((orb >> 5) & 3u);

 m->last_orb = orb;
 m->last_phase = phase;
 m->last_motor = motor;
 m->last_density = density;

 if (!*motor_valid) {
 *motor_valid = 1u;
 *last_motor = motor;
 queue_motor(m, motor);
 } else if (motor != *last_motor) {
 *last_motor = motor;
 queue_motor(m, motor);

 if (!motor) {
  uint32_t rpm_i;
  for (rpm_i = 0u; rpm_i < 32u; ++rpm_i) rpm_seen[rpm_i] = 0u;
 }
 }

 if (!*phase_valid) {
 *phase_valid = 1u;
 *last_phase = phase;
 } else if (phase != *last_phase) {
 uint8_t oldp = *last_phase;
 uint8_t delta = (uint8_t)((phase - oldp) & 3u);

 {
  uint32_t rpm_i;
  for (rpm_i = 0u; rpm_i < 32u; ++rpm_i) rpm_seen[rpm_i] = 0u;
 }
 *last_phase = phase;
 m->phase_event_count++;
 queue_phase(m, oldp, phase, delta, motor);

 /* Mirror the proven GUI half-step arithmetic in RP2350 SRAM.
  * This is background decode only; PIO/DMA acquisition is untouched.
  */
 if (*pos_valid) {
 if (delta == 1u) {
 *current_pos2 = clamp_pos2_in(*current_pos2);
 } else if (delta == 3u) {
 *current_pos2 = clamp_pos2_out(*current_pos2);
 }
 publish_track_state(m, *last_track_write, *track_write_valid,
 *current_pos2, *pos_valid, *stepping);
 }
 }

 /*
 * VIA2 PB5/PB6 are the drive's actual density-select outputs.
 * This reports the commanded hardware density, independent of track.
 */
 if (!*density_valid) {
 *density_valid = 1u;
 *last_density = density;
 m->density_valid = 1u;
 m->density_event_count++;
 queue_density(m, density);
 } else if (density != *last_density) {
 *last_density = density;
 m->density_event_count++;
 queue_density(m, density);
 }
 }
 /* Physical-header recognition for RPM.
  *
  * The 1541 ROM uses two different RAM write orders:
  *
  *   Actual decoded disk header:
  *     $18 -> $19 -> $1A -> $17 -> $16
  *
  *   DOS pre-search header image:
  *     $16 -> $17 -> $18 -> $19 -> $1A
  *
  * Only the first sequence represents a header actually decoded from
  * the rotating disk.  Timestamp $19, then wait for $1A/$17/$16 to
  * confirm the complete physical-header sequence before using it.
  */
 if (ram_write_at(snapshot, RAM_HDRTRK)) {
  *hdr_track = logical_data_from_gpio(snapshot);
  *hdr_state = 1u;
 } else if (ram_write_at(snapshot, RAM_HDRSEC)) {
  if (*hdr_state == 1u) {
   *hdr_sector = logical_data_from_gpio(snapshot);
   *hdr_ticks16 = (uint16_t)((TIMER0_RAWL >> 4) & 0xFFFFu);
   *hdr_state = 2u;
  } else {
   *hdr_state = 0u;
  }
 } else if (ram_write_at(snapshot, RAM_HDRCHK)) {
  *hdr_state = (*hdr_state == 2u) ? 3u : 0u;
 } else if (ram_write_at(snapshot, RAM_HDRID1)) {
  *hdr_state = (*hdr_state == 3u) ? 4u : 0u;
 } else if (ram_write_at(snapshot, RAM_HDRID2)) {
  if (*hdr_state == 4u &&
      *hdr_track >= 1u && *hdr_track <= 127u &&
      *hdr_sector <= 31u) {
   uint8_t sec = *hdr_sector;
   uint16_t now = *hdr_ticks16;
   queue_hdrphy_diag(m, *hdr_track, sec, now);

   if (rpm_seen[sec]) {
    uint16_t dt = (uint16_t)(now - rpm_ticks[sec]);

    /* 16 us timer ticks. At 300 RPM one revolution is ~12,500 ticks.
     * Infer 1..4 revolutions by nearest integer multiple, then require
     * the resulting speed to be plausible for a 1541.
     *
     * RPM*100 = 60,000,000*100*revs / (dt*16)
     *         = 375,000,000*revs / dt
     */
    if (dt >= 10000u) {
     uint32_t revs = ((uint32_t)dt + 6250u) / 12500u;
     if (revs >= 1u && revs <= 4u) {
      uint32_t rpm100 =
       ((375000000u * revs) + ((uint32_t)dt / 2u)) / (uint32_t)dt;

      if (rpm100 >= 28000u && rpm100 <= 32000u) {
       queue_rpm_diag(m, *hdr_track, (uint8_t)revs, (uint16_t)rpm100);
      }
     }
    }
   }

   rpm_seen[sec] = 1u;
   rpm_ticks[sec] = now;
  }
  *hdr_state = 0u;
 }


 if (ram_write_at(snapshot, RAM_DRVST)) {
 uint8_t data = logical_data_from_gpio(snapshot);
 uint8_t was_stepping = *stepping;
 *last_drvst = data;
 *stepping = (uint8_t)((data & 0x40u) ? 1u : 0u);
 m->last_drvst = data;

 /* Stock DOS writes destination DRVTRK before a seek, then clears DRVST
  * bit 6 after the head-settle phase. At that exact transition the cached
  * DRVTRK is again the physical full-track location.
  */
 if (was_stepping && !*stepping && *track_write_valid &&
 *last_track_write >= 1u && *last_track_write <= 127u) {
 uint32_t p2 = (uint32_t)(*last_track_write) * 2u;
 *current_pos2 = (uint8_t)((p2 > 254u) ? 254u : p2);
 *pos_valid = 1u;
 }

 publish_track_state(m, *last_track_write, *track_write_valid,
 *current_pos2, *pos_valid, *stepping);
 }

 if (ram_write_at(snapshot, RAM_DRVTRK)) {
 uint8_t data = logical_data_from_gpio(snapshot);

 /* DOS $0022 (DRVTRK) is the full-track target/current-track variable.
  * Keep the last value, and continue publishing the V28 event unchanged.
  */
 *last_track_write = data;
 *track_write_valid = 1u;
 queue_track_write(m, data);

 if (data == 1u) {
 /* Strong HOME/bump anchor. Subsequent outward bump steps are clamped at 1.0. */
 *current_pos2 = 2u;
 *pos_valid = 1u;
 m->home_count++;
 } else if (!*pos_valid && !*stepping && data >= 1u && data <= 127u) {
 /* If DOS supplies a track while not stepping, it is safe as the initial
  * full-track anchor. During normal seeks DRVST bit 6 is already set first.
  */
 uint32_t p2 = (uint32_t)data * 2u;
 *current_pos2 = (uint8_t)((p2 > 254u) ? 254u : p2);
 *pos_valid = 1u;
 }

 publish_track_state(m, *last_track_write, *track_write_valid,
 *current_pos2, *pos_valid, *stepping);
 }

 if (ram_write_at(snapshot, RAM_LWPT)) {
 uint8_t data = logical_data_from_gpio(snapshot);
 uint8_t wp = (uint8_t)((data & 0x10u) ? 1u : 0u);
 m->last_write_protect = wp;

 if (!*wp_valid) {
 *wp_valid = 1u;
 *last_wp = wp;
 m->write_protect_valid = 1u;
 m->write_protect_event_count++;
 queue_write_protect(m, wp);
 } else if (wp != *last_wp) {
 *last_wp = wp;
 m->write_protect_event_count++;
 queue_write_protect(m, wp);
 }
 }
}

void drivehud_probe_main(ora_lookup_fn_t lookup,
 ora_plugin_type_t type,
 const ora_entry_args_t *args) {
 ora_gpio_query_fn_t gpio_query;
 volatile drivehud_mailbox_t *m = DRIVEHUD_MAILBOX;
 uint32_t i;
 uint32_t consumer_total = 0u;
 uint32_t produced_total = 0u;
 uint32_t last_remaining = DMA_RELOAD;
 ora_log_open_write_fn_t t019_log_open;
 ora_log_write_fn_t t019_log_write;
 uint8_t t019_log_ready = 0u;
 uint8_t t019_motor_valid = 0u, t019_last_motor = 0u;
 uint8_t t019_track_valid = 0u, t019_last_track = 0u;
 uint32_t t019_last_home_count = 0u;
 uint32_t t019_next_log_us;
 char t019_track_line[40];
 uint8_t phase_valid = 0u, motor_valid = 0u, wp_valid = 0u, density_valid = 0u;
 uint8_t last_phase = 0u, last_motor = 0u, last_wp = 0u, last_density = 2u;
 uint8_t track_write_valid = 0u, last_track_write = 0u;
 uint8_t pos_valid = 0u, current_pos2 = 0u;
 uint8_t last_drvst = 0u, stepping = 0u;
 uint8_t sync_last_level = (SIO_GPIO_IN & MASK_SYNC) ? 1u : 0u;
 uint32_t sync_count = 0u;
 uint32_t sync_next_report_us = TIMER0_RAWL + 1000000u;

 /* Physical-header/RPM state is deliberately local to the plugin main
  * routine. Do not move these arrays to static/global storage: the USER
  * plugin has fixed RAM allocations and unallocated .bss state previously
  * corrupted the 1541HUD mailbox during T0.0.6.
  *
  * The history arrays are volatile intentionally. This is a freestanding
  * plugin with no libc; without volatile, GCC may optimize initialization
  * or clear loops into an unresolved memset() call, as seen during T0.0.11
  * development.
  */
 uint8_t hdr_state = 0u, hdr_track = 0u, hdr_sector = 0u;
 uint16_t hdr_ticks16 = 0u;
 volatile uint8_t rpm_seen[32];
 volatile uint16_t rpm_ticks[32];
 {
  uint32_t rpm_i;
  for (rpm_i = 0u; rpm_i < 32u; ++rpm_i) {
   rpm_seen[rpm_i] = 0u;
   rpm_ticks[rpm_i] = 0u;
  }
 }
 (void)args;
 gpio_query = (ora_gpio_query_fn_t)lookup(ORA_ID_GPIO_QUERY);

 m->magic = DRIVEHUD_MAILBOX_MAGIC;
 m->version = DRIVEHUD_MAILBOX_VERSION;
 m->flags = 0u;
 m->capture_count = 0u;
 m->consumed_count = 0u;
 m->event_head = 0u;
 m->event_tail = 0u;
 m->event_overflow = 0u;
 m->ring_pressure = 0u;
 m->last_orb = 0u;
 m->last_phase = 0u;
 m->last_motor = 0u;
 m->home_count = 0u;
 m->pio_pc = 0u;
 m->rx_level = 0u;
 m->dma_write_addr = 0u;
 m->consumer_index = 0u;
 m->producer_index = 0u;
 m->dma_busy = 0u;
 m->dma_trans_count = 0u;
 m->produced_total = 0u;
 m->consumer_total = 0u;
 m->ring_overrun = 0u;
 m->phase_event_count = 0u;
 m->last_write_protect = 0u;
 m->write_protect_event_count = 0u;
 m->write_protect_valid = 0u;
 m->last_density = 2u; /* GUI/firmware startup assumption: Track 18 => D2 */
 m->density_event_count = 0u;
 m->density_valid = 0u;
 m->track_state = 0u;
 m->last_drvst = 0u;

 for (i = 0u; i < DRIVEHUD_EVENT_WORDS; ++i) m->events[i] = 0u;
 for (i = 0u; i < DRIVEHUD_RING_WORDS; ++i) m->ring[i] = 0u;

 if (type != ORA_PLUGIN_TYPE_USER ||
 gpio_query == 0 ||
 !all_bus_gpios_are_inputs(gpio_query)) {
 m->flags = DRIVEHUD_FLAG_UNSAFE_OUTPUT;
 while (1) __asm volatile("wfi");
 }

 m->flags = DRIVEHUD_FLAG_INPUTS_SAFE;
 pio_dma_init(m);

 /* Log failure must never stop the passive monitor. Keep new state local
  * to this entry point; the plugin's .bss overlaps reserved mailbox RAM. */
 t019_log_open = (ora_log_open_write_fn_t)lookup(ORA_ID_LOG_OPEN_WRITE);
 t019_log_write = (ora_log_write_fn_t)lookup(ORA_ID_LOG_WRITE);
 if (t019_log_open != 0 && t019_log_write != 0 &&
     t019_log_open(ORA_LOG_CHANNEL_0, t019_log_name) == ORA_RESULT_OK) {
  t019_log_ready = 1u;
 }
 t019_next_log_us = TIMER0_RAWL + 1000000u;

 while (1) {
 sync_poll(m, &sync_last_level, &sync_count, &sync_next_report_us);
 produced_total = dma_update_producer(produced_total, &last_remaining);

 m->pio_pc = PIO_SM3_ADDR & 0x1Fu;
 m->rx_level = (PIO_FLEVEL >> 28) & 0xFu;
 m->dma_write_addr = DMA11->write_addr;
 m->consumer_index = consumer_total & (DRIVEHUD_RING_WORDS - 1u);
 m->producer_index = produced_total & (DRIVEHUD_RING_WORDS - 1u);
 m->dma_busy = (DMA11->ctrl_trig & DMA_BUSY) ? 1u : 0u;
 m->dma_trans_count = DMA11->transfer_count;
 m->produced_total = produced_total;
 m->consumer_total = consumer_total;

 update_ring_health(m, produced_total, &consumer_total);

 while (consumer_total != produced_total) {
 sync_poll(m, &sync_last_level, &sync_count, &sync_next_report_us);
 uint32_t idx = consumer_total & (DRIVEHUD_RING_WORDS - 1u);
 uint32_t snapshot = m->ring[idx];

 consumer_total++;
 m->capture_count++;
 m->consumed_count++;
 m->consumer_total = consumer_total;
 m->flags |= DRIVEHUD_FLAG_CAPTURE_VALID;

 decode_snapshot(m, snapshot,
 &phase_valid, &last_phase,
 &motor_valid, &last_motor,
 &wp_valid, &last_wp,
 &density_valid, &last_density,
 &track_write_valid, &last_track_write,
 &pos_valid, &current_pos2,
 &last_drvst, &stepping,
 &hdr_state, &hdr_track, &hdr_sector, &hdr_ticks16,
 rpm_seen, rpm_ticks);

 produced_total = dma_update_producer(produced_total, &last_remaining);
 m->produced_total = produced_total;
 update_ring_health(m, produced_total, &consumer_total);
 }

 /* Event-only, nonblocking native log. Values are compared after draining
  * samples; full/unavailable log channels are ignored with no retry. */
 if (t019_log_ready && (int32_t)(TIMER0_RAWL - t019_next_log_us) >= 0) {
  t019_next_log_us = TIMER0_RAWL + 1000000u;
  if (!t019_motor_valid || m->last_motor != t019_last_motor) {
   t019_motor_valid = 1u;
   t019_last_motor = m->last_motor;
   (void)t019_log_write(ORA_LOG_CHANNEL_0,
    (m->last_motor != 0u) ? t019_motor_on : t019_motor_off,
    (m->last_motor != 0u) ? (uint32_t)(sizeof(t019_motor_on) - 1u)
                         : (uint32_t)(sizeof(t019_motor_off) - 1u));
  }
  if (track_write_valid && last_track_write >= 1u && last_track_write <= 35u &&
      (!t019_track_valid || last_track_write != t019_last_track)) {
   uint32_t len;
   t019_track_valid = 1u;
   t019_last_track = last_track_write;
   len = t019_track_record(t019_track_line, last_track_write);
   (void)t019_log_write(ORA_LOG_CHANNEL_0, t019_track_line, len);
  }
  if (m->home_count != t019_last_home_count) {
   t019_last_home_count = m->home_count;
   (void)t019_log_write(ORA_LOG_CHANNEL_0, t019_home,
                         (uint32_t)(sizeof(t019_home) - 1u));
  }
 }
 }
}
