# 1541HUD T0.0.16 preserved test artifacts

This directory is the permanent provenance location for the exact T0.0.16 OneROM v0.7.2 UB4 passive-monitor build that passed hardware testing.

Expected files and SHA256 values:

```text
f4486c04893bd17ef7fdcd1b049f33fc3012642ec105ce2403119f0a85f76678  1541HUD_OneROM_T0.0.16_v0.7.2_Baseline.bin
86a6866021903507fb3b03508fc914b2417eaa57880667ebae6e28d554b50445  1541HUD_OneROM_T0.0.16_v0.7.2_Baseline.uf2
443e979675bd1117176c56f9f487ebce075b629a15b0c341a0008cb959493738  1541hud_probe_t016_v072_baseline_SOURCE.c
d3d5c7c0a29d65eef539f94fbaa952045845ef712cbddc623977c97cf353869f  usb_main_t016_1541hud_baseline_SOURCE.c
```

The BIN and UF2 were rebuilt after the builder default toolchain was changed to Arm GNU 15.3.rel1. The rebuilt binaries matched the hardware-tested files byte-for-byte.

Hardware proof is limited to the UB4 passive monitor. It does not establish UB3 active-control/address-switching behavior.
