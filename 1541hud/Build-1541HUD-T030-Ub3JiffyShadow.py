#!/usr/bin/env python3
"""Create a verified, non-destructive 1541 JiffyDOS address shadow image."""
from argparse import ArgumentParser
from hashlib import sha256
from pathlib import Path

PATCH_OFFSET = 0x0B3A  # CPU address $EB3A in an 8K $E000 image
EXPECTED = bytes.fromhex("AD 00 18 29 60 0A 2A 2A 2A 09 48 85 78 49 60 85 77")
PATCHES = {
    8: bytes.fromhex("A9 00 C9 F0 EA"),
    9: bytes.fromhex("A9 20 C9 D0 EA"),
    10: bytes.fromhex("A9 40 C9 B0 EA"),
    11: bytes.fromhex("A9 60 C9 90 EA"),
}

p = ArgumentParser()
p.add_argument("source", type=Path, help="Pristine 8K JiffyDOS 1541 ROM")
p.add_argument("--address", type=int, choices=PATCHES, required=True)
p.add_argument("--output", type=Path, required=True)
a = p.parse_args()

clean = a.source.read_bytes()
if len(clean) != 8192:
    raise SystemExit("Refusing: source must be exactly 8192 bytes.")
if clean[PATCH_OFFSET:PATCH_OFFSET + len(EXPECTED)] != EXPECTED:
    raise SystemExit("Refusing: $EB3A sequence does not match the verified JiffyDOS/original-ROM address path.")

shadow = bytearray(clean)
shadow[PATCH_OFFSET:PATCH_OFFSET + 5] = PATCHES[a.address]
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_bytes(shadow)

print("T0.0.30 shadow created; source is unchanged.")
print("Source SHA256 :", sha256(clean).hexdigest())
print("Shadow SHA256 :", sha256(shadow).hexdigest())
print("CPU patch     : $EB3A", EXPECTED[:5].hex(" ").upper(), "->", PATCHES[a.address].hex(" ").upper())
print("Target device :", a.address)
print("NOT uploaded, selected, or reset. This file is for later UB3 shadow-slot testing only.")
