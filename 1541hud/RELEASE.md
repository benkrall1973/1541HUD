# 1541HUD Release Process

This file is the authoritative release procedure for 1541HUD. The repository root `RELEASE.md` is a short pointer to this document so visitors do not accidentally follow the upstream OneROM publishing process.

## Stable release rules

- `v0.0.30` is the immutable hardware-proven DriveHUD acquisition baseline.
- `v0.0.31` is the current stable 1541HUD rename baseline.
- Released tags are never moved or rewritten.
- Generated BIN/UF2 files are build products and are not committed to the repository.
- Runtime changes require a new version. Documentation-only cleanup does not.
- Experimental `T0.x` builds are never renamed in place to become a stable release.

## Promoting proven T0.x work

When a set of experimental features has survived real-hardware testing and is ready to leave the T0.x line:

1. Keep V0.0.30 and V0.0.31 unchanged as historical/stable checkpoints.
2. Select only the proven T0.x behavior that belongs in the release.
3. Create a **new integrated release-candidate source/build** with one unified version identity.
4. Preserve the original T0.x builders and source files unchanged for provenance.
5. Build the release candidate from its own canonical source and record BIN/UF2 hashes.
6. Hardware-test the exact release-candidate image and matching GUI.
7. Only after that exact integrated build passes should it be promoted to the next stable version, currently expected to be V0.0.32.

Do not merge experimental source directly into the historical V0.0.30 tag or relabel an already-tested T0.x binary as V0.0.32. The release candidate must be a separately reproducible artifact.

## Before tagging a new 1541HUD release

1. Update `1541hud/CHANGELOG.md` with the exact tag version.
2. Update source/build filenames and displayed version strings only when the runtime version changes.
3. Run the canonical PowerShell build and record its output/hashes for the release notes or handoff.
4. Confirm `1541HUD Sanity` passes.
5. Confirm any relevant OneROM base CI checks pass.
6. Verify the exact image on real Commodore 1541 hardware when the release changes acquisition, decoding, mailbox behavior, USB transport, RPM/SYNC handling, or other runtime behavior.
7. Verify the matching GUI against the exact release-candidate firmware.
8. Tag the exact tested commit and push the tag.

The `.github/workflows/release.yml` workflow creates the GitHub release from the matching section in `1541hud/CHANGELOG.md`.

## Upstream OneROM

1541HUD is based on OneROM v0.7.1. Upstream updates should be reviewed and integrated deliberately. Do not automatically merge upstream changes into a stable 1541HUD release line.
