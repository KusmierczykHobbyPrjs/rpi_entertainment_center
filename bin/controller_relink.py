#!/usr/bin/env python3
"""
controller_relink.py - make a restored controller mapping bind again.

THE PROBLEM
    You restore a backup onto a fresh install, EmulationStation starts, and it
    asks you to configure your controller as if nothing had been restored. The
    mapping IS there in es_input.cfg. ES just cannot see that it belongs to the
    pad you have plugged in.

    ES identifies a controller by its SDL "GUID", which is not a serial number
    but a hash of what the pad reports:

        0300 457e 7900 0000 0600 0000 1001 0000
        ^bus ^CRC ^vendor    ^product   ^version

    The third field is a CRC-16/ARC of the device NAME, and SDL changed whether
    it collapses the runs of whitespace in that name before hashing it. Same
    physical pad, same vendor and product, different GUID:

        2023 image   name "DragonRise Inc. Generic USB Joystick"        -> 2061
        2026 image   name "DragonRise Inc.   Generic   USB  Joystick  " -> 457e

    So the restore worked perfectly and the controller still does not work.

    RetroArch is unaffected: its autoconfig files match on name plus
    input_vendor_id and input_product_id, none of which move between versions.
    This is an EmulationStation-only failure.

WHAT THIS DOES
    Computes the GUID each connected pad has on THIS system, finds entries in
    es_input.cfg that describe the same physical device (same bus, vendor,
    product and version) but carry a stale GUID, and rewrites just that field.

USAGE
    python3 bin/controller_relink.py            # show what would change
    python3 bin/controller_relink.py --apply    # write it (backs up first)

See docs/30-retropie.md.
"""

import argparse
import os
import re
import shutil
import sys

ES_INPUT = "/opt/retropie/configs/all/emulationstation/es_input.cfg"
DEVICES = "/proc/bus/input/devices"


def squash(name: str) -> str:
    """Collapse runs of whitespace - the only difference between the two
    namings SDL has used, so it is what "the same device name" must mean."""
    return re.sub(r"\s+", " ", name).strip()


def crc16_arc(data: bytes) -> int:
    """SDL_crc16: CRC-16/ARC, reversed polynomial 0xA001, initial value 0."""
    crc = 0
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ 0xA001 if crc & 1 else crc >> 1
    return crc & 0xFFFF


def sdl_guid(bus: int, vendor: int, product: int, version: int, name: str) -> str:
    """Rebuild SDL2's joystick GUID for an evdev device.

    Layout is eight little-endian 16-bit fields, every other one zero:
        bus | crc16(name) | vendor | 0 | product | 0 | version | 0
    """
    fields = [bus, crc16_arc(name.encode()), vendor, 0, product, 0, version, 0]
    return "".join("%02x%02x" % (f & 0xFF, (f >> 8) & 0xFF) for f in fields)


def connected_joysticks(path=DEVICES):
    """Yield dicts for every device in /proc/bus/input/devices with a js handler."""
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            blocks = fh.read().split("\n\n")
    except OSError as exc:
        sys.exit("Cannot read %s: %s" % (path, exc))

    for block in blocks:
        ids = re.search(
            r"^I: Bus=([0-9a-fA-F]+) Vendor=([0-9a-fA-F]+) "
            r"Product=([0-9a-fA-F]+) Version=([0-9a-fA-F]+)",
            block, re.M)
        name = re.search(r'^N: Name="(.*)"', block, re.M)
        handlers = re.search(r"^H: Handlers=(.*)$", block, re.M)
        if not (ids and name and handlers):
            continue
        if not re.search(r"\bjs\d+\b", handlers.group(1)):
            continue          # not a joystick as far as SDL is concerned

        bus, vendor, product, version = (int(g, 16) for g in ids.groups())
        raw = name.group(1)
        # The two namings SDL has used. Both are computed so the report can say
        # which rule this system's SDL follows rather than assuming.
        yield {
            "name": raw,
            "collapsed": squash(raw),
            "bus": bus, "vendor": vendor, "product": product, "version": version,
            "guid": sdl_guid(bus, vendor, product, version, raw),
            "guid_collapsed": sdl_guid(bus, vendor, product, version,
                                       squash(raw)),
            "js": re.search(r"\b(js\d+)\b", handlers.group(1)).group(1),
        }


