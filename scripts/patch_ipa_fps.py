#!/usr/bin/env python3
"""Reproducible FPS getter patch for the inspected Liên Quân iOS archive.

Does NOT inject a WebView/menu, bypass any protection, or provide valid signing.
Patch only a matching original UnityFramework and verify expected instructions.
"""
import argparse
import hashlib
import json
import shutil
import struct
import tempfile
import zipfile
from pathlib import Path

UNITY = "Payload/kgvn.app/Frameworks/UnityFramework.framework/UnityFramework"
ORIGINAL_SHA256 = "53a8c9cde76592e55b87db19ab47992a8bac4377e350cee4c9cfad59aa87655d"
RETURN_TRUE = bytes.fromhex("20 00 80 52 C0 03 5F D6")
FUNCTIONS = {
    "60": (0x55624B8, "GameSettings.get_Supported60FPSMode"),
    "90": (0x554C8BC, "GameSettings.get_Supported90FPSMode"),
}
ORIGINAL = bytes.fromhex("F4 4F BE A9 FD 7B 01 A9")


def macho_text(data):
    if data[:4] != bytes.fromhex("CF FA ED FE"):
        raise ValueError("Expected 64-bit little-endian Mach-O")
    cpu, _, _, count, size, _, _ = struct.unpack_from("<7I", data, 4)
    if cpu != 0x0100000C or size + 32 > len(data):
        raise ValueError("Not a supported arm64 Mach-O")
    pos = 32
    for _ in range(count):
        command, n = struct.unpack_from("<II", data, pos)
        if n < 8 or pos + n > len(data):
            raise ValueError("Invalid Mach-O load command")
        if command == 0x19:
            name, vma, vmsize, fileoff, filesize, *_ = struct.unpack_from(
                "<16sQQQQIIII", data, pos + 8
            )
            if name.rstrip(b"\0") == b"__TEXT":
                return vma, vmsize, fileoff, filesize
        pos += n
    raise ValueError("Missing __TEXT segment")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--fps", default="60,90", help="60, 90, or 60,90")
    parser.add_argument("--restore", action="store_true",
                        help="Restore the exact original 8-byte instructions")
    args = parser.parse_args()
    modes = [part.strip() for part in args.fps.split(",")]
    if not modes or len(modes) != len(set(modes)) or any(x not in FUNCTIONS for x in modes):
        parser.error("Choose 60, 90, or 60,90")
    if args.ipa.resolve() == args.output.resolve() or args.output.exists():
        parser.error("Output must be a new, separate path")

    with zipfile.ZipFile(args.ipa, "r") as inp:
        if UNITY not in inp.namelist():
            parser.error("No UnityFramework found in input IPA")
        data = bytearray(inp.read(UNITY))
        digest = hashlib.sha256(data).hexdigest()
        if not args.restore and digest != ORIGINAL_SHA256:
            parser.error("Not the exact inspected binary; no patch applied: " + digest)
        vmaddr, vmsize, off, length = macho_text(data)
        entries = []
        for mode in modes:
            rva, name = FUNCTIONS[mode]
            if rva < vmaddr or rva + 8 > vmaddr + min(length, vmsize):
                parser.error("Method outside __TEXT: " + name)
            start = off + rva - vmaddr
            before, after = (RETURN_TRUE, ORIGINAL) if args.restore else (ORIGINAL, RETURN_TRUE)
            if data[start:start + 8] != before:
                parser.error("Original instruction check failed: " + name)
            data[start:start + 8] = after
            entries.append(dict(symbol=name, rva=hex(rva), file_offset=hex(start),
                                before=before.hex(), after=after.hex()))
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="eri-ipa-") as temp:
            new_path = Path(temp) / "updated.ipa"
            with zipfile.ZipFile(new_path, "w") as out:
                for item in inp.infolist():
                    if item.filename == UNITY:
                        out.writestr(item, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=6)
                    elif item.is_dir():
                        out.writestr(item, b"")
                    else:
                        with inp.open(item) as source, out.open(item, "w", force_zip64=True) as target:
                            shutil.copyfileobj(source, target, 1024 * 1024)
            shutil.move(new_path, args.output)
        report = {
            "result": "binary_modified_not_runtime_tested",
            "original_binary_sha256": ORIGINAL_SHA256,
            "output_binary_sha256": hashlib.sha256(data).hexdigest(),
            "changes": entries,
            "signed": False,
            "warning": "Code signature invalid. Sign before installing. No WebView injected; actual FPS depends on device and game."
        }
        report_path = args.output.with_suffix(".report.json")
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n",
                               encoding="utf-8")
        print("Created", args.output, "and", report_path)


if __name__ == "__main__":
    main()
