"""
Check the built library of every target against the declared interface and
the frame rules (ARCHITECTURE.md sections 4, 5, 6 and 7).

Usage: python3 -I platform/check.py
Runs from the repo root, inside the image from platform/linux/Dockerfile,
after platform/build-all.sh. It exits with status 1 when any check fails.

Declared interface:
- Functions and roles: each "## Function" entry in docs/reference/ and its
  "- Role:" line.
- Dependency functions: the "Functions used" column of the README
  Dependencies table.

Checks on the library archive of each of the 7 targets:
- Exports: the global symbols are exactly the L2 functions.
- Names: every function starts with the library name.
- Entries: every function in the archive has a documentation entry, and
  every documented function is in the archive.
- Imports: every undefined symbol is a declared dependency function.
- Unwind: every function has unwind data that starts at its first byte.

Checks on the instructions, once for each ISA, on its Linux object. The core
uses the same instruction sequence on every OS (section 7).
- Calls: every call goes straight to a function of the library or to a
  declared dependency function. No indirect calls or jumps.
- Branches: every other branch stays inside its function.
- Stack: no load or store below the stack pointer.
- ARM64: no use of x18. A function that calls keeps an x29 frame record:
  it starts with "stp x29, x30, [sp, #-N]!" and "mov x29, sp", and writes
  x29 nowhere else but its epilogue. A leaf does not touch x29 or x30.

It writes build/linux-<ISA>/calls.txt: one "caller callee" line for each call.
"""

import glob
import re
import subprocess
import sys

TARGETS = [
    ("linux", "x86_64"),
    ("linux", "arm64"),
    ("linux", "riscv64"),
    ("windows", "x86_64"),
    ("windows", "arm64"),
    ("macos", "x86_64"),
    ("macos", "arm64"),
]

failures = []


def fail(target, message):
    failures.append(f"{target}: {message}")


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


# ---------------------------------------------------------------- Declared interface


def library_name():
    with open("README.md", encoding="utf-8") as f:
        m = re.match(r"# asm-(\w+)", f.readline())
    if not m:
        sys.exit("check.py: README.md does not start with '# asm-<library>'")
    return m.group(1)


def declared_roles():
    """{function: role} from the documentation entries."""
    roles = {}
    for path in sorted(glob.glob("docs/reference/*.md")):
        function = None
        with open(path, encoding="utf-8") as f:
            for line in f:
                m = re.match(r"## Function `([^`]+)`", line)
                if m:
                    function = m.group(1)
                    roles[function] = None
                elif line.startswith("## "):
                    function = None
                elif function:
                    m = re.match(r"- Role: (L[012])\.", line)
                    if m:
                        roles[function] = m.group(1)
    for function, role in roles.items():
        if role is None:
            failures.append(f"docs: function {function} has no Role line")
    return roles


def dependency_functions():
    functions, inside = set(), False
    with open("README.md", encoding="utf-8") as f:
        for line in f:
            if line.startswith("## "):
                inside = line.strip() == "## Dependencies"
            elif inside and line.startswith("|") and not line.startswith("|---") and "Functions used" not in line:
                cells = [c.strip() for c in line.strip().strip("|").split("|")]
                functions |= set(re.findall(r"`([^`]+)`", cells[-1]))
    return functions


# ---------------------------------------------------------------- Symbols


def is_temporary(name):
    return name.startswith(".L") or name.startswith("ltmp")


def symbols(archive, macos):
    """Defined code symbols as {name: (address, global)}, and undefined names."""
    defined, undefined = {}, set()
    for line in run("llvm-nm", "--no-sort", archive).splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[0] == "U":
            name = parts[1]
            undefined.add(name[1:] if macos and name.startswith("_") else name)
        elif len(parts) == 3 and parts[1] in "Tt" and not is_temporary(parts[2]):
            name = parts[2]
            if macos and parts[1] == "T" and name.startswith("_"):
                name = name[1:]
            defined[name] = (int(parts[0], 16), parts[1] == "T")
    return defined, undefined


def unwind_starts(archive, os_name):
    """Where unwind data starts: addresses, and on Windows function names."""
    starts = set()
    if os_name == "windows":
        # x64 prints StartAddress, ARM64 prints Function. Both name the function.
        text = run("llvm-readobj", "--unwind", archive)
        return set(re.findall(r"(?:StartAddress|Function): (\S+) \(", text))
    frames = run("llvm-objdump", "--dwarf=frames", archive)
    starts |= {int(a, 16) for a in re.findall(r"FDE cie=\S+ pc=([0-9a-f]+)\.\.\.", frames)}
    if os_name == "macos":
        info = run("llvm-objdump", "--unwind-info", archive)
        starts |= {int(a, 16) for a in re.findall(r"start:\s+(0x[0-9a-f]+)", info)}
    return starts


