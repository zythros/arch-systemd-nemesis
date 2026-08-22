#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Install picom (X11 compositor) and make the terminal (alacritty,
#             per 802/803) translucent: ~90% opacity when focused, ~70% when
#             unfocused. Bare metal only — skips automatically inside a VM,
#             matching 870's VM-only check but inverted: extra GPU compositing
#             on top of an already-virtualized/passed-through display is a
#             cost with no real payoff for a purely cosmetic effect.
#
#             Split across two mechanisms deliberately, not one picom
#             opacity-rule for both states — see Step 2/3 comments below:
#             picom composites a whole window's pixels uniformly, so any
#             picom-level opacity dims the text along with the background.
#             Alacritty's own window.opacity only touches the background
#             (glyphs are drawn separately at full alpha), so the *focused*
#             opacity comes from alacritty directly — text stays fully crisp
#             — and picom only ever adds extra dimming on top for the
#             *unfocused* case, where touching the text too is fine.
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
# OPACITY_ACTIVE: alacritty's own background opacity (%), applied directly
# in alacritty.toml — this is what the focused terminal actually shows.
# Text is untouched by this (alacritty renders glyphs at full alpha
# regardless of window.opacity).
OPACITY_ACTIVE=90
# OPACITY_INACTIVE: target *overall* opacity (%) when unfocused. picom
# applies an extra dim on top of OPACITY_ACTIVE to reach this (see Step 3) —
# it's the only one of the two that also touches text, since picom can't
# tell background from glyphs, which is fine for the unfocused case.
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
# Step 2: Set alacritty's own background opacity — this, not picom, is what
# the focused terminal shows. alacritty.toml's [window] opacity only fades
# the background fill; glyphs are drawn at full alpha regardless, so text
# stays fully crisp no matter how transparent the background gets. (803
# writes alacritty.toml's [window] section without an opacity key — patched
# in here rather than in 803, since the opacity value is this script's
# concern, not the base terminal config's.)
##################################################################################################################################

echo
tput setaf 3
echo "── Setting alacritty background opacity to ${OPACITY_ACTIVE}% (text unaffected) ──"
tput sgr0

ALACRITTY_CONF="$HOME/.config/alacritty/alacritty.toml"
ALACRITTY_OPACITY=$(awk -v v="$OPACITY_ACTIVE" 'BEGIN{printf "%.2f", v/100}')

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
# xrender is slower but "just works" for a plain opacity effect. Switch to
# "glx" here if you've verified it's stable on this hardware.
#
# use-ewmh-active-win: confirmed live that without this, picom's default
# FocusIn/FocusOut-based focus tracking gets it backwards under dwm — the
# focused terminal came out dimmed (the !focused rule) and the unfocused one
# came out fully opaque (the focused rule), i.e. exactly inverted. dwm
# reliably maintains _NET_ACTIVE_WINDOW itself (sets/deletes it on root in
# its own focus() on every focus change), so telling picom to trust that
# property instead of raw X focus events is the documented fix for "focused
# condition is backwards on a minimal WM", not a coincidence-only guess.
#
# mark-wmwin-focused / mark-ovredir-focused: unrelated edge case (WM
# decoration / override-redirect windows with no WM_TRANSIENT_FOR) — kept,
# harmless, but use-ewmh-active-win above is what actually fixes focus
# tracking for normal client windows like the terminal.
#
# opacity-rule below is *not* symmetric on purpose (unlike a naive first
# pass at this): the focused case is pinned to 100 (i.e. picom leaves it
# alone) so alacritty's own OPACITY_ACTIVE background opacity from Step 2 is
# the only thing determining the focused terminal's look — text stays
# crisp. The unfocused case gets a *relative* multiplier
# (OPACITY_INACTIVE / OPACITY_ACTIVE) instead of OPACITY_INACTIVE directly,
# so it compounds with Step 2's base opacity to land on the actual target
# OPACITY_INACTIVE overall, e.g. 90% (alacritty) × 78% (picom) ≈ 70%.
##################################################################################################################################

REL_INACTIVE=$(awk -v a="$OPACITY_ACTIVE" -v i="$OPACITY_INACTIVE" 'BEGIN{printf "%.0f", (i*100)/a}')

echo
tput setaf 3
echo "── Writing picom.conf (terminal opacity: ${OPACITY_ACTIVE}% active / ~${OPACITY_INACTIVE}% inactive) ──"
tput sgr0

PICOM_CONF="$HOME/.config/picom/picom.conf"
MARKER="100:class_g = '$TERM_CLASS' && focused"

if grep -qF "$MARKER" "$PICOM_CONF" 2>/dev/null; then
    echo "  → $PICOM_CONF already has the $TERM_CLASS opacity rule — skipping."
else
    mkdir -p "$(dirname "$PICOM_CONF")"
    cat > "$PICOM_CONF" <<EOF
# Written by 804-picom-setup.sh — re-run that script to regenerate.

backend = "xrender";
vsync = true;

# dwm maintains _NET_ACTIVE_WINDOW reliably (see comment in
# 804-picom-setup.sh) — use it instead of raw FocusIn/FocusOut tracking,
# which was confirmed live to report focus backwards under dwm.
use-ewmh-active-win = true;

mark-wmwin-focused = true;
mark-ovredir-focused = true;

# Fade between opacity levels on focus change instead of an instant jump
fading = true;
fade-in-step = 0.06;
fade-out-step = 0.06;

# Focused: left at 100 (untouched) -- alacritty.toml's own [window] opacity
# (Step 2) is what shows, so the text stays fully crisp. Unfocused: an
# additional relative dim on top of that base, landing on ~$OPACITY_INACTIVE%
# overall ($OPACITY_ACTIVE% alacritty x $REL_INACTIVE% picom).
opacity-rule = [
    "100:class_g = '$TERM_CLASS' && focused",
    "$REL_INACTIVE:class_g = '$TERM_CLASS' && !focused"
];
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
echo "Focused terminal: ${OPACITY_ACTIVE}% opacity, set directly in alacritty.toml —"
echo "text stays fully crisp. Unfocused: picom dims it further to ~${OPACITY_INACTIVE}%"
echo "overall (this pass does affect text too, which is expected/fine when unfocused)."
echo "If the $TERM_CLASS terminal doesn't pick up the opacity, confirm its"
echo "actual WM_CLASS with 'xprop WM_CLASS' and update TERM_CLASS at the top"
echo "of this script."
tput sgr0
echo
