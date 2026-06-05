#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys
import tempfile

from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM


PREFIX = "[arm64-jit-dump] "


def run_cmd(cmd, cwd=None):
    return subprocess.check_output(cmd, cwd=cwd, text=True)


def parse_dump_lines(path):
    records = []
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            if not line.startswith(PREFIX):
                continue
            records.append(json.loads(line[len(PREFIX):]))
    return records


def disassemble_words(words):
    with tempfile.TemporaryDirectory(prefix="jitdump-host-") as td:
        asm = os.path.join(td, "frag.s")
        obj = os.path.join(td, "frag.o")
        with open(asm, "w", encoding="utf-8") as f:
            f.write(".text\n.globl _frag\n.p2align 2\n_frag:\n")
            for w in words:
                val = int(w, 16)
                b0 = val & 0xff
                b1 = (val >> 8) & 0xff
                b2 = (val >> 16) & 0xff
                b3 = (val >> 24) & 0xff
                f.write(f"  .byte 0x{b0:02x},0x{b1:02x},0x{b2:02x},0x{b3:02x}\n")
        subprocess.check_call(["clang", "-c", "-arch", "arm64", asm, "-o", obj])
        out = run_cmd(["otool", "-tvV", obj])
    host = {}
    for line in out.splitlines():
        m = re.match(r"^([0-9a-f]{16})\t(.*)$", line.strip())
        if not m:
            continue
        off = int(m.group(1), 16)
        host[off] = m.group(2).strip()
    return host


def disassemble_dump_guest_insns(rec):
    mapping = {}
    md = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
    for insn in rec["guest_insns"]:
        pc = int(insn["pc"], 16)
        word = int(insn["insn"], 16) if isinstance(insn["insn"], str) else int(insn["insn"])
        raw = word.to_bytes(4, byteorder="little")
        decoded = list(md.disasm(raw, pc, count=1))
        if decoded:
            i = decoded[0]
            asm = i.mnemonic if not i.op_str else f"{i.mnemonic}\t{i.op_str}"
        else:
            asm = "<undisassembled>"
        mapping[pc] = (word, asm)
    return mapping


def format_guest_insn(pc, dump_map):
    dump = dump_map.get(pc)
    if dump is None:
        return f"0x{pc:016x}: <missing dump insn>"
    dump_word, dump_asm = dump
    return f"0x{pc:016x}: {dump_asm}    ; dump=0x{dump_word:08x}"


def render_record(rec):
    print(f"# fragment {rec['start_pc']}..{rec['end_pc']}")
    if rec["gpr_map"]:
        regs = " ".join(
            f"{m['guest']}->{m['host']}({m['use_count']})" for m in rec["gpr_map"]
        )
    else:
        regs = "(none)"
    print(f"# register relation {regs}")
    print(f"# guest code segment at time of execution {rec['start_pc']}-{rec['end_pc']}")
    print(f"# host body bytes {rec['body_code_size']} total bytes {rec['code_size']}")
    host_map = disassemble_words(rec["host_words"])
    dump_guest_map = disassemble_dump_guest_insns(rec)

    host_offs = [insn["host_off"] for insn in rec["guest_insns"]]
    body_end = rec["body_code_size"]
    for idx, insn in enumerate(rec["guest_insns"]):
        pc = int(insn["pc"], 16)
        print()
        print(f"# {format_guest_insn(pc, dump_guest_map)}")
        start = insn["host_off"]
        if start == 0xFFFFFFFF:
            continue
        next_start = body_end
        for later in host_offs[idx + 1:]:
            if later != 0xFFFFFFFF and later > start:
                next_start = later
                break
        for off in range(start, min(next_start, body_end), 4):
            asm = host_map.get(off, "<undisassembled>")
            print(f"  0x{off:04x}: {asm}")

    if rec["entry_thunks_offset"] < rec["code_size"]:
        print()
        print("# entry thunks")
        for insn in rec["guest_insns"]:
            if insn["entry_off"] == 0xFFFFFFFF:
                continue
            pc = int(insn["pc"], 16)
            print(f"# entry for {format_guest_insn(pc, dump_guest_map)}")
            off = insn["entry_off"]
            for x in range(off, min(off + 18 * 4 + 8, rec["code_size"]), 4):
                asm = host_map.get(x, "<undisassembled>")
                print(f"  0x{x:04x}: {asm}")


def main():
    if len(sys.argv) != 2:
        print("usage: render_arm64_jit_dump.py <dump.log>", file=sys.stderr)
        return 1
    dump_path = sys.argv[1]
    records = parse_dump_lines(dump_path)
    if not records:
        print("no dump records found", file=sys.stderr)
        return 1
    for rec in records:
        render_record(rec)
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
