"""
Write the asm-rlp vector files.

Usage: generate.py OUT_DIR

Every expected result comes from ethereum-rlp v0.1.6, the pinned reference
(requirements.txt). The file format is in README.md.
"""

import hashlib
import json
import os
import random
import struct
import sys
import threading
import urllib.request

import ethereum_rlp
from ethereum_rlp import rlp
from ethereum_rlp.exceptions import DecodingError
from ethereum_types.numeric import Uint

TESTS_COMMIT = "c67e485ff8b5be9abc8ad15345ec21aa22e290d9"  # ethereum/tests v17.2
TESTS_URL = "https://raw.githubusercontent.com/ethereum/tests/" + TESTS_COMMIT + "/RLPTests/"
SOURCES = {
    "rlptest.json": "dd11055db749a21d8ee7aae7810ac30d19a89e2c6dadba9967f7bd567ad5fc00",
    "invalidRLPTest.json": "f90bf5745d21bfa7fbfeabaf5b6d1c66bae10051b1c0a054eecd424d488385d7",
    "RandomRLPTests/example.json": "1000fba8f0b749abb16af29a44ef0ab13b54b5ef35a93088d2c6988c8adfbe7f",
}

# include/rlp.inc: the status for each DecodingError message of v0.1.6.
STATUS = {
    "Cannot decode empty bytestring": 2,  # RLP_EMPTY
    "truncated": 3,  # RLP_TRUNCATED
    "trailing bytes": 4,  # RLP_TRAILING_BYTES
    "negative length": 5,  # RLP_NEGATIVE_LENGTH
    "": 6,  # RLP_NON_CANONICAL
}

KIND_BYTES, KIND_LIST = 1, 2
FILE_VALID, FILE_REJECT = 1, 2


# ---------------------------------------------------------------- Sources


def fetch(out, name):
    path = os.path.join(out, "sources", "RLPTests", name)
    want = SOURCES[name]
    if os.path.exists(path):
        with open(path, "rb") as f:
            data = f.read()
        if hashlib.sha256(data).hexdigest() == want:
            return data
    request = urllib.request.Request(TESTS_URL + name, headers={"User-Agent": "asm-rlp-generator"})
    with urllib.request.urlopen(request) as r:
        data = r.read()
    got = hashlib.sha256(data).hexdigest()
    if got != want:
        sys.exit(f"{name}: SHA-256 {got}, pinned {want}")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)
    return data


def from_hex(text):
    text = text[2:] if text.startswith("0x") else text
    return bytes.fromhex(text)


def to_simple(value):
    """The RLPTests "in" value as the Simple tree that v0.1.6 encode uses."""
    if isinstance(value, list):
        return [to_simple(v) for v in value]
    if isinstance(value, int):
        return bytes(Uint(value).to_be_bytes())
    if value.startswith("#"):
        return bytes(Uint(int(value[1:])).to_be_bytes())
    return value.encode()


# ---------------------------------------------------------------- Reference


def reference_decode(enc):
    """(status, tree): v0.1.6 decode of enc."""
    try:
        tree = rlp.decode(enc)
    except DecodingError as e:
        message = e.args[0] if e.args else ""
        if message not in STATUS:
            sys.exit(f"{enc.hex()}: unknown DecodingError {message!r}")
        return STATUS[message], None
    return 0, tree


def header_length(payload):
    if payload < 56:
        return 1
    return 1 + (payload.bit_length() + 7) // 8


