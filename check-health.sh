#!/bin/bash
# Read-only check: is the lid-power setup actually installed and running?
# No sudo, no privileged actions — just notifies you if something's missing
# so you can run install.sh yourself. Safe to run unattended (e.g. as an
# Omarchy post-boot hook) since it never tries to elevate on its own.
missing=()

[[ -f /etc/systemd/logind.conf.d/lid-switch.conf ]] || missing+=("lid-switch.conf")
systemctl is-enabled lid-bluetooth-guard.service &>/dev/null || missing+=("lid-bluetooth-guard.service")
systemctl is-active lid-bluetooth-guard.service &>/dev/null || missing+=("lid-bluetooth-guard.service (not running)")

if ((${#missing[@]})); then
  msg="lid-power-setup incomplete: ${missing[*]}. Run ~/lid-power-setup/install.sh"
  echo "$msg" >&2
  command -v notify-send >/dev/null 2>&1 && notify-send "Lid power setup" "$msg"
fi
