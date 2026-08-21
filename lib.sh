#!/bin/bash
# Shared helpers for arch-systemd-nemesis setup scripts.
# Source this at the top of any script that calls pacman:
#   source "$(dirname "$(readlink -f "$0")")/lib.sh"
#
# This is the systemd/Arch port of zythros/artix-nemesis. The biggest
# simplification vs. that repo: artix-nemesis has to run every pacman
# transaction through a hand-rolled "nohook" config because Artix/OpenRC has
# no system D-Bus/session guarantee while pacman hooks run as root, so hooks
# like dbus-reload.hook / dconf-update.hook / gvfsd.hook hang. On a stock
# Arch + systemd box, dbus.service is socket-activated and always available
# before any of that runs, so hooks just work — no nohook dance needed here.

##################################################################################################################################
# pkg_install <pkg>
#
# Install a package via pacman. Official repos only — no AUR/yay fallback,
# by design (see 801/803 for the opt-in Chaotic AUR path). Cleans a stale
# db.lck before each attempt. Returns non-zero if the package isn't available
# in a configured repo; callers should treat that as "not available without
# AUR" rather than a hard error.
##################################################################################################################################

pkg_install() {
    local pkg="$1"
    sudo rm -f /var/lib/pacman/db.lck
    sudo pacman -S --noconfirm --needed "$pkg"
}
