#!/usr/bin/env python3
"""
controller_hotkeys.py - give standalone emulators the exit combo they lack.

THE PROBLEM
    Select+Start to quit a game is a RetroArch feature. It works for every
    libretro core (the lr-* emulators) and does not exist at all for standalone
    ones. Pick a standalone emulator from runcommand's launch menu and there is
    no way back out except a keyboard.

    RetroPie does try to bridge this. Its mupen64plus scriptmodule reads your
    RetroArch joypad autoconfig and writes the equivalent binding into
    mupen64plus.cfg. It finds the autoconfig by matching the device NAME:

        file=$(grep -lF "\"${devices[$device_num]}\"" .../retroarch-joypads/*.cfg)

    The name it searches for comes from /sys/class/input/js0/device/name, which
    is the raw kernel string. The autoconfig stores a whitespace-collapsed
    version of the same name. For any controller whose name contains runs of
    whitespace - "DragonRise Inc.   Generic   USB  Joystick  " is a common one -
    those two never match, the lookup silently yields nothing, and you end up
    with:

        Joy Mapping Stop = ""

    No error, no clue, and no way to exit the emulator.

WHAT THIS DOES
    The same job, matching on vendor and product ID instead of on the name, so
    whitespace cannot break it. For every connected pad it finds the autoconfig,
    reads the hotkey bindings, and writes them into each standalone emulator
    config that understands them.

    It also reports the case that started all this: an exit button bound to the
    same button as the hotkey, which collapses the combo into a single press.

SCOPE - read this before assuming it covers everything
    The controller side is general: any pad, any number of pads.

    The emulator side is not, and cannot be - standalone emulators share no
    common format for input. This handles mupen64plus (every system that has a
    mupen64plus.cfg). Others - PPSSPP, Amiberry, ScummVM - each keep their own
    scheme and would need their own writer. Anything found but not handled is
    listed rather than silently ignored.

USAGE
    python3 bin/controller_hotkeys.py            # show what would change
    python3 bin/controller_hotkeys.py --apply    # write it (backs up first)

See docs/30-retropie.md.
"""

import argparse
import glob
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from controller_relink import connected_joysticks, squash  # noqa: E402

CONFIGDIR = "/opt/retropie/configs"
JOYPAD_DIRS = [
    os.path.join(CONFIGDIR, "all", "retroarch-joypads"),
    os.path.join(CONFIGDIR, "all", "retroarch", "autoconfig"),
]

# RetroArch binding  ->  mupen64plus [CoreEvents] key
HOTKEYS = [
    ("input_exit_emulator", "Joy Mapping Stop"),
    ("input_save_state", "Joy Mapping Save State"),
    ("input_load_state", "Joy Mapping Load State"),
]

HAT_DIRS = {"up": 1, "right": 2, "down": 4, "left": 8}


def ini_get(text, key):
    """Value of `key = "value"` from a RetroArch config, or ''."""
    m = re.search(r'^\s*%s\s*=\s*"?([^"\n]*)"?\s*$' % re.escape(key), text, re.M)
    return m.group(1).strip() if m else ""


def autoconfig_files():
    """Every joypad autoconfig, de-duplicated (the two dirs are often symlinked)."""
    seen, out = set(), []
    for d in JOYPAD_DIRS:
        for path in sorted(glob.glob(os.path.join(d, "*.cfg"))):
            real = os.path.realpath(path)
            if real in seen:
                continue
            seen.add(real)
            out.append(path)
    return out


