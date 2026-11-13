#!/usr/bin/env python3
"""Read-only IPA + IL2CPP dump compatibility audit.

Inspects archive metadata and selected rendering/camera method declarations.
No decryption, binary modification, bypasses or game integration.
"""
import argparse
import json
import plistlib
import re
import struct
import sys
import zipfile
from pathlib import Path

TARGETS = {
    "GameSettings": (
        "get_Supported60FPSMode",
        "get_Supported120FPSMode",
        "DowngradeFpsLinkedQuality",
    ),
    "CameraSystem": ("GetZoomRate",),
    "Moba_Camera": ("get_currentZoomAmount",),
    "MaskBlur": ("SetQuality",),
}
CLASS_RE = re.compile(r"^(?:public|private|internal|protected)\s+(?:(?:sealed|abstract|static)\s+)*class\s+(\w+)\b")
RVA_RE = re.compile(r"\bRVA:\s*(0x[0-9a-fA-F]+)\b")

def macho_metadata(head):
    if head[:4] != bytes.fromhex("cffaedfe"):
        return {"recognized": False, "reason": "Requires little-endian 64-bit Mach-O"}
    if len(head) < 32:
        return {"recognized": False, "reason": "Truncated Mach-O header"}
    cpu, subtype, filetype, ncmds, sizeofcmds, flags, reserved = struct.unpack_from("<7I", head, 4)
    result = {
        "recognized": True, "cpu_type": hex(cpu), "arm64": cpu == 0x0100000c,
        "segments": [], "cryptid": None, "has_code_signature_command": False
    }
    if 32 + sizeofcmds > len(head):
        result["warning"] = "Load commands extend beyond inspected header"
        return result
    p = 32
    for _ in range(ncmds):
        if p + 8 > len(head):
            break
        cmd, size = struct.unpack_from("<II", head, p)
        if size < 8 or p + size > len(head):
            break
        if cmd == 0x19 and size >= 72:
            rawname, vmaddr, vmsize, fileoff, filesize, _, _, _, _ = struct.unpack_from(
                "<16sQQQQIIII", head, p + 8
            )
            result["segments"].append({
                "name": rawname.split(b"\0")[0].decode("ascii", errors="replace"),
                "vmaddr": vmaddr, "vmsize": vmsize, "fileoff": fileoff, "filesize": filesize
            })
        elif cmd in (0x21, 0x2c) and size >= 20:
            _, _, cryptid = struct.unpack_from("<III", head, p + 8)
            result["cryptid"] = cryptid
        elif cmd == 0x1d:
            result["has_code_signature_command"] = True
        p += size
    return result

def dump_methods(path):
    targets = {cls: {method: {"found": False, "rva_in_text": None}
                     for method in names} for cls, names in TARGETS.items()}
    class_name = None
    last_rva = None
    for raw in path.open("r", encoding="utf-8", errors="replace"):
        line = raw.strip()
        found_class = CLASS_RE.match(line)
        if found_class:
            class_name = found_class.group(1)
            last_rva = None
            continue
        if line == "}":
            class_name = None
            last_rva = None
            continue
        if class_name not in targets:
            continue
        m = RVA_RE.search(line)
        if m:
            last_rva = int(m.group(1), 16)
        if "(" in line and ")" in line and line.endswith("{ }"):
            for method, details in targets[class_name].items():
                if re.search(r"\b" + re.escape(method) + r"\s*\(", line):
                    details["found"] = True
                    details["rva"] = last_rva
    return targets

def audit(ipa_path, dump_path):
    with zipfile.ZipFile(ipa_path) as archive:
        names = archive.namelist()
        app_info = sorted(n for n in names
                          if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", n))
        if len(app_info) != 1:
            raise ValueError("Expected exactly one top-level app Info.plist")
        app_dir = app_info[0].rsplit("/", 1)[0]
        plist = plistlib.loads(archive.read(app_info[0]))
        unity = app_dir + "/Frameworks/UnityFramework.framework/UnityFramework"
        if unity not in names:
            raise ValueError("UnityFramework not found in this IPA")
        with archive.open(unity) as file:
            head = file.read(65536)
        metadata = macho_metadata(head)
        binary_size = archive.getinfo(unity).file_size
        has_provision = app_dir + "/embedded.mobileprovision" in names

    found = dump_methods(dump_path)
    text_seg = next((x for x in metadata.get("segments", []) if x["name"] == "__TEXT"), None)
    for methods in found.values():
        for detail in methods.values():
            rva = detail.pop("rva", None)
            if rva is not None and text_seg is not None:
                detail["rva_in_text"] = bool(
                    text_seg["vmaddr"] <= rva < text_seg["vmaddr"] + text_seg["vmsize"]
                )
    return {
        "result": "static_inspection_only",
        "ipa": {
            "bundle_id": plist.get("CFBundleIdentifier"),
            "short_version": plist.get("CFBundleShortVersionString"),
            "build_version": plist.get("CFBundleVersion"),
            "unity_size_bytes": binary_size,
            "embedded_provisioning_profile": has_provision,
            "unity_macho_arm64": metadata.get("arm64", False),
            "unity_cryptid": metadata.get("cryptid"),
            "unity_has_code_signature_command": metadata.get("has_code_signature_command", False),
            "text_segment_present": text_seg is not None
        },
        "dump_methods": found,
        "limitations": [
            "RVA within __TEXT does not prove a method is from this exact binary build.",
            "The dump does not establish runtime behavior, calling conventions or original instruction bytes.",
            "No native bridge into the third-party game is present.",
            "The original game IPA is unmodified and is not installable after arbitrary changes without valid signing."
        ],
    }

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", required=True, type=Path)
    parser.add_argument("--dump", required=True, type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if not args.ipa.is_file() or not args.dump.is_file():
        parser.error("Both --ipa and --dump must refer to existing files")
    try:
        result = audit(args.ipa, args.dump)
    except (OSError, ValueError, zipfile.BadZipFile, plistlib.InvalidFileException) as exc:
        parser.exit(2, f"Audit error: {exc}\n")
    output = json.dumps(result, indent=2, ensure_ascii=False)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(output + "\n", encoding="utf-8")
        print(f"Saved audit: {args.output}")
    else:
        print(output)

if __name__ == "__main__":
    main()
