// Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
//
// MIT License

// RP2350 Shared PIO routines

#include "include.h"

#if defined(TEST_BUILD)
#define TEST_PIO_C
#else
#define APIO_LOG_IMPL  1
#endif // TEST_BUILD

#include "piodma/piodma.h"

int pio(void) {
    int rc;

#if defined(HUD1541_PASSIVE_UB4)
    // 1541HUD UB4 passive-monitor mode.  Preserve the hardware-proven V0.0.32
    // safety rule on the clean OneROM v0.7.2 core: do not start the normal ROM
    // serving PIO state machines, because UB4 must never drive the 1541 bus.
    // setup_initial_gpios() has already left the ROM bus GPIOs as inputs.
    return 0;
#endif

    if (0) {
        DEBUG("PIO RAM Mode");
        uint32_t rom_table_addr = (uint32_t)(uintptr_t)RUNTIME->rom_table;
        rc = pioram(INFO, RUNTIME, rom_table_addr);
    } else {
        DEBUG("PIO ROM Mode");
        rc = piorom2();
    }

    return rc;
}