def check_target(os_name, isa, library, roles, deps):
    target = f"{os_name}-{isa}"
    archive = f"build/{target}/libasm-{library}.a"
    macos = os_name == "macos"
    defined, undefined = symbols(archive, macos)

    exported = {n for n, (_, g) in defined.items() if g}
    l2 = {n for n, r in roles.items() if r == "L2"}
    for name in sorted(exported - l2):
        fail(target, f"exports {name}, which is not a declared L2 function")
    for name in sorted(l2 - exported):
        fail(target, f"does not export the L2 function {name}")
    for name in sorted(defined):
        if not name.startswith(library + "_"):
            fail(target, f"function {name} does not start with {library}_")
        if name not in roles:
            fail(target, f"function {name} has no documentation entry")
    for name in sorted(set(roles) - set(defined)):
        fail(target, f"documented function {name} is not in the library")
    for name in sorted(undefined - deps):
        fail(target, f"uses {name}, which is not a declared dependency function")

    starts = unwind_starts(archive, os_name)
    for name, (address, _) in sorted(defined.items()):
        if address not in starts and name not in starts:
            fail(target, f"function {name} has no unwind data at its start")


# ---------------------------------------------------------------- Instructions

BRANCHES = {
    "arm64": re.compile(r"^(b|b\.\w+|cbz|cbnz|tbz|tbnz)$"),
    "x86_64": re.compile(r"^(j\w+)$"),
    "riscv64": re.compile(r"^(beq|bne|blt|bge|bltu|bgeu|beqz|bnez|blez|bgez|bltz|bgtz|bgt|ble|bgtu|bleu|j|jal)$"),
}
CALLS = {"arm64": re.compile(r"^bl$"), "x86_64": re.compile(r"^callq?$"), "riscv64": None}
BELOW_SP = {
    "arm64": re.compile(r"\[sp, #-[^\]]*\](?!!)"),
    "x86_64": re.compile(r"-0x[0-9a-f]+\(%rsp\)"),
    "riscv64": re.compile(r"-(?:0x[0-9a-f]+|\d+)\(sp\)"),
}
INSTRUCTION = re.compile(r"^\s*([0-9a-f]+):\s+(\S+)\s*(.*?)\s*$")
RELOCATION = re.compile(r"^\s*([0-9a-f]+):\s+(R_\S+)\s+(\S+)$")
FUNCTION_START = re.compile(r"^[0-9a-f]+ <(.+)>:$")


def disassemble(obj):
    """{function: [(address, mnemonic, operands, relocation symbol or None)]}."""
    functions, current = {}, None
    for line in run("llvm-objdump", "-d", "-r", "--no-show-raw-insn", obj).splitlines():
        m = FUNCTION_START.match(line)
        if m:
            # A temporary label (RISC-V keeps them as symbols) stays in its function.
            if not is_temporary(m.group(1)):
                current = m.group(1)
                functions[current] = []
            continue
        if current is None:
            continue
        m = RELOCATION.match(line)
        if m and m.group(2) in ("R_RISCV_RELAX", "R_RISCV_ALIGN"):
            continue
        if m and functions[current]:
            a, mn, ops, _ = functions[current][-1]
            functions[current][-1] = (a, mn, ops, re.sub(r"[-+]0x[0-9a-f]+$", "", m.group(3)))
            continue
        m = INSTRUCTION.match(line)
        if m and not m.group(2).startswith("R_"):
            functions[current].append((int(m.group(1), 16), m.group(2), m.group(3), None))
    return functions


def target_address(operands):
    """The branch or call target: the address before the "<symbol+offset>" note."""
    m = re.search(r"(?:^|[ ,])(?:0x)?([0-9a-f]+) <", operands)
    return int(m.group(1), 16) if m else None