def records(enc, tree):
    """The Item records that rlp_decode must write for enc, in pre-order."""
    out = []

    def walk(t, pos):
        """Add the records of t, encoded at pos. Returns its encoded length."""
        index = len(out)
        if isinstance(t, bytes):
            if len(t) == 1 and t[0] < 0x80:
                out.append([KIND_BYTES, pos, 1, 1])
                return 1
            h = header_length(len(t))
            out.append([KIND_BYTES, pos + h, len(t), 1])
            assert enc[pos + h : pos + h + len(t)] == t
            return h + len(t)
        out.append(None)
        # The header length depends on the payload length, so measure first.
        payload = sum(encoded_length(c) for c in t)
        h = header_length(payload)
        p = pos + h
        for c in t:
            p += walk(c, p)
        assert p == pos + h + payload
        out[index] = [KIND_LIST, pos + h, payload, len(out) - index]
        return h + payload

    total = walk(tree, 0)
    assert total == len(enc)
    return out


def encoded_length(t):
    key = id(t)
    if key in _lengths:
        return _lengths[key][1]
    if isinstance(t, bytes):
        n = 1 if len(t) == 1 and t[0] < 0x80 else header_length(len(t)) + len(t)
    else:
        p = sum(encoded_length(c) for c in t)
        n = header_length(p) + p
    _lengths[key] = (t, n)
    return n


_lengths = {}


def valid_case(enc, tree):
    """Check that v0.1.6 decodes enc to tree and encodes it back, then return the records."""
    status, decoded = reference_decode(enc)
    assert status == 0, (enc[:40].hex(), status)
    assert decoded == tree
    assert rlp.encode(decoded) == enc
    _lengths.clear()
    r = records(enc, decoded)
    _lengths.clear()
    return r


# ---------------------------------------------------------------- Files


def blob(b):
    return struct.pack("<Q", len(b)) + b


class VectorFile:
    def __init__(self, kind, dedupe):
        self.kind = kind
        self.dedupe = dedupe
        self.cases = []
        self.encodings = set()

    def add_valid(self, name, enc, recs):
        if self.dedupe and enc in self.encodings:
            return
        self.encodings.add(enc)
        body = blob(name.encode()) + blob(enc) + struct.pack("<Q", len(recs))
        body += b"".join(struct.pack("<4Q", *r) for r in recs)
        self.cases.append(body)

    def add_reject(self, name, enc, status):
        if self.dedupe and enc in self.encodings:
            return
        self.encodings.add(enc)
        self.cases.append(blob(name.encode()) + blob(enc) + struct.pack("<Q", status))

    def write(self, path):
        with open(path, "wb") as f:
            f.write(b"RLPVEC01" + struct.pack("<QQ", self.kind, len(self.cases)))
            for c in self.cases:
                f.write(c)


# ---------------------------------------------------------------- Generated inputs


def boundary_trees():
    """Byte strings and lists at the header boundaries."""
    out = []
    for b in range(256):
        out.append((f"byte_{b:02x}", bytes([b])))
    for n in (0, 2, 55, 56, 57, 255, 256, 257, 1023, 65535, 65536, 65537, 1 << 24):
        out.append((f"bytes_len_{n}", bytes((i * 7 + 3) & 0xFF for i in range(n))))
    for n in (0, 1, 55, 56, 57, 255, 256, 257, 65535, 65536):
        out.append((f"list_payload_{n}", [b"\x01"] * n))
    for n in (54, 55, 56, 254, 255, 256):
        # One string whose encoding makes the list payload n + 2 or n + 3 bytes.
        out.append((f"list_of_string_{n}", [bytes(n)]))
    out.append(("list_of_long_string_2_24", [bytes(1 << 24)]))
    return out


def nested_trees():
    out = []
    for depth in (1, 2, 3, 10, 100, 1000, 3000):
        t = []
        for _ in range(depth - 1):
            t = [t]
        out.append((f"nested_empty_{depth}", t))
        t = [b"leaf"]
        for i in range(depth - 1):
            t = [bytes([i & 0x7F]), t, b"x" * (i % 60)]
        out.append((f"nested_content_{depth}", t))
    return out


