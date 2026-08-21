#!/bin/bash
#set -e
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Install MPD (Music Player Daemon) + rmpc TUI client; configure
#             MPD as a systemd --user service so it runs as your login user
#             and reaches the PipeWire/PulseAudio socket naturally.
#
# Differs from artix-nemesis's 861 by design, not just by mechanical
# translation: that version ran MPD as a *system* service and patched its
# OpenRC init script's command_user to point at a regular user (with a
# manual chown of /var/lib/mpd) purely to reach the audio socket. On
# systemd, MPD's own package ships a `mpd.service` *user* unit — the
# idiomatic path is to run it under `systemctl --user`, which is already
# your login user, no command_user patch or chown needed. Config and data
# live under ~/.config/mpd and ~/.local/share/mpd instead of /etc + /var/lib.
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

if [ "$DEBUG" = true ]; then
    echo
    echo "------------------------------------------------------------"
    echo "Running $(basename $0)"
    echo "------------------------------------------------------------"
    echo
    read -n 1 -s -r -p "Debug mode is on. Press any key to continue..."
    echo
fi

##################################################################################################################################

echo
tput setaf 2
echo "########################################################################"
echo "################### Setting up MPD + rmpc"
echo "########################################################################"
tput sgr0
echo

##################################################################################################################################
# 1. MPD + rmpc
##################################################################################################################################

echo
tput setaf 3
echo "── MPD + rmpc ───────────────────────────────────────────────────"
tput sgr0

for pkg in mpd rmpc; do
    if pacman -Q "$pkg" &>/dev/null; then
        echo "$pkg already installed — skipping."
    else
        echo "Installing $pkg ..."
        pkg_install "$pkg" || true
        if pacman -Q "$pkg" &>/dev/null; then
            tput setaf 2; echo "$pkg installed."; tput sgr0
        else
            tput setaf 1; echo "ERROR: $pkg installation failed." >&2; tput sgr0
        fi
    fi
done

##################################################################################################################################
# 2. ~/.config/mpd/mpd.conf — write a complete, ready-to-use user-level config
##################################################################################################################################

echo
tput setaf 3
echo "── mpd.conf ──────────────────────────────────────────────────"
tput sgr0

MPD_DATA_DIR="$HOME/.local/share/mpd"
MPD_CONF_DIR="$HOME/.config/mpd"
mkdir -p "$MPD_DATA_DIR/playlists" "$MPD_CONF_DIR"

cat > "$MPD_CONF_DIR/mpd.conf" << EOF
# MPD configuration — managed by 861-mpd-setup.sh
# Full reference: https://mpd.readthedocs.io/en/stable/user.html#configuration

# Set this to your music library path, then restart MPD:
#music_directory "~/Music"

playlist_directory  "$MPD_DATA_DIR/playlists"
db_file             "$MPD_DATA_DIR/tag_cache"
state_file          "$MPD_DATA_DIR/state"
sticker_file        "$MPD_DATA_DIR/sticker.sql"

log_file            "$MPD_DATA_DIR/log"
log_level           "notice"

# TCP for remote clients; Unix socket for local clients (required for
# rmpc add / and other commands that use the MPD config command).
bind_to_address     "any"
bind_to_address     "$XDG_RUNTIME_DIR/mpd/socket"
port                "6600"

# Automatically update the database when music files change (Linux inotify).
auto_update         "yes"

input {
    plugin "curl"
}

audio_output {
    type   "pulse"
    name   "PipeWire"
}
EOF

mkdir -p "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/mpd"

tput setaf 2; echo "Wrote $MPD_CONF_DIR/mpd.conf."; tput sgr0

##################################################################################################################################
# 3. rmpc — bootstrap default config
##################################################################################################################################

echo
tput setaf 3
echo "── rmpc config ───────────────────────────────────────────────"
tput sgr0

RMPC_CONF="$HOME/.config/rmpc/config.ron"
if [ -f "$RMPC_CONF" ]; then
    echo "rmpc config already exists — skipping."
else
    mkdir -p "$(dirname "$RMPC_CONF")"
    rmpc config > "$RMPC_CONF" 2>/dev/null && \
        { tput setaf 2; echo "Bootstrapped $RMPC_CONF."; tput sgr0; } || \
        { tput setaf 1; echo "WARNING: rmpc config bootstrap failed — run 'rmpc config > $RMPC_CONF' manually." >&2; tput sgr0; }
fi

##################################################################################################################################
# 4. Enable and start MPD as a systemd --user service
##################################################################################################################################

echo
tput setaf 3
echo "── Enabling MPD user service ─────────────────────────────────"
tput sgr0

# Lingering lets the user service start at boot without an active login
# session (matches "always available" behavior of the old system-service setup).
if loginctl show-user "$USER" -p Linger 2>/dev/null | grep -q 'Linger=yes'; then
    echo "Lingering already enabled for $USER."
else
    sudo loginctl enable-linger "$USER"
    tput setaf 2; echo "Lingering enabled for $USER (user services now start at boot)."; tput sgr0
fi

systemctl --user daemon-reload
if systemctl --user enable --now mpd.service; then
    tput setaf 2; echo "mpd.service (user) enabled and started."; tput sgr0
else
    echo "mpd.service failed to start — check: systemctl --user status mpd.service"
fi

##################################################################################################################################

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename $0) done"
echo "##############################################################"
echo
echo "MPD config:    $MPD_CONF_DIR/mpd.conf  ← uncomment and set music_directory"
echo "MPD data:      $MPD_DATA_DIR/"
echo "Connect:       rmpc  (localhost:6600)"
echo "rmpc config:   $HOME/.config/rmpc/config.ron"
echo "Service:       systemctl --user {status,restart,stop} mpd.service"
echo
tput sgr0
