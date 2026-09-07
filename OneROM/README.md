# OneROM foundation used by 1541HUD

This directory contains the OneROM-derived firmware, plugin, tooling, hardware-support, configuration, test and documentation tree used to build 1541HUD.

1541HUD is an independent derivative project. OneROM was created and is maintained by Piers Finlayson. The authoritative upstream project is:

- https://github.com/piersfinlayson/one-rom
- https://onerom.org

The copy retained here is based on OneROM v0.7.1 and includes the integration changes required by 1541HUD. It is kept in-tree so a 1541HUD firmware build can be traced to the exact OneROM foundation that was used.

## 1541HUD integration inside this tree

The most important 1541HUD-specific integration points are:

- `plugins/user/1541hud-probe/` — passive Commodore 1541 acquisition/state-decoding plugin.
- `plugins/system/usb/` — USB/mailbox integration used by the desktop monitor.
- `firmware/src/piodma/pio.c` — passive acquisition integration used by the 1541HUD firmware build.

General OneROM material remains here for provenance and reproducibility. It should not be interpreted as original 1541HUD work.

## Building

The repository-root `Makefile` delegates OneROM targets into this directory. Current 1541HUD PowerShell build entry points are under `../1541hud/` and should be given this directory as their OneROM repository path when using a preserved version-specific builder, for example:

```powershell
.\1541hud\Build-1541HUD-T011.ps1 -Repo .\OneROM
```

The historical experimental construction scripts under `../1541hud/development/experiments/` are preserved for traceability and are not rewritten merely to match this newer repository layout.
