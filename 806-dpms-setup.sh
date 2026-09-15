#!/bin/bash
#set -e
# shellcheck disable=SC2016
# Applies to text written literally into ~/.xprofile: the $ is meant to be
# expanded when SDDM sources ~/.xprofile at the next login, not by this
# setup script right now.
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Stop the display from blanking/powering down under SDDM (the
#             login screen) and dwm (the session) alike.
#
#             Two mechanisms both have to be neutralized, since either one
#             alone is enough to dim/blank the monitor:
#               - X's screensaver (BlankTime) — paints the screen black.
#               - DPMS (Standby/Suspend/Off) — tells the monitor itself to
#                 drop into a low-power state over DDC/HDMI.
#             xset's own defaults (10 min screensaver, DPMS standby/suspend/
#             off riding on top of that) are what's biting here — nothing
#             dwm-specific is off; dwm carries zero display-power code of
#             its own, same as most minimal WMs.
#
#             Fixed in two layers, same defense-in-depth shape as other
#             scripts in this repo (see 861's local_permissions +
#             per-connection password):
#               1. /etc/X11/xorg.conf.d — a ServerFlags block disabling the
#                  DPMS extension outright and zeroing BlankTime. This is
#                  read by *any* Xorg instance on the machine, including the
#                  one SDDM starts for the greeter itself before any user
#                  session exists — so the login screen stops blanking too,
#                  not just the desktop.
#               2. ~/.xprofile — `xset s off -dpms`, same pattern 804/810/
#                  830/870 already use for session autostart. Belt-and-
#                  suspenders: the xorg.conf.d change zeroes the timers and
#                  turns DPMS off at the server level, but doesn't stop some
#                  other piece of software from calling `xset +dpms` or
#                  `xset dpms force ...` mid-session and re-arming it — the
#                  runtime call closes that gap.
#
#             The xorg.conf.d file only takes effect for X servers started
#             *after* it's written — SDDM's already-running greeter Xorg
#             instance won't reread it, so a `systemctl restart sddm` or
#             reboot is needed for the login screen itself. The dwm session
#             picks up ~/.xprofile fresh on every login regardless.
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

if [ "$DEBUG" = true ]; then
    echo
    echo "------------------------------------------------------------"
    echo "Running $(basename "$0")"
    echo "------------------------------------------------------------"
    echo
    read -n 1 -s -r -p "Debug mode is on. Press any key to continue..."
    echo
fi

##################################################################################################################################

echo
tput setaf 2
echo "########################################################################"
echo "################### Disabling display sleep (SDDM + dwm)"
echo "########################################################################"
tput sgr0
echo

##################################################################################################################################
# 1. System-wide Xorg config: kill DPMS and screensaver blanking at the
#    server level. Covers SDDM's greeter Xorg instance as well as the dwm
#    session's, since both are plain Xorg reading the same config dir.
##################################################################################################################################

XORG_CONF="/etc/X11/xorg.conf.d/10-disable-dpms.conf"
XORG_CONF_CONTENT='Section "ServerFlags"
    Option "DPMS" "false"
    Option "BlankTime" "0"
    Option "StandbyTime" "0"
    Option "SuspendTime" "0"
    Option "OffTime" "0"
EndSection'

echo "── Xorg ServerFlags (system-wide) ─────────────────────────────────────"

if [ -f "$XORG_CONF" ] && diff -q <(echo "$XORG_CONF_CONTENT") "$XORG_CONF" &>/dev/null; then
    echo "  → $XORG_CONF already up to date — skipping."
else
    sudo mkdir -p "$(dirname "$XORG_CONF")"
    echo "  → Writing $XORG_CONF ..."
    echo "$XORG_CONF_CONTENT" | sudo tee "$XORG_CONF" > /dev/null
    tput setaf 6
    echo "  → $XORG_CONF written."
    tput sgr0
fi

##################################################################################################################################
# 2. Session-level enforcement via ~/.xprofile — same autostart pattern as
#    804/810/830/870. Catches anything that re-arms DPMS after login.
#
#    xset ships in the separate xorg-xset package (xorg-apps group), NOT as
#    part of xorg-server — 802/803 never pull it in, so a stock install of
#    this repo's scripts doesn't have it. Without this, the line below was
#    silently a no-op every login (`command not found`, backgrounded so
#    nothing surfaced the failure).
##################################################################################################################################

echo
echo "── dwm session (~/.xprofile) ──────────────────────────────────────────"

if ! command -v xset &>/dev/null; then
    echo "  → Installing xorg-xset (provides xset, not part of xorg-server) ..."
    pkg_install xorg-xset
fi

XPROFILE="$HOME/.xprofile"
DPMS_LINE='xset s off -dpms &'

if grep -qF "$DPMS_LINE" "$XPROFILE" 2>/dev/null; then
    echo "  → ~/.xprofile already disables DPMS at session start — skipping."
else
    echo "  → Adding DPMS disable to ~/.xprofile ..."
    echo "$DPMS_LINE" >> "$XPROFILE"
    tput setaf 6
    echo "  → ~/.xprofile updated."
    tput sgr0
fi

##################################################################################################################################
# Summary
##################################################################################################################################

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename "$0") done"
echo "##############################################################"
echo
echo "Display sleep disabled:"
echo "  System:  $XORG_CONF (DPMS off, blanking timers zeroed)"
echo "  Session: ~/.xprofile → xset s off -dpms (runs on every dwm login)"
echo
echo "The dwm session picks this up on the very next login. The SDDM"
echo "greeter's own already-running X server won't reread xorg.conf.d until"
echo "it's restarted:"
echo "  sudo systemctl restart sddm    # kicks you back to the login screen"
echo "or just reboot."
echo
tput sgr0
