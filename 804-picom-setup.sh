#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Install picom (X11 compositor) and configure per-window opacity
#             for the terminal (alacritty, per 802/803): 90% when focused,
#             70% when unfocused. Bare metal only — skips automatically
#             inside a VM, matching 870's VM-only check but inverted: extra
#             GPU compositing on top of an already-virtualized/passed-through
#             display is a cost with no real payoff for a purely cosmetic
#             effect.
#
#             New to this repo — artix-nemesis has no picom setup to port
#             from, and dwm itself has no compositor of its own.
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

# ── Config ───────────────────────────────────────────────────────────────
# TERM_CLASS must match the terminal's WM_CLASS. "Alacritty" is alacritty's
# default (unverified against a live `xprop` — alacritty.toml in 803 doesn't
# override window.class, so this is the stock default). If opacity doesn't
# apply, run `xprop WM_CLASS` on the terminal window and fix this.
TERM_CLASS="Alacritty"
OPACITY_ACTIVE=90
OPACITY_INACTIVE=70
# ─────────────────────────────────────────────────────────────────────────

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
# Check if running on bare metal (mirrors 870-vm-clipboard-setup.sh's VM
# check, inverted — that script runs only inside a VM, this one only outside)
##################################################################################################################################

VIRT_TYPE=$(systemd-detect-virt 2>/dev/null)

if [ -n "$VIRT_TYPE" ] && [ "$VIRT_TYPE" != "none" ]; then
    tput setaf 3
    echo "Running inside a VM ($VIRT_TYPE) - skipping picom setup (bare metal only)"
    tput sgr0
    exit 0
fi

echo
tput setaf 2
echo "########################################################################"
echo "################### picom setup (bare metal)"
echo "########################################################################"
tput sgr0
echo

##################################################################################################################################
# Authenticate sudo once; keepalive prevents expiry during install
##################################################################################################################################

sudo -v
while true; do timeout 30 sudo -v; sleep 50; done &
SUDO_KEEPALIVE=$!
trap 'kill $SUDO_KEEPALIVE 2>/dev/null' EXIT

##################################################################################################################################
# Step 1: Install picom
##################################################################################################################################

echo
tput setaf 3
echo "── Installing picom ──────────────────────────────────────────────────────"
tput sgr0

if pacman -Q picom &>/dev/null; then
    echo "  picom already installed — skipping."
elif pkg_install picom; then
    tput setaf 2; echo "  picom installed."; tput sgr0
else
    tput setaf 1; echo "ERROR: failed to install picom" >&2; tput sgr0; exit 1
fi

##################################################################################################################################
# Step 2: Write ~/.config/picom/picom.conf
#
# xrender backend chosen over glx for compatibility — this machine has an
# NVIDIA GPU (see 880/890), and glx compositing on the proprietary NVIDIA
# driver is a common source of tearing/flicker unless separately tuned.
# xrender is slower but "just works" for a plain opacity effect. Switch to
# "glx" here if you've verified it's stable on this hardware.
#
# mark-wmwin-focused / mark-ovredir-focused: dwm doesn't fully implement the
# EWMH _NET_ACTIVE_WINDOW conventions some WMs rely on for picom's "focused"
# condition — these two make focus tracking work reliably without it.
##################################################################################################################################

echo
tput setaf 3
echo "── Writing picom.conf (terminal opacity: ${OPACITY_ACTIVE}% active / ${OPACITY_INACTIVE}% inactive) ──"
tput sgr0

PICOM_CONF="$HOME/.config/picom/picom.conf"
MARKER="class_g = '$TERM_CLASS' && focused"

if grep -qF "$MARKER" "$PICOM_CONF" 2>/dev/null; then
    echo "  → $PICOM_CONF already has the $TERM_CLASS opacity rule — skipping."
else
    mkdir -p "$(dirname "$PICOM_CONF")"
    cat > "$PICOM_CONF" <<EOF
# Written by 804-picom-setup.sh — re-run that script to regenerate.

backend = "xrender";
vsync = true;

mark-wmwin-focused = true;
mark-ovredir-focused = true;

# Fade between opacity levels on focus change instead of an instant jump
fading = true;
fade-in-step = 0.06;
fade-out-step = 0.06;

opacity-rule = [
    "$OPACITY_ACTIVE:class_g = '$TERM_CLASS' && focused",
    "$OPACITY_INACTIVE:class_g = '$TERM_CLASS' && !focused"
];
EOF
    tput setaf 2; echo "  → wrote $PICOM_CONF"; tput sgr0
fi

##################################################################################################################################
# Step 3: Autostart picom via ~/.xprofile (dwm has no session infrastructure
# of its own to launch a compositor — same reasoning as polkit-gnome's
# autostart in 803)
##################################################################################################################################

echo
tput setaf 3
echo "── Autostarting picom via ~/.xprofile ────────────────────────────────────"
tput sgr0

XPROFILE="$HOME/.xprofile"
if grep -qF 'picom --config' "$XPROFILE" 2>/dev/null; then
    echo "  → ~/.xprofile already starts picom — skipping."
else
    cat >> "$XPROFILE" <<XPROFILE_ENTRY

# picom — compositor, terminal opacity only (see 804-picom-setup.sh)
picom --config "$PICOM_CONF" &
XPROFILE_ENTRY
    tput setaf 6; echo "  → added picom autostart to ~/.xprofile"; tput sgr0
fi

##################################################################################################################################

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename "$0") done"
echo "##############################################################"
echo
tput setaf 2
echo "picom will start automatically on next login (~/.xprofile is sourced by"
echo "SDDM before session start). To apply now without logging out:"
echo "  picom --config $PICOM_CONF -b"
echo "If the $TERM_CLASS terminal doesn't pick up the opacity, confirm its"
echo "actual WM_CLASS with 'xprop WM_CLASS' and update TERM_CLASS at the top"
echo "of this script."
tput sgr0
echo
