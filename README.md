# lid-power-setup

A personal Linux workaround for a laptop where suspend and hibernate proved
unreliable: request a screen lock on lid close, let the desktop's idle cycle
blank the screen, and block Bluetooth while the lid is physically closed.
**The laptop stays awake.** This does not provide suspend-level power savings.

Built and tested on the MacBook/Omarchy setup below. The core uses systemd,
logind, Python 3, `rfkill`, and a Linux input device named `Lid Switch`.
Other systems need their own verification, including a desktop that handles
logind's lock request. Broadcom and Omarchy/Limine extras are conditional.

## Install and verify

Read [`install.sh`](install.sh) before running it. It writes system files
with sudo, restarts `systemd-logind` and the Bluetooth guard, and enables the
guard at boot. Restarting logind can disrupt a desktop session; save work
and run this when an interruption is acceptable.

```bash
git clone https://github.com/Crambeary/lid-power-setup
cd lid-power-setup
./install.sh
```

The installer expects Python 3, `rfkill`, systemd tools, and hardware detection
commands (`lsmod`/`lspci`) to be available; it is not a package installer.
Back up any existing files at the destination paths first: the installer
replaces them without keeping backups.

After installation:

```bash
systemctl is-enabled lid-bluetooth-guard.service
systemctl is-active lid-bluetooth-guard.service
journalctl -u lid-bluetooth-guard.service -b --no-pager
rfkill list bluetooth
```

With work saved, close and reopen the lid. Confirm the screen actually locks
and Bluetooth blocks on close and unblocks on open. The guard acts on the
physical lid even when docked; only logind's **lock** action ignores the
docked case. It unblocks Bluetooth on open rather than restoring a previous
manual block. If no `Lid Switch` device is found, the service keeps retrying;
inspect the journal above.

## Undo

There is no uninstall script. Disable the guard before removing its files:

```bash
sudo systemctl disable --now lid-bluetooth-guard.service
sudo rm /etc/systemd/system/lid-bluetooth-guard.service
sudo rm /usr/local/bin/lid-bluetooth-guard.py
sudo rm /etc/systemd/logind.conf.d/lid-switch.conf
sudo systemctl daemon-reload
```

Remove these optional files only if this installer created them, restoring
any backups you made:

- `/usr/lib/systemd/system-sleep/brcmfmac-cycle.sh`
- `/etc/systemd/system/systemd-hibernate-resume.service.d/order.conf`
- `~/.config/omarchy/hooks/post-boot.d/lid-power-setup-check.sh`

Run `sudo systemctl daemon-reload` again after removing a drop-in. Reboot
when convenient to reload logind's remaining configuration. If Bluetooth
remains software-blocked, run `sudo rfkill unblock bluetooth` when desired.

## Tested hardware

Only actually tested on one machine:

