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
#
# Auth: bind_to_address "any" (needed so a phone app etc. can reach MPD
# over the LAN) used to mean anyone who could reach port 6600 got full,
# unauthenticated control — no password directive existed at all. Fixed:
# default_permissions "" (anonymous gets nothing) + a generated password
# required for every TCP connection (including localhost:6600, which is
# how rmpc connects by default); the local unix socket is still trusted
# outright via local_permissions, since reaching that at all already
# requires local OS-level access to $XDG_RUNTIME_DIR, not just an open
# port. The password is generated once and reused on every re-run (read
# back out of the existing mpd.conf) so re-running this script doesn't
# silently rotate it out from under an already-configured remote client.
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
echo "################### Setting up MPD + rmpc"
echo "########################################################################"
tput sgr0
echo
echo "Running as: $USER (home: $HOME) — mpd.service will run as this user via"
echo "'systemctl --user', with config/data under \$HOME. No hardcoded username."
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

# Reuse an existing password across re-runs — this file is rewritten
# unconditionally below, so without this a re-run would silently generate
# a fresh password and lock out any remote client already configured with
# the old one.
MPD_PASSWORD=""
if [ -f "$MPD_CONF_DIR/mpd.conf" ]; then
    MPD_PASSWORD=$(grep -E '^password[[:space:]]+"' "$MPD_CONF_DIR/mpd.conf" 2>/dev/null \
        | head -1 | sed -E 's/^password[[:space:]]+"([^@]+)@.*/\1/')
fi
if [ -n "$MPD_PASSWORD" ]; then
    echo "  → reusing existing MPD password from $MPD_CONF_DIR/mpd.conf"
else
    MPD_PASSWORD=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24)
    echo "  → generated a new MPD password"
fi

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

# TCP for remote clients (password-gated below); Unix socket for local
# clients (required for rmpc add / and other commands that use the MPD
# config command).
bind_to_address     "any"
bind_to_address     "$XDG_RUNTIME_DIR/mpd/socket"
port                "6600"

# Anonymous connections get nothing. The local unix socket is trusted
# outright (local_permissions) — reaching it already requires local OS
# access to $XDG_RUNTIME_DIR, a different trust boundary than an open
# TCP port. Everything else, including TCP connections from localhost
# (e.g. rmpc's own default 127.0.0.1:6600), needs the password. See this
# script's header comment for why this exists.
default_permissions ""
local_permissions    "read,add,control,player,admin"
password             "$MPD_PASSWORD@read,add,control,player,admin"

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

# mpd.conf now holds the password in plaintext — restrict it to the owner
# (defense in depth; this is a single-user desktop, but costs nothing).
chmod 600 "$MPD_CONF_DIR/mpd.conf"

tput setaf 2; echo "Wrote $MPD_CONF_DIR/mpd.conf."; tput sgr0

##################################################################################################################################
# 3. rmpc — bootstrap default config, then make sure it has the MPD
# password (rmpc's default address is TCP 127.0.0.1:6600, which — same as
# any other TCP connection — needs the password now that
# default_permissions is empty).
##################################################################################################################################

echo
tput setaf 3
echo "── rmpc config ───────────────────────────────────────────────"
tput sgr0

RMPC_CONF="$HOME/.config/rmpc/config.ron"
if [ -f "$RMPC_CONF" ]; then
    echo "rmpc config already exists — skipping bootstrap (password still checked below)."
else
    mkdir -p "$(dirname "$RMPC_CONF")"
    if rmpc config > "$RMPC_CONF" 2>/dev/null; then
        tput setaf 2; echo "Bootstrapped $RMPC_CONF."; tput sgr0
    else
        tput setaf 1; echo "WARNING: rmpc config bootstrap failed — run 'rmpc config > $RMPC_CONF' manually." >&2; tput sgr0
    fi
fi

if [ -f "$RMPC_CONF" ]; then
    if grep -qF "Some(\"$MPD_PASSWORD\")" "$RMPC_CONF" 2>/dev/null; then
        echo "  → $RMPC_CONF already has the current MPD password — skipping."
    elif grep -qE '^[[:space:]]*password:' "$RMPC_CONF"; then
        sed -i -E "s/^([[:space:]]*password:)[[:space:]]*.*/\1 Some(\"$MPD_PASSWORD\"),/" "$RMPC_CONF"
        if grep -qF "Some(\"$MPD_PASSWORD\")" "$RMPC_CONF"; then
            chmod 600 "$RMPC_CONF"
            tput setaf 6; echo "  → set MPD password in $RMPC_CONF"; tput sgr0
        else
            tput setaf 1
            echo "  → WARNING: couldn't confirm the password was set in $RMPC_CONF —"
            echo "    edit it manually: password: Some(\"$MPD_PASSWORD\"),"
            tput sgr0
        fi
    else
        tput setaf 1
        echo "  → WARNING: no 'password:' field found in $RMPC_CONF (rmpc's config"
        echo "    format may have changed) — set it manually: password: Some(\"$MPD_PASSWORD\"),"
        tput sgr0
    fi
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
echo "###################  $(basename "$0") done"
echo "##############################################################"
echo
echo "MPD config:    $MPD_CONF_DIR/mpd.conf  ← uncomment and set music_directory"
echo "MPD data:      $MPD_DATA_DIR/"
echo "Connect:       rmpc  (localhost:6600) — already has the password below, no"
echo "               action needed for local use."
echo "rmpc config:   $HOME/.config/rmpc/config.ron"
echo "Service:       systemctl --user {status,restart,stop} mpd.service"
echo
tput setaf 3
echo "MPD password (needed by any OTHER TCP client — e.g. a phone app):"
echo "  $MPD_PASSWORD"
echo "Same value on every re-run of this script; stored in mpd.conf (chmod 600)."
tput sgr0
echo
tput sgr0
