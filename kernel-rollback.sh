#!/bin/bash
#set -e
##################################################################################################################################
# Author    : zythros
# Purpose   : Roll back the kernel to any version available in the pacman cache.
#             Lists kernel + headers pairs, lets you pick one with fzf,
#             then installs with pacman -U and rebuilds DKMS modules.
#             Detects the installed kernel flavor (linux/-lts/-zen/-hardened)
#             rather than assuming plain "linux" — which kernel this install
#             uses is an install-time decision, not something to hardcode.
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

CACHE=/var/cache/pacman/pkg
RUNNING=$(uname -r)

# Detect the installed kernel flavor rather than assuming "linux" — same
# helper logic as lib.sh's detect_kernel_pkg, inlined here since this
# script is deliberately standalone (not wired into menu-fzf.sh).
KERNEL_PKG="linux"
for k in linux linux-lts linux-zen linux-hardened; do
    if pacman -Q "$k" &>/dev/null; then
        KERNEL_PKG="$k"
        break
    fi
done

echo
tput setaf 2
echo "########################################################################"
echo "################### Kernel Rollback"
echo "########################################################################"
tput sgr0
echo
echo "Running kernel : $RUNNING"
echo "Kernel package : $KERNEL_PKG"
echo "Cache          : $CACHE"
echo

if ! command -v fzf &>/dev/null; then
    echo "Installing fzf..."
    sudo pacman -S --noconfirm fzf || { echo "Could not install fzf" >&2; exit 1; }
fi

##################################################################################################################################
# Discover kernel packages in cache
##################################################################################################################################

mapfile -t PKG_PATHS < <(
    find "$CACHE" -maxdepth 1 -name "${KERNEL_PKG}-[0-9]*.pkg.tar.zst" | sort -rV
)

if [ ${#PKG_PATHS[@]} -eq 0 ]; then
    echo "No $KERNEL_PKG packages found in $CACHE" >&2
    exit 1
fi

# Normalise running version for comparison (uname: 6.11.3-arch1-1 → all dots: 6.11.3.arch1.1)
running_norm="${RUNNING//-/.}"

DISPLAY_LINES=()
declare -A LINE_TO_PATH

for path in "${PKG_PATHS[@]}"; do
    base=$(basename "$path" .pkg.tar.zst)   # linux-6.11.3.arch1-1-x86_64
    ver="${base#${KERNEL_PKG}-}"             # 6.11.3.arch1-1-x86_64
    ver="${ver%-x86_64}"                     # 6.11.3.arch1-1

    headers="$CACHE/${KERNEL_PKG}-headers-${ver}-x86_64.pkg.tar.zst"
    has_headers="no "
    [ -f "$headers" ] && has_headers="yes"

    ver_norm="${ver//-/.}"
    running_tag=""
    [ "$ver_norm" = "$running_norm" ] && running_tag="  ← running"

    line="$(printf "%-30s  headers: %s%s" "$ver" "$has_headers" "$running_tag")"
    DISPLAY_LINES+=("$line")
    LINE_TO_PATH["$line"]="$path"
done

##################################################################################################################################
# fzf selection
##################################################################################################################################

SELECTED=$(printf '%s\n' "${DISPLAY_LINES[@]}" | fzf \
    --prompt="kernel-rollback > " \
    --header="ENTER to select  |  ESC to cancel" \
    --header-first \
    --reverse \
    --no-sort) || exit 0

[ -z "$SELECTED" ] && { echo "Nothing selected."; exit 0; }

TARGET_PATH="${LINE_TO_PATH[$SELECTED]}"
TARGET_BASE=$(basename "$TARGET_PATH" .pkg.tar.zst)
TARGET_VER="${TARGET_BASE#${KERNEL_PKG}-}"
TARGET_VER="${TARGET_VER%-x86_64}"

##################################################################################################################################
# Build install list
##################################################################################################################################

echo
echo "Selected: $TARGET_VER"

PKGS=("$TARGET_PATH")
HEADERS_PATH="$CACHE/${KERNEL_PKG}-headers-${TARGET_VER}-x86_64.pkg.tar.zst"
if [ -f "$HEADERS_PATH" ]; then
    PKGS+=("$HEADERS_PATH")
fi

echo
echo "Packages to install:"
for p in "${PKGS[@]}"; do
    echo "  $(basename "$p")"
done
echo

read -r -p "Proceed? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

##################################################################################################################################
# Install
##################################################################################################################################

echo
sudo pacman -U "${PKGS[@]}"

##################################################################################################################################
# Rebuild DKMS modules for the target kernel
##################################################################################################################################

# Package version (dots, e.g. 6.11.3.arch1-1) doesn't always translate to the
# modules-dir name (hyphens, e.g. 6.11.3-arch1-1) by a single fixed regex —
# the exact version-tag convention differs per kernel flavor (linux uses
# .archN, linux-zen uses .zenN, linux-lts often has no such tag at all). Read
# the real module directory name straight out of the package archive instead
# of guessing a flavor-specific pattern — this is the exact string DKMS/
# `uname -r` need, and it's correct for any kernel flavor uniformly.
KVER=$(bsdtar -tf "$TARGET_PATH" 2>/dev/null | grep -oP 'usr/lib/modules/\K[^/]+' | head -1)
if [ -z "$KVER" ]; then
    tput setaf 3
    echo "WARNING: could not read the module directory name out of the package" >&2
    echo "         archive — falling back to the raw version string. Verify with" >&2
    echo "         'ls /usr/lib/modules/' after reboot if the DKMS rebuild below" >&2
    echo "         looks wrong." >&2
    tput sgr0
    KVER="$TARGET_VER"
fi

if command -v dkms &>/dev/null; then
    echo
    tput setaf 3
    echo "Rebuilding DKMS modules for $KVER ..."
    tput sgr0
    sudo dkms autoinstall -k "$KVER" || {
        tput setaf 1
        echo "WARNING: dkms autoinstall reported errors — check 'dkms status' after reboot"
        tput sgr0
    }
fi

##################################################################################################################################

echo
tput setaf 2
echo "Done. Reboot to boot into $KVER."
tput sgr0
echo