def guid_parts(guid: str):
    """Split a GUID into (bus, crc, vendor, product, version); None if malformed."""
    if not re.fullmatch(r"[0-9a-fA-F]{32}", guid or ""):
        return None
    le = lambda i: int(guid[i + 2:i + 4] + guid[i:i + 2], 16)
    return le(0), le(4), le(8), le(16), le(24)


def main():
    ap = argparse.ArgumentParser(add_help=True, description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true",
                    help="write the changes (default is to only show them)")
    ap.add_argument("--file", default=ES_INPUT, help="es_input.cfg to repair")
    ap.add_argument("--devices", default=DEVICES,
                    help="device list to read (default %s)" % DEVICES)
    args = ap.parse_args()

    pads = list(connected_joysticks(args.devices))
    if not pads:
        print("No joystick is connected - plug the controller in first.")
        return 1

    print("Connected controllers, and the GUID they have on THIS system:")
    for p in pads:
        print("  %s  %s" % (p["js"], p["name"]))
        print("      vendor=%04x product=%04x version=%04x" %
              (p["vendor"], p["product"], p["version"]))
        print("      GUID %s" % p["guid"])
        if p["guid_collapsed"] != p["guid"]:
            print("      (an older SDL would have called it %s)" % p["guid_collapsed"])
    print()

    try:
        with open(args.file, encoding="utf-8") as fh:
            text = fh.read()
    except OSError as exc:
        sys.exit("Cannot read %s: %s" % (args.file, exc))

    changes = []
    for m in re.finditer(r'<inputConfig\s+type="joystick"[^>]*?'
                         r'deviceName="([^"]*)"[^>]*?deviceGUID="([^"]*)"', text):
        cfg_name, cfg_guid = m.group(1), m.group(2)
        parts = guid_parts(cfg_guid)
        if parts is None:
            continue          # e.g. the keyboard entry, whose GUID is "-1"
        bus, cfg_crc, vendor, product, version = parts

        for p in pads:
            if cfg_guid == p["guid"]:
                print('  OK      "%s" already matches %s' % (cfg_name, p["js"]))
                break

            # Everything except the name hash has to agree first.
            if (bus, vendor, product, version) != \
               (p["bus"], p["vendor"], p["product"], p["version"]):
                continue

            # Matching IDs alone are NOT enough to act on. Plenty of cheap pads
            # report vendor=0000 product=0000 version=0000, so two unrelated
            # controllers can agree on every one of those fields - and rewriting
            # the wrong entry would replace a good mapping with another pad's
            # identity. Require corroboration from the name as well, by either
            # of two independent routes.
            same_name = squash(cfg_name) == squash(p["name"])
            known_crc = cfg_crc in (crc16_arc(p["name"].encode()),
                                    crc16_arc(p["collapsed"].encode()))
            if same_name or known_crc:
                why = "name" if same_name else "name hash"
                changes.append((cfg_guid, p["guid"], cfg_name, p["js"], why))
            else:
                print('  SKIP    "%s" has the same IDs as %s but a different '
                      'name ("%s")' % (cfg_name, p["js"], p["name"]))
                print("            Not relinking - that would overwrite one "
                      "pad's mapping with another's.")
            break
        else:
            print('  UNKNOWN "%s" (%s) matches no connected pad' % (cfg_name, cfg_guid))

    if not changes:
        print("\nNothing to relink.")
        return 0

    print()
    for old, new, name, js, why in changes:
        print('  RELINK  "%s" -> %s   (matched on %s)' % (name, js, why))
        print("            %s" % old)
        print("            %s" % new)

    if not args.apply:
        print("\nNothing written. Re-run with --apply to make the change.")
        return 0

    backup = args.file + ".rec-backup"
    if not os.path.exists(backup):
        shutil.copy2(args.file, backup)
        print("\nBacked up %s -> %s" % (args.file, backup))

    for old, new, _name, _js, _why in changes:
        text = text.replace('deviceGUID="%s"' % old, 'deviceGUID="%s"' % new)
    with open(args.file, "w", encoding="utf-8") as fh:
        fh.write(text)

    print("Updated %s" % args.file)
    print("Restart EmulationStation for it to re-read the file.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