- **MacBookPro14,1** (13", 2017, no Touch Bar) — Intel Kaby Lake, Iris Plus
  Graphics 640, Broadcom BCM4350 802.11ac Wi-Fi (`brcmfmac`)
- **Omarchy** (Arch + Hyprland), kernel `7.1.9-arch1-2`
- LUKS (`cryptdevice=`) + btrfs root, with swap as a **file** in its own
  dedicated `swap` subvolume (not a separate partition)
- **Limine** bootloader building a Unified Kernel Image (UKI), not a
  plain initramfs

`core/` (lid-lock, Bluetooth guard) should work as-is on other laptops —
it only depends on standard systemd/logind and the generic ACPI "Lid
Switch" input device, both far more universal than this one machine. The
`macbook-broadcom/` extras and the suspend/hibernate root-cause notes
below are specific to this hardware and may not transfer:

- **Disk/swap setup is the most likely thing to differ.** `resume=` and
  `resume_offset=` are tied to exactly how your swap is laid out: a swap
  **partition** only needs `resume=<partition>` (no offset at all), while
  a swap **file** needs `resume_offset=` computed for your filesystem
  (`btrfs inspect-internal map-swapfile -r` is btrfs-specific; ext4/xfs
  use different tools). A non-LUKS install has no `cryptdevice=`/mapper
  device to route through in the first place. None of this is handled by
  `install.sh` — the hibernate pieces here document what was tried on
  this specific disk layout, not a general fix.
- **Wi-Fi chipset varies by model/year.** `install.sh` only auto-detects
  Broadcom `brcmfmac`. Other MacBook Wi-Fi generations (e.g. BCM4360 on
  older models, BCM4364/4377 on 2019+ models) may behave differently or
  not need this hook at all; non-Broadcom hardware (Intel, Atheros,
  Realtek) will correctly skip `macbook-broadcom/` entirely.
- **T2-equipped MacBooks (2018+) are a different failure mode.** This
  machine predates the T2 chip. Community reports suggest T2 models hit
  suspend/hibernate issues for different reasons (Touch Bar
  re-enumeration, T2-managed devices) — the fixes here aren't confirmed
  to apply there.
- **Bootloader/initramfs.** The `mkinitcpio -P` / `limine-mkinitcpio`
  rebuild step is Omarchy/Limine-specific. GRUB, systemd-boot with a
  plain initramfs, or dracut-based setups need a different rebuild
  command entirely.

If you try this on a different MacBook model or a non-Mac laptop,
opening an issue with what changed (and what worked) would help fill
this section in.

## Why lock instead of suspend/hibernate

Originally built for a 2017 MacBookPro14,1 (Intel, Broadcom BCM4350 wifi)
running Omarchy, where both suspend and hibernate proved unreliable:

- **Suspend**: Wi-Fi (`brcmfmac`) doesn't reliably come back after resume.
- **Hibernate**: the image writes and the machine powers off cleanly, but
  on power-on the kernel reports `PM: Image not found (code -22)` and just
  cold-boots instead of restoring the session. Confirmed NOT caused by: a
  stale `resume_offset` (verified live against
  `btrfs inspect-internal map-swapfile -r /swap/swapfile`), a missing
  `resume` mkinitcpio hook (present via
  `/etc/mkinitcpio.conf.d/omarchy_resume.conf` on that system), or the
  swapfile being inside a snapshotted subvolume (it lived in its own
  dedicated `swap` subvolume, outside snapper's scope). Tried and did NOT
  fix it: ordering `systemd-hibernate-resume.service` after
  `cryptsetup.target` (`macbook-broadcom/hibernate-resume-order.conf`) —
  kept installed since it's harmless, but the real cause is still open.
  If revisited, do it with someone watching the boot console live (drop
  `quiet splash` temporarily) rather than more blind reboot cycles.

So lid-close is set to **lock** instead: the screen locks immediately and
blanks shortly after via the desktop's normal idle cycle, without relying
on a successful suspend/resume cycle. If your suspend/hibernate is reliable, you
don't need this — `HandleLidSwitch=suspend` and real sleep will always
beat this on battery life.

## What's in `core/`

- `lid-switch.conf` -> `/etc/systemd/logind.conf.d/` — lid close (on
  battery or AC) locks the session; docked (external display/keyboard)
  does nothing, for normal clamshell-mode use.
- `lid-bluetooth-guard.py` + `.service` — reads `SW_LID` events directly
  off the Lid Switch input device (resolved dynamically by name, since
  `/dev/input/eventN` numbering isn't stable across reboots/reinstalls)
  and blocks/unblocks the Bluetooth radio accordingly. Deliberately hooks
  the physical switch rather than the lock screen, so a manual lock (lid
  still open) doesn't kill Bluetooth audio. Needs only python3 and rfkill.

## What's in `macbook-broadcom/` (only installed if Broadcom wifi detected)

- `brcmfmac-cycle.sh` -> `/usr/lib/systemd/system-sleep/` — force-reloads
  the Wi-Fi driver after any suspend/hibernate that *does* happen (e.g.
  triggered manually via `systemctl suspend`), since brcmfmac doesn't
  reinitialize on its own.
- `hibernate-resume-order.conf` -> drop-in on
  `systemd-hibernate-resume.service` — the ordering fix that didn't
  resolve the Image-not-found bug above; vestigial, harmless to keep.

## After a kernel/initramfs update, or a reflash (Omarchy/Limine only)

This system uses Limine + a Unified Kernel Image, not a plain initramfs
file, so `resume=`/`resume_offset=` live inside the signed `.efi` image.
Rebuild it with:

```
sudo mkinitcpio -P    # it will offer to run limine-mkinitcpio for you — accept
```

## Self-healing boot check (optional, Omarchy only)

`install.sh` drops `check-health.sh` into
`~/.config/omarchy/hooks/post-boot.d/` if `~/.config/omarchy/hooks/` exists
(creating `post-boot.d/` if needed). It's
read-only and never elevates privileges on its own — it just notifies you
if something's missing so you can rerun `install.sh` yourself. (A hook
that silently `sudo`'d on every boot would just hang waiting on a
password with no TTY, so it deliberately doesn't try to fix anything
itself.)

## Keeping this backed up

This directory only protects you from a *reflash* if it's also backed up
somewhere off this machine (a git remote, USB, cloud). Locally it
survives normal package updates fine, but a wipe-and-reinstall takes
`~/lid-power-setup` with it unless you've pushed/copied it elsewhere
first.
