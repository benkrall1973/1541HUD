#!/usr/bin/env python3
"""Build T0.0.32: read the 1541 CPU-visible JiffyDOS address-init bytes."""
from pathlib import Path
import runpy

root = Path(__file__).resolve().parent
# Reuse the proven BASIC V2 tokenizer from T0.0.26 without duplicating it.
tokenizer = root / "Build-1541HUD-T026-SelectorIecReadProof.py"
if not tokenizer.exists():
    raise SystemExit("Missing T0.0.26 tokenizer dependency.")
namespace = runpy.run_path(str(tokenizer))
tokenize = namespace["tokenize"]

source = root / "c64" / "1541-OneROM-Jiffy-Handoff-Proof-T032.bas"
output = root / "build-address-test" / "1541HUD_UB3_T0.0.32_Jiffy_Handoff_Proof.prg"
output.parent.mkdir(parents=True, exist_ok=True)
output.write_bytes(tokenize(source.read_text(encoding="ascii")))
print(f"Built {output}")
print("Read-only: C64 sends 17 M-R commands to device 8 for CPU $EB3A..$EB4A.")
print("Expected JiffyDOS bytes: 173 0 24 41 96 10 42 42 42 9 72 133 120 73 96 133 119")
