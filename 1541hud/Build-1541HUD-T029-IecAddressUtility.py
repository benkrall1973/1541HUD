#!/usr/bin/env python3
"""Build T0.0.29 with the Selector project's BASIC V2 tokenizer."""
from pathlib import Path

KEYWORDS = [
    "END","FOR","NEXT","DATA","INPUT#","INPUT","DIM","READ","LET","GOTO","RUN","IF","RESTORE","GOSUB","RETURN","REM","STOP","ON","WAIT","LOAD","SAVE","VERIFY","DEF","POKE","PRINT#","PRINT","CONT","LIST","CLR","CMD","SYS","OPEN","CLOSE","GET","NEW","TAB(","TO","FN","SPC(","THEN","NOT","STEP","+","-","*","/","^","AND","OR",">","=","<","SGN","INT","ABS","USR","FRE","POS","SQR","RND","LOG","EXP","COS","SIN","TAN","ATN","PEEK","LEN","STR$","VAL","ASC","CHR$","LEFT$","RIGHT$","MID$","GO",
]
TOKENS = {word: 0x80 + i for i, word in enumerate(KEYWORDS)}
ORDERED = sorted(TOKENS, key=len, reverse=True)

def tokenize_body(body):
    result = bytearray()
    i = 0
    quoted = data_mode = False
    while i < len(body):
        ch = body[i]
        if quoted:
            result.append(ord(ch)); quoted = ch != '"'; i += 1; continue
        if ch == '"':
            quoted = True; result.append(ord(ch)); i += 1; continue
        if data_mode:
            result.append(ord(ch)); i += 1
            if ch == ":": data_mode = False
            continue
        word = next((w for w in ORDERED if body.startswith(w, i)), None)
        if word is None:
            result.append(ord(ch)); i += 1; continue
        result.append(TOKENS[word]); i += len(word)
        if word == "REM":
            result.extend(body[i:].encode("ascii")); break
        if word == "DATA": data_mode = True
    return result

def tokenize(source):
    out = bytearray((1, 8)); address = 0x0801; previous = -1
    for raw in source.splitlines():
        if not raw: continue
        n, sep, body = raw.partition(" ")
        if not sep or not n.isdigit() or int(n) <= previous:
            raise ValueError(f"Invalid BASIC line: {raw!r}")
        previous = int(n); tokens = tokenize_body(body)
        next_address = address + 5 + len(tokens)
        out.extend((next_address & 255, next_address >> 8, previous & 255, previous >> 8))
        out.extend(tokens); out.append(0); address = next_address
    out.extend((0, 0)); return out

root = Path(__file__).resolve().parent
source = root / "c64" / "1541-OneROM-IEC-Address-Utility-T029.bas"
output = root / "build-address-test" / "1541HUD_UB3_T0.0.29_IEC_Address_Utility.prg"
output.parent.mkdir(parents=True, exist_ok=True)
output.write_bytes(tokenize(source.read_text(encoding="ascii")))
print(f"Built {output}")
print("Interactive temporary address utility: choose current and new addresses from 8 through 11; verifies at the chosen new address.")
