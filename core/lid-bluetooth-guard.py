#!/usr/bin/env python3
# Blocks the Bluetooth radio while the lid is physically closed, and
# unblocks it on open. Reads SW_LID straight off the lid switch input
# device rather than hooking systemd-logind's lock action, so it only
# fires on the actual lid, not on a manual screen lock (which should
# leave Bluetooth audio etc. alone). Distro-agnostic: only needs
# python3, rfkill, and a standard "Lid Switch" input device.
import glob
import struct
import subprocess
import time

EVENT_FMT = "llHHi"
EVENT_SIZE = struct.calcsize(EVENT_FMT)
EV_SW = 5
SW_LID = 0


def set_bt(blocked):
    subprocess.run(["rfkill", "block" if blocked else "unblock", "bluetooth"])


def initial_state():
    for path in glob.glob("/proc/acpi/button/lid/*/state"):
        with open(path) as f:
            return "closed" in f.read()
    return False


def find_lid_device():
    # /dev/input/eventN numbering isn't stable across reboots/reinstalls,
    # so resolve the Lid Switch device by name each time instead of
    # hardcoding a path.
    block = []
    for line in open("/proc/bus/input/devices"):
        line = line.rstrip("\n")
        if line == "":
            if any(b.startswith("N: Name=\"Lid Switch\"") for b in block):
                for b in block:
                    if b.startswith("H: Handlers="):
                        for h in b.split("=", 1)[1].split():
                            if h.startswith("event"):
                                return f"/dev/input/{h}"
            block = []
        else:
            block.append(line)
    return None


def main():
    dev = find_lid_device()
    if dev is None:
        time.sleep(5)
        raise SystemExit("Lid Switch input device not found")
    set_bt(initial_state())
    with open(dev, "rb") as f:
        while True:
            data = f.read(EVENT_SIZE)
            if len(data) < EVENT_SIZE:
                break
            _, _, ev_type, code, value = struct.unpack(EVENT_FMT, data)
            if ev_type == EV_SW and code == SW_LID:
                set_bt(value == 1)


if __name__ == "__main__":
    main()
