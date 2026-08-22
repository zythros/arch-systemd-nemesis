#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Install picom (X11 compositor) and make the terminal (alacritty,
#             per 802/803) translucent at a constant opacity. Bare metal
#             only — skips automatically inside a VM, matching 870's VM-only
#             check but inverted: extra GPU compositing on top of an
#             already-virtualized/passed-through display is a cost with no
#             real payoff for a purely cosmetic effect.
#
#             Deliberately one constant opacity, not a focused/unfocused
#             split: picom composites a whole window's pixels uniformly, so
#             any picom-level opacity-rule dims the text along with the
#             background — confirmed live. The fix that keeps text crisp is
#             alacritty's own [window] opacity (only fades the background
#             fill; glyphs are drawn at full alpha regardless), set once
#             here in alacritty.toml. picom itself gets no opacity-rule for
#             the terminal at all — with none, it passes the window's own
#             alpha through untouched, so text stays crisp in every state.
#             The tradeoff: no extra dimming when unfocused. That's also
#             what sidesteps a real dwm-specific gotcha: picom's
#             focused/!focused detection is unreliable under dwm (confirmed
#             live — options like use-ewmh-active-win, mark-ovredir-focused,
#             or swapping the rule conditions are all reported fixes for
#             different setups, no consistent winner), so not depending on
#             focus tracking at all removes that whole failure mode.
#
#             picom is still required infrastructure even with no
#             opacity-rule: X11 doesn't blend a window's alpha channel onto
#             the desktop without a running compositor.
#
#             New to this repo — artix-nemesis has no picom setup to port
#             from, and dwm itself has no compositor of its own.
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

# ── Config ───────────────────────────────────────────────────────────────
# TERM_OPACITY: alacritty's background opacity (%), set directly in
# alacritty.toml. Applies constantly, focused or not. Text is untouched by
# this — alacritty renders glyphs at full alpha regardless of window.opacity.
TERM_OPACITY=90
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
# Step 2: Set alacritty's own background opacity — this, not picom, is what
# the terminal shows. alacritty.toml's [window] opacity only fades the
# background fill; glyphs are drawn at full alpha regardless, so text stays
# fully crisp no matter how transparent the background gets. (803 writes
# alacritty.toml's [window] section without an opacity key — patched in
# here rather than in 803, since the opacity value is this script's
# concern, not the base terminal config's.)
##################################################################################################################################

echo
tput setaf 3
echo "── Setting alacritty background opacity to ${TERM_OPACITY}% (text unaffected) ──"
tput sgr0

ALACRITTY_CONF="$HOME/.config/alacritty/alacritty.toml"
ALACRITTY_OPACITY=$(awk -v v="$TERM_OPACITY" 'BEGIN{printf "%.2f", v/100}')

mkdir -p "$(dirname "$ALACRITTY_CONF")"
if [ ! -f "$ALACRITTY_CONF" ]; then
    tput setaf 3
    echo "  → WARNING: $ALACRITTY_CONF not found (run 803-apps-setup.sh first for the"
    echo "    full config) — creating a minimal one with just the opacity setting."
    tput sgr0
    printf '[window]\nopacity = %s\n' "$ALACRITTY_OPACITY" > "$ALACRITTY_CONF"
elif grep -qE "^opacity = ${ALACRITTY_OPACITY}\$" "$ALACRITTY_CONF"; then
    echo "  → alacritty.toml already has opacity = $ALACRITTY_OPACITY — skipping."
elif grep -qE '^opacity = ' "$ALACRITTY_CONF"; then
    sed -i -E "s/^opacity = .*/opacity = $ALACRITTY_OPACITY/" "$ALACRITTY_CONF"
    tput setaf 6; echo "  → updated opacity = $ALACRITTY_OPACITY in $ALACRITTY_CONF"; tput sgr0
elif grep -qE '^\[window\]' "$ALACRITTY_CONF"; then
    sed -i -E "/^\[window\]/a opacity = $ALACRITTY_OPACITY" "$ALACRITTY_CONF"
    tput setaf 6; echo "  → added opacity = $ALACRITTY_OPACITY under [window] in $ALACRITTY_CONF"; tput sgr0
else
    printf '\n[window]\nopacity = %s\n' "$ALACRITTY_OPACITY" >> "$ALACRITTY_CONF"
    tput setaf 6; echo "  → appended [window] opacity = $ALACRITTY_OPACITY to $ALACRITTY_CONF"; tput sgr0
fi

##################################################################################################################################
# Step 3: Write ~/.config/picom/picom.conf
#
# xrender backend chosen over glx for compatibility — this machine has an
# NVIDIA GPU (see 880/890), and glx compositing on the proprietary NVIDIA
# driver is a common source of tearing/flicker unless separately tuned.
# xrender is slower but "just works" here.
#
# Deliberately no opacity-rule at all: Step 2's alacritty.toml opacity is
# the only opacity control for the terminal. picom is only needed so the
# window's own alpha channel actually blends onto the desktop — no
# per-window rule means no focus tracking is involved and no risk of
# picom's focused/!focused detection (unreliable under dwm — see header
# comment) touching this window's opacity, or its text, at all.
##################################################################################################################################

echo
tput setaf 3
echo "── Writing picom.conf (compositor only — opacity is alacritty's job) ──"
tput sgr0

PICOM_CONF="$HOME/.config/picom/picom.conf"
MARKER="opacity is alacritty's job"

if grep -qF "$MARKER" "$PICOM_CONF" 2>/dev/null; then
    echo "  → $PICOM_CONF already in the current (no opacity-rule) form — skipping."
else
    mkdir -p "$(dirname "$PICOM_CONF")"
    cat > "$PICOM_CONF" <<'EOF'
# Written by 804-picom-setup.sh — re-run that script to regenerate.
# No opacity-rule here on purpose: opacity is alacritty's job (see
# alacritty.toml's [window] opacity, set by 804-picom-setup.sh's Step 2).
# picom is just here so a window's own alpha channel actually renders.

backend = "xrender";
vsync = true;
EOF
    tput setaf 2; echo "  → wrote $PICOM_CONF"; tput sgr0
fi

##################################################################################################################################
# Step 4: Autostart picom via ~/.xprofile (dwm has no session infrastructure
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
echo "Restart alacritty (or reload its config) to pick up the new window.opacity."
echo "Terminal opacity: ${TERM_OPACITY}%, constant regardless of focus, set"
echo "directly in alacritty.toml — text stays fully crisp in every state."
tput sgr0
echo
