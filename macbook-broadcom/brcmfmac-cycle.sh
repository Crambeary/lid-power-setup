#!/bin/bash
# brcmfmac doesn't reliably reinitialize after this MacBook resumes from
# hibernate/suspend, leaving wifi dead until a full reboot. Force a
# reload of the driver stack right after resume to bring it back.
case "$1/$2" in
    post/*)
        modprobe -r brcmfmac_wcc brcmfmac 2>/dev/null
        sleep 1
        modprobe brcmfmac_wcc 2>/dev/null || modprobe brcmfmac
        ;;
esac