def shaped_trees():
    """Trees shaped like the RLP a consensus client handles: an ENR, and a discv5 NODES message."""
    rng = random.Random(1478)

    def enr(i):
        return [
            bytes(rng.randrange(256) for _ in range(64)),  # signature
            bytes(Uint(1000 + i).to_be_bytes()),  # seq
            b"attnets", bytes(rng.randrange(256) for _ in range(8)),
            b"eth2", bytes(rng.randrange(256) for _ in range(16)),
            b"id", b"v4",
            b"ip", bytes([10, 0, i & 0xFF, 1]),
            b"secp256k1", bytes([2]) + bytes(rng.randrange(256) for _ in range(32)),
            b"syncnets", bytes([0x0F]),
            b"tcp", bytes(Uint(9000).to_be_bytes()),
            b"udp", bytes(Uint(9000).to_be_bytes()),
        ]

    return [
        ("enr_shaped", enr(0)),
        ("discv5_nodes_shaped", [bytes(rng.randrange(256) for _ in range(8)), b"\x01", [enr(i) for i in range(16)]]),
    ]


def random_bytes(rng):
    choice = rng.random()
    if choice < 0.3:
        n = 1
    elif choice < 0.6:
        n = rng.randrange(0, 60)
    elif choice < 0.9:
        n = rng.choice((0, 1, 2, 54, 55, 56, 57, 64, 100, 255, 256, 300))
    else:
        n = rng.randrange(0, 2000)
    return bytes(rng.randrange(256) for _ in range(n))


def random_tree(rng, depth, budget):
    """A random tree of at most budget[0] items."""
    budget[0] -= 1
    if depth == 0 or budget[0] <= 0 or rng.random() < 0.45:
        return random_bytes(rng)
    width = rng.choice((0, 1, 2, 3, 4, 8, 17, 40))
    return [random_tree(rng, depth - 1, budget) for _ in range(min(width, max(budget[0], 0)))]


def mutations(enc):
    """Cut, extended and one byte changed copies of enc."""
    out = []
    for k in range(len(enc)):
        out.append(("cut", enc[:k]))
    for b in (0x00, 0x7F, 0x80, 0xC0, 0xFF):
        out.append(("extend", enc + bytes([b])))
    values = (0x00, 0x01, 0x37, 0x38, 0x7F, 0x80, 0x81, 0xB7, 0xB8, 0xB9, 0xBF, 0xC0, 0xC1, 0xF7, 0xF8, 0xF9, 0xFF)
    for i in range(len(enc)):
        for v in values + (enc[i] ^ 0x01,):
            if v != enc[i]:
                out.append((f"byte_{i}_{v:02x}", enc[:i] + bytes([v]) + enc[i + 1 :]))
    return out


CRAFTED = [
    # (name, hex): inputs that reach each refusal, at the top and nested.
    ("top_long_bytes_max_length", "bf" + "ff" * 8),
    ("top_long_list_max_length", "ff" + "ff" * 8),
    ("top_long_bytes_8_byte_length", "bf0000000000000038" + "00" * 56),
    ("top_long_bytes_length_of_length_missing", "bf00"),
    ("nested_long_bytes_max_length", "c9bf" + "ff" * 8),
    ("nested_long_list_max_length", "c9ff" + "ff" * 8),
    ("nested_long_bytes_near_max_length", "c9bf" + "ff" * 7 + "f6"),
    ("nested_long_length_past_parent", "c3b80500"),
    ("top_long_short_length", "b80500"),
    ("nested_leading_zero", "c4b9003800"),
    ("nested_length_of_length_cut", "c2b9"),
    ("nested_short_past_parent", "c2830102"),
    ("nested_single_byte_wrapped", "c28105"),
    ("nested_list_short_length_long_form", "c3f80180"),
    ("single_then_more", "0102"),
    ("single_then_more_long", "7f" + "00" * 100),
    ("list_trailing", "c0c0"),
    ("bytes_trailing", "8100ff"),
    ("deep_then_truncated", "c4c3c2c18f"),
    ("deep_then_noncanonical", "c4c3c2c18101"),
    ("second_child_bad_after_first_bad", "c48101b800"),
]


