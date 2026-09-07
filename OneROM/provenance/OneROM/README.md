# Upstream OneROM Material

This directory contains material retained from the upstream **OneROM** project for provenance, attribution, and reproducibility.

OneROM was created and is maintained by **Piers Finlayson**:

- https://onerom.org
- https://github.com/piersfinlayson/one-rom

1541HUD is an independent derivative project based on OneROM v0.7.1. It uses the OneROM Fire-24-E hardware, RP2350 firmware architecture, plugin system, firmware composition process, and supporting tooling as its foundation.

The files placed under this directory are upstream OneROM material that does not need to remain at the repository root for the current 1541HUD development workflow.

Some build-critical OneROM directories remain at the repository root, including `firmware/`, `plugins/`, `onerom-config/`, `rust/`, and the top-level `Makefile`. Those paths are intentionally left in place because current 1541HUD build scripts and OneROM build tooling expect the established layout. Moving them would require a separate build-system refactor and hardware revalidation.

Upstream documentation currently preserved here includes:

- `documentation/CHANGELOG.md`
- `documentation/CLAUDE.md`
- `documentation/INSTALL.md`

No upstream authorship is claimed for these files. Their relocation is organizational only; their content and Git history are retained.
