#!/bin/bash
# Reinstalls the lid-close power-saving setup after a fresh install/reflash,
# or after any update that overwrites these files. Idempotent: safe to
# re-run any time. Requires sudo. Works on any systemd Linux distro; the
# macbook-broadcom/ extras are only installed when that hardware is detected.
set -euo pipefail
cd "$(dirname "$0")"

echo "== lid close -> lock (no suspend/hibernate) =="
sudo install -D -m 644 core/lid-switch.conf /etc/systemd/logind.conf.d/lid-switch.conf

echo "== bluetooth-off-while-lid-closed service =="
sudo install -D -m 755 core/lid-bluetooth-guard.py /usr/local/bin/lid-bluetooth-guard.py
sudo install -D -m 644 core/lid-bluetooth-guard.service /etc/systemd/system/lid-bluetooth-guard.service
# Clean up the old pre-rename unit/binary/service name if present.
if [[ -f /etc/systemd/system/omarchy-lid-bluetooth.service ]]; then
  sudo systemctl disable --now omarchy-lid-bluetooth.service 2>/dev/null || true
  sudo rm -f /etc/systemd/system/omarchy-lid-bluetooth.service /usr/local/bin/omarchy-lid-bluetooth.py
fi

sudo systemctl daemon-reload
sudo systemctl restart systemd-logind
sudo systemctl enable lid-bluetooth-guard.service
sudo systemctl restart lid-bluetooth-guard.service

if lsmod 2>/dev/null | grep -q brcmfmac || grep -qi broadcom <(lspci -nnk 2>/dev/null | grep -A3 -i network || true); then
  echo "== Broadcom wifi detected: installing resume-reload hook =="
  sudo install -D -m 755 macbook-broadcom/brcmfmac-cycle.sh /usr/lib/systemd/system-sleep/brcmfmac-cycle.sh
  sudo install -D -m 644 macbook-broadcom/hibernate-resume-order.conf /etc/systemd/system/systemd-hibernate-resume.service.d/order.conf
  sudo systemctl daemon-reload
else
  echo "== no Broadcom wifi detected: skipping macbook-broadcom/ extras =="
fi

if command -v limine-mkinitcpio >/dev/null 2>&1; then
  echo "== Omarchy/Limine detected =="
  echo "   If hibernate-related boot params ever look stale, rebuild the UKI with:"
  echo "     sudo mkinitcpio -P   (accept the limine-mkinitcpio prompt)"
fi

echo "== boot-time health check (optional, Omarchy hook) =="
if [[ -d "$HOME/.config/omarchy/hooks" ]]; then
  mkdir -p "$HOME/.config/omarchy/hooks/post-boot.d"
  install -m 755 "$(pwd)/check-health.sh" "$HOME/.config/omarchy/hooks/post-boot.d/lid-power-setup-check.sh"
  echo "   Installed as an Omarchy post-boot hook: notifies you (no sudo, read-only)"
  echo "   if anything is missing, rather than un-attended reinstalling as root."
fi

echo "== done =="
cat /etc/systemd/logind.conf.d/lid-switch.conf
systemctl is-enabled lid-bluetooth-guard.service
rfkill list bluetooth