def check_instructions(isa, library, roles, deps):
    target = f"linux-{isa}"
    obj = f"build/{target}/libasm-{library}.a"
    members = run("llvm-ar", "t", obj).split()
    if len(members) != 1:
        fail(target, f"the archive has {len(members)} objects; check.py reads one")
        return
    if isa == "riscv64":
        # RISC-V branches carry relocations to .Ltmp labels: resolve them by address.
        addresses = {}
        for line in run("llvm-nm", "--no-sort", obj).splitlines():
            parts = line.split()
            if len(parts) == 3 and parts[1] in "Tt":
                addresses[parts[2]] = int(parts[0], 16)
    functions = disassemble(obj)
    # Each function ends where its unwind data ends. Bytes after that, such as
    # a constant table in the text section, belong to no function.
    ends = {
        int(a, 16): int(b, 16)
        for a, b in re.findall(r"FDE cie=\S+ pc=([0-9a-f]+)\.\.\.([0-9a-f]+)", run("llvm-objdump", "--dwarf=frames", obj))
    }
    starts = sorted((code[0][0], name) for name, code in functions.items() if code)
    ranges = {}
    for start, name in starts:
        if start not in ends:
            fail(target, f"function {name} has no unwind data at its start")
            ends[start] = start
        ranges[name] = (start, ends[start])
        functions[name] = [i for i in functions[name] if i[0] < ends[start]]
    start_of = {start: name for start, name in starts}
    calls = []

    for name, code in functions.items():
        lo, hi = ranges[name]
        makes_calls = False
        for i, (address, mnemonic, operands, reloc) in enumerate(code):
            where = f"{name}+0x{address - lo:x}"
            if BELOW_SP[isa].search(operands):
                fail(target, f"{where}: accesses memory below the stack pointer: {mnemonic} {operands}")

            # Calls.
            callee = None
            if CALLS[isa] and CALLS[isa].match(mnemonic):
                if operands.startswith("*"):
                    fail(target, f"{where}: indirect call")
                    continue
                callee = reloc or start_of.get(target_address(operands))
                if callee is None:
                    fail(target, f"{where}: call to an address that starts no function")
                    continue
            if isa == "riscv64" and mnemonic == "auipc" and reloc and reloc != "" and i + 1 < len(code):
                if code[i + 1][1] == "jalr" and re.match(r"ra\b", code[i + 1][2]):
                    callee = reloc
            if callee:
                makes_calls = True
                calls.append((name, callee))
                if callee not in roles and callee not in deps:
                    fail(target, f"{where}: calls {callee}, which is not a library or declared dependency function")
                continue

            # Indirect branches.
            if isa == "arm64" and mnemonic in ("br", "blr"):
                fail(target, f"{where}: indirect branch")
            if isa == "x86_64" and mnemonic.startswith("jmp") and operands.startswith("*"):
                fail(target, f"{where}: indirect jump")
            if isa == "riscv64" and mnemonic in ("jalr", "jr"):
                previous = code[i - 1] if i else None
                if not (mnemonic == "jalr" and previous and previous[1] == "auipc" and previous[3]):
                    fail(target, f"{where}: indirect jump")

            # Branches stay inside the function.
            if BRANCHES[isa].match(mnemonic):
                if isa == "riscv64" and reloc:
                    destination = addresses.get(reloc)
                else:
                    destination = target_address(operands)
                if destination is None or not lo <= destination < hi:
                    fail(target, f"{where}: branch out of the function: {mnemonic} {operands}")

            if isa == "arm64" and re.search(r"\b[xw]18\b", operands):
                fail(target, f"{where}: uses x18")

        if isa == "arm64":
            check_frame(target, name, code, makes_calls)

    with open(f"build/{target}/calls.txt", "w") as f:
        for caller, callee in sorted(set(calls)):
            f.write(f"{caller} {callee}\n")


FRAME_WRITES = (
    re.compile(r"^stp x29, x30, \[sp, #-0x[0-9a-f]+\]!$"),
    re.compile(r"^mov x29, sp$"),
    re.compile(r"^ldp x29, x30, \[sp\], #0x[0-9a-f]+$"),
)


def check_frame(target, name, code, makes_calls):
    lines = [(a, f"{m} {o}".strip()) for a, m, o, _ in code]
    lo = code[0][0]
    if makes_calls:
        if len(lines) < 2 or not FRAME_WRITES[0].match(lines[0][1]) or lines[1][1] != "mov x29, sp":
            fail(target, f"{name}: calls, but does not start with an x29 frame record")
        for address, text in lines:
            if re.search(r"\bx29\b", text) and not any(p.match(text) for p in FRAME_WRITES):
                fail(target, f"{name}+0x{address - lo:x}: uses x29 outside its frame record: {text}")
    else:
        for address, text in lines:
            if re.search(r"\b(x29|x30|w29|w30)\b", text):
                fail(target, f"{name}+0x{address - lo:x}: a leaf uses x29 or x30: {text}")


# ---------------------------------------------------------------- Main


def main():
    library = library_name()
    roles = declared_roles()
    deps = dependency_functions()
    for os_name, isa in TARGETS:
        check_target(os_name, isa, library, roles, deps)
    for isa in ("x86_64", "arm64", "riscv64"):
        check_instructions(isa, library, roles, deps)
    for line in failures:
        print(f"FAIL {line}")
    print(f"{'FAIL' if failures else 'PASS'} check: {len(TARGETS)} targets, {len(failures)} problems")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