# ---------------------------------------------------------------- Main


def main(out):
    assert ethereum_rlp.__version__ == "0.1.6", ethereum_rlp.__version__
    sys.setrecursionlimit(1_000_000)
    files = {}

    def f(name, kind):
        if name not in files:
            # Official files keep every case; generated files drop repeated encodings.
            files[name] = VectorFile(kind, dedupe=name.startswith("generated"))
        return files[name]

    # Official vectors: ethereum/tests v17.2 RLPTests.
    valid = json.loads(fetch(out, "rlptest.json"))
    for name, case in valid.items():
        enc = from_hex(case["out"])
        tree = to_simple(case["in"])
        assert rlp.encode(tree) == enc, name
        f("rlptests-valid.bin", FILE_VALID).add_valid(name, enc, valid_case(enc, tree))
    for name, case in json.loads(fetch(out, "RandomRLPTests/example.json")).items():
        assert case["in"] == "VALID"
        enc = from_hex(case["out"])
        status, tree = reference_decode(enc)
        assert status == 0, name
        f("rlptests-valid.bin", FILE_VALID).add_valid(name, enc, valid_case(enc, tree))
    for name, case in json.loads(fetch(out, "invalidRLPTest.json")).items():
        assert case["in"] == "INVALID"
        enc = from_hex(case["out"])
        status, _ = reference_decode(enc)
        assert status != 0, name
        f("rlptests-reject.bin", FILE_REJECT).add_reject(name, enc, status)

    # Generated vectors.
    gv = f("generated-valid.bin", FILE_VALID)
    gr = f("generated-reject.bin", FILE_REJECT)
    bases = [from_hex(c["out"]) for c in valid.values()]
    for name, tree in boundary_trees() + nested_trees() + shaped_trees():
        enc = rlp.encode(tree)
        gv.add_valid(name, enc, valid_case(enc, tree))
        if len(enc) <= 64:
            bases.append(enc)
    rng = random.Random(778)
    for i in range(3000):
        tree = random_tree(rng, rng.randrange(1, 7), [rng.choice((4, 16, 64, 256))])
        enc = rlp.encode(tree)
        gv.add_valid(f"random_{i}", enc, valid_case(enc, tree))
        if len(enc) <= 48 and len(bases) < 600:
            bases.append(enc)
    for name, text in CRAFTED:
        enc = from_hex(text)
        status, tree = reference_decode(enc)
        if status:
            gr.add_reject(name, enc, status)
        else:
            gv.add_valid(name, enc, valid_case(enc, tree))
    for i, base in enumerate(bases):
        for change, enc in mutations(base):
            status, tree = reference_decode(enc)
            name = f"mutation_{i}_{change}"
            if status:
                gr.add_reject(name, enc, status)
            else:
                gv.add_valid(name, enc, valid_case(enc, tree))

    seen = {struct.unpack("<Q", c[-8:])[0] for name in files for c in files[name].cases if files[name].kind == FILE_REJECT}
    missing = set(STATUS.values()) - seen
    assert not missing, f"no reject case for status {sorted(missing)}"

    manifest = []
    for name in sorted(files):
        path = os.path.join(out, name)
        files[name].write(path)
        with open(path, "rb") as fh:
            digest = hashlib.sha256(fh.read()).hexdigest()
        manifest.append(f"{name} {len(files[name].cases)} {digest}")
        print(f"{name}: {len(files[name].cases)} cases")
    with open(os.path.join(out, "manifest.txt"), "w") as fh:
        fh.write("\n".join(manifest) + "\n")


if __name__ == "__main__":
    # Deep trees recurse once per level in v0.1.6 and in records().
    threading.stack_size(1 << 29)
    result = []
    worker = threading.Thread(target=lambda: result.append(main(sys.argv[1])))
    worker.start()
    worker.join()
    if not result:
        sys.exit(1)