def find_autoconfig(pad):
    """The autoconfig for this pad: by vendor/product ID first, name second.

    RetroPie matches on the name alone, which is exactly what fails. IDs are
    numeric and cannot be mangled by whitespace, so they are tried first; the
    name is kept only as a fallback for autoconfigs that omit the IDs.
    """
    by_name = None
    for path in autoconfig_files():
        try:
            text = open(path, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        vid, pid = ini_get(text, "input_vendor_id"), ini_get(text, "input_product_id")
        if vid.isdigit() and pid.isdigit():
            if int(vid) == pad["vendor"] and int(pid) == pad["product"]:
                return path, text, "vendor/product ID"
        if squash(ini_get(text, "input_device")) == squash(pad["name"]):
            by_name = by_name or (path, text, "name")
    return by_name if by_name else (None, None, None)


def bind_fragment(text, key):
    """One RetroArch binding as mupen64plus spells it: B3, A2+, H0V1 - or ''.

    Mirrors RetroPie's getBind so the output is byte-identical to what a
    working RetroPie would have produced.
    """
    for suffix in ("_btn", "_axis"):
        val = ini_get(text, key + suffix).replace(" ", "").replace('"', "")
        if not val:
            continue
        if suffix == "_axis":
            # "+3" -> A3+
            return "A%s%s" % (val[1:], val[0])
        if "h" in val:
            # "h0up" -> H0V1
            direction = HAT_DIRS.get(val[2:])
            if direction is None:
                return ""
            return "H%sV%d" % (val[1], direction)
        return "B%s" % val
    return ""


def build_binding(pads_info, action):
    """RetroPie's format: J<n>B<hotkey>/B<action>, comma-joined across pads."""
    parts = []
    for idx, text in pads_info:
        hot = bind_fragment(text, "input_enable_hotkey")
        act = bind_fragment(text, action)
        if not act:
            continue
        parts.append("J%d%s/%s" % (idx, hot, act))
    return ",".join(parts)


def set_ini_value(text, key, value):
    """Replace `key = ...` in a mupen64plus config, preserving everything else."""
    pattern = r'^%s\s*=.*$' % re.escape(key)
    if not re.search(pattern, text, re.M):
        return text, False
    return re.sub(pattern, '%s = "%s"' % (key, value), text, count=1, flags=re.M), True


def unhandled_standalone_emulators():
    """Standalone emulators configured on this machine that this tool cannot set."""
    found = {}
    for path in sorted(glob.glob(os.path.join(CONFIGDIR, "*", "emulators.cfg"))):
        system = os.path.basename(os.path.dirname(path))
        if system == "all":
            continue
        if os.path.exists(os.path.join(CONFIGDIR, system, "mupen64plus.cfg")):
            continue          # handled below
        try:
            lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
        except OSError:
            continue
        names = [ln.split("=")[0].strip() for ln in lines
                 if "=" in ln and not ln.startswith(("default", "lr-"))]
        if names:
            found[system] = names
    return found


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true",
                    help="write the changes (default is to only show them)")
    ap.add_argument("--devices", default="/proc/bus/input/devices",
                    help=argparse.SUPPRESS)
    args = ap.parse_args()

    pads = list(connected_joysticks(args.devices))
    if not pads:
        print("No joystick is connected - plug the controller in first.")
        return 1

    print("Controllers and their RetroArch autoconfig:")
    pads_info = []
    for pad in pads:
        idx = int(re.sub(r"\D", "", pad["js"]) or 0)
        path, text, how = find_autoconfig(pad)
        print("  %s  %s" % (pad["js"], pad["name"]))
        if not path:
            print("      no autoconfig found - configure the pad in "
                  "EmulationStation first")
            continue
        print("      %s  (matched on %s)" % (os.path.basename(path), how))

        # Report the derived fragments, not the raw _btn values: a pad can bind
        # these to an axis or a hat, and reading only _btn would print "-" for a
        # binding that is actually present.
        hot = bind_fragment(text, "input_enable_hotkey")
        ext = bind_fragment(text, "input_exit_emulator")
        print("      hotkey=%s  exit=%s" % (hot or "-", ext or "-"))
        if hot and hot == ext:
            print("      WARNING: hotkey and exit are the same button, so a single")
            print("               press quits. Set them to different buttons in")
            print("               EmulationStation's input configuration.")
        pads_info.append((idx, text))

    if not pads_info:
        print("\nNothing to work from.")
        return 1

    bindings = {m64: build_binding(pads_info, ra) for ra, m64 in HOTKEYS}
    print("\nBindings derived for standalone mupen64plus:")
    for key, val in bindings.items():
        print("  %-24s %s" % (key, val or "(none)"))

    targets = sorted(glob.glob(os.path.join(CONFIGDIR, "*", "mupen64plus.cfg")))
    if not targets:
        print("\nNo mupen64plus.cfg on this machine - nothing to write.")
    changed_any = False
    for cfg in targets:
        system = os.path.basename(os.path.dirname(cfg))
        try:
            text = open(cfg, encoding="utf-8").read()
        except OSError as exc:
            print("\n%s: cannot read (%s)" % (cfg, exc))
            continue
        updates = []
        new = text
        for key, val in bindings.items():
            if not val:
                continue
            if ini_get(new, key) == val:
                continue
            new, ok = set_ini_value(new, key, val)
            if ok:
                updates.append(key)
        print("\n%s (%s)" % (cfg, system))
        if not updates:
            print("  already correct")
            continue
        for key in updates:
            print("  set %-24s -> %s" % (key, bindings[key]))
        changed_any = True
        if args.apply:
            backup = cfg + ".rec-backup"
            if not os.path.exists(backup):
                shutil.copy2(cfg, backup)
                print("  backed up -> %s" % os.path.basename(backup))
            open(cfg, "w", encoding="utf-8").write(new)
            print("  written")

    others = unhandled_standalone_emulators()
    if others:
        print("\nStandalone emulators this tool does NOT configure:")
        for system, names in others.items():
            print("  %-12s %s" % (system, ", ".join(names)))
        print("  Each keeps its own input format; they need their own exit key.")

    if changed_any and not args.apply:
        print("\nNothing written. Re-run with --apply to make the change.")
    elif changed_any:
        print("\nDone. Close and relaunch a game for it to take effect.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
