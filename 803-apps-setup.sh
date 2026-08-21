#!/bin/bash
#set -e
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Install base GUI applications.
#             Edit the APPS list below — comment out any line to skip that app.
#             Packages are sourced from official Arch repos only — no AUR or
#             Chaotic AUR required. Anything AUR-only is commented out below;
#             uncomment it yourself only if you've deliberately opted into 801.
#             Post-install fixups are handled automatically.
#
# Notable differences from artix-nemesis's 803:
#   - networkmanager + nm-connection-editor instead of connman/connman-gtk.
#     NetworkManager is the standard choice on Arch+systemd (its OpenRC port
#     was abandoned in the source repo because /run/NetworkManager, normally
#     created by systemd-tmpfiles at boot, doesn't exist under OpenRC —
#     that gap doesn't exist here, so it just works).
#   - polkit + xfce-polkit instead of gparted's alacritty+sudo wrapper.
#     dwm has no session infrastructure of its own to launch a polkit agent
#     (unlike GNOME/KDE), so xfce-polkit (a standalone, DE-independent agent)
#     is autostarted via ~/.xprofile. Once it's running, gparted's own
#     packaged .desktop (Exec=gparted-pkexec) prompts for auth properly —
#     no custom wrapper needed.
#   - podman needs no shared-root fixup: systemd-remount-fs.service already
#     marks / as a shared mount at boot, unconditionally, on every systemd box.
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

# ── Apps to install ───────────────────────────────────────────────────────────
# Comment out any line to skip that app.
APPS=(
    fish                 # login shell (chsh + fish_add_path ~/.local/bin auto-configured)
    polkit                # privilege escalation framework (needed by gparted, etc.)
    xfce-polkit           # standalone polkit auth agent (autostarted via ~/.xprofile)
    gparted              # partition editor (uses its own pkexec desktop entry)
    mullvad-browser-bin  # privacy browser
    gimp                 # image editor
    freetube             # YouTube frontend
    darktable            # RAW photo editor
    vlc                  # media player (codecs: libdvdcss libdvdread libdvdnav libbluray libaacs auto-installed)
    kdenlive             # video editor
    krename              # batch file renamer
    flameshot            # screenshot tool with annotation
    rofi                 # app launcher (bound to Mod+d in dwm's config.h)
    freecad              # parametric 3D CAD modeler
    cifs-utils           # SMB/CIFS share mounting (fstab + manual)
    networkmanager       # network manager (nmtui/nmcli; service auto-enabled)
    nm-connection-editor # standalone GUI for NetworkManager (no systray needed)
    podman               # rootless container engine
    distrobox            # run other distros' containers as if native (needs podman above)
    # sublime-text-4      # text editor — AUR/chaotic-aur only, disabled by default (run 801 + uncomment to opt in)
    python-yaml          # dep: blood-pressure-tracker
    python-matplotlib    # dep: blood-pressure-tracker
)
# ─────────────────────────────────────────────────────────────────────────────

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
echo "################### Installing base apps"
echo "########################################################################"
tput sgr0
echo

##################################################################################################################################
# Authenticate sudo once up front; keepalive prevents expiry during long installs
##################################################################################################################################

sudo -v
while true; do timeout 30 sudo -v; sleep 50; done &
SUDO_KEEPALIVE=$!
trap "kill $SUDO_KEEPALIVE 2>/dev/null" EXIT

sudo pacman -Sy

##################################################################################################################################
# Helpers
##################################################################################################################################

# Called after each successful install; add per-app fixups here.
post_install() {
    local pkg="$1"
    case "$pkg" in
        vlc)
            # Codec packages not always pulled in as hard deps
            local codecs=(libdvdcss libdvdread libdvdnav libbluray)
            tput setaf 6
            echo "  → installing VLC codec packages: ${codecs[*]}"
            tput sgr0
            for codec in "${codecs[@]}"; do
                if pacman -Q "$codec" &>/dev/null; then
                    echo "    $codec already installed — skipping."
                else
                    pkg_install "$codec" && echo "    $codec installed." || echo "    WARNING: $codec failed." >&2
                fi
            done
            ;;
        fish)
            # Set fish as the login shell
            if [ "$(getent passwd "$USER" | cut -d: -f7)" != "/usr/bin/fish" ]; then
                tput setaf 6
                echo "  → setting fish as login shell (chsh) ..."
                tput sgr0
                chsh -s /usr/bin/fish
            else
                echo "  → fish already the login shell — skipping chsh."
            fi
            # Ensure ~/.local/bin is in fish PATH
            FISH_CONF="$HOME/.config/fish/config.fish"
            mkdir -p "$(dirname "$FISH_CONF")"
            if grep -qF "fish_add_path ~/.local/bin" "$FISH_CONF" 2>/dev/null; then
                echo "  → fish_add_path already in config.fish — skipping."
            else
                tput setaf 6
                echo "  → adding fish_add_path ~/.local/bin to $FISH_CONF ..."
                tput sgr0
                cat >> "$FISH_CONF" <<'FISHCONF'
if status is-interactive
    fish_add_path ~/.local/bin
end
FISHCONF
            fi
            ;;
        xfce-polkit)
            # dwm has no built-in session infrastructure to launch a polkit
            # agent (unlike GNOME/KDE), so autostart one via ~/.xprofile.
            # Once running, any app's pkexec/PolicyKit prompt (gparted, etc.)
            # gets a proper GUI auth dialog instead of needing a sudo wrapper.
            XPROFILE="$HOME/.xprofile"
            if grep -qF "xfce-polkit" "$XPROFILE" 2>/dev/null; then
                echo "  → ~/.xprofile already starts xfce-polkit — skipping."
            else
                tput setaf 6
                echo "  → adding xfce-polkit autostart to ~/.xprofile ..."
                tput sgr0
                cat >> "$XPROFILE" <<'XPROFILE_ENTRY'

# xfce-polkit — standalone PolicyKit auth agent (dwm has no session shell of its own)
/usr/lib/xfce-polkit/xfce-polkit &
XPROFILE_ENTRY
            fi
            ;;
        flameshot)
            # On X11 + dwm (no xdg-desktop-portal Screenshot backend), flameshot's
            # portal-based capture times out after 30s and fails. Force the legacy
            # X11 capture path instead. This is a dwm/portal-backend gap, not an
            # init-system issue — it would happen identically on Artix. See
            # flameshot-org/flameshot#4737.
            FLAMESHOT_CONF="$HOME/.config/flameshot/flameshot.ini"
            mkdir -p "$(dirname "$FLAMESHOT_CONF")"
            if grep -q '^useX11LegacyScreenshot=true' "$FLAMESHOT_CONF" 2>/dev/null; then
                echo "  → flameshot.ini already has useX11LegacyScreenshot=true — skipping."
            else
                if [ ! -f "$FLAMESHOT_CONF" ]; then
                    printf '[General]\nuseX11LegacyScreenshot=true\n' > "$FLAMESHOT_CONF"
                elif grep -q '^useX11LegacyScreenshot=' "$FLAMESHOT_CONF"; then
                    sed -i 's/^useX11LegacyScreenshot=.*/useX11LegacyScreenshot=true/' "$FLAMESHOT_CONF"
                elif grep -q '^\[General\]' "$FLAMESHOT_CONF"; then
                    sed -i '/^\[General\]/a useX11LegacyScreenshot=true' "$FLAMESHOT_CONF"
                else
                    printf '[General]\nuseX11LegacyScreenshot=true\n' >> "$FLAMESHOT_CONF"
                fi
                tput setaf 6
                echo "  → set useX11LegacyScreenshot=true in $FLAMESHOT_CONF"
                tput sgr0
            fi
            ;;
        networkmanager)
            tput setaf 6
            echo "  → enabling NetworkManager.service ..."
            tput sgr0
            sudo systemctl enable --now NetworkManager.service
            ;;
    esac
}

##################################################################################################################################
# Install loop
##################################################################################################################################

FAILED=()

for app in "${APPS[@]}"; do
    echo
    tput setaf 3
    echo "── $app ──────────────────────────────────────────"
    tput sgr0

    if pacman -Q "$app" &>/dev/null; then
        echo "$app already installed — skipping install, but re-applying post-install fixups."
        post_install "$app"
        continue
    fi

    echo "Installing $app ..."
    pkg_install "$app" || true
    if pacman -Q "$app" &>/dev/null; then
        tput setaf 2
        echo "$app installed."
        tput sgr0
        post_install "$app"
    else
        tput setaf 1
        echo "ERROR: $app installation failed." >&2
        tput sgr0
        FAILED+=("$app")
    fi
done

##################################################################################################################################
# Deploy alacritty config
##################################################################################################################################

ALACRITTY_CONF="$HOME/.config/alacritty/alacritty.toml"
if grep -qF '#0a0a0a' "$ALACRITTY_CONF" 2>/dev/null; then
    echo "alacritty config already in place — skipping."
else
    mkdir -p "$(dirname "$ALACRITTY_CONF")"
    tput setaf 6
    echo "Writing alacritty config ..."
    tput sgr0
    cat > "$ALACRITTY_CONF" <<'ALACRITTYCONF'
[font]
size = 14.0

[font.normal]
family = "monospace"
style = "Regular"

[font.bold]
family = "monospace"
style = "Bold"

[font.italic]
family = "monospace"
style = "Italic"

[window]
padding.x = 8
padding.y = 8
decorations = "full"

[scrolling]
history = 10000

[cursor]
style.shape = "Block"
unfocused_hollow = true

[colors.primary]
background = "#0a0a0a"
foreground = "#d0d2d0"

[colors.normal]
black   = "#1a1a1a"
red     = "#e06c6c"
green   = "#39d353"
yellow  = "#f5c050"
blue    = "#3b9eff"
magenta = "#c87ed8"
cyan    = "#5ec4bd"
white   = "#d0d2d0"

[colors.bright]
black   = "#888888"
red     = "#ff7878"
green   = "#57ff6e"
yellow  = "#ffd855"
blue    = "#5bc8ff"
magenta = "#dc9af5"
cyan    = "#7ee8dd"
white   = "#ffffff"
ALACRITTYCONF
    tput setaf 2
    echo "  → wrote $ALACRITTY_CONF"
    tput sgr0
fi

##################################################################################################################################
# Install blood-pressure-tracker (Python CLI from GitHub source)
##################################################################################################################################

BP_WRAPPER="$HOME/.local/bin/bp-tracker"
if [ -f "$BP_WRAPPER" ]; then
    echo "bp-tracker already installed — skipping."
else
    tput setaf 6
    echo "Installing blood-pressure-tracker ..."
    tput sgr0
    BP_SRC="$HOME/.local/src/bp-tracker"
    rm -rf "$BP_SRC"
    git clone https://github.com/zythros/blood-pressure-tracker "$BP_SRC"
    export PATH="$HOME/.local/bin:$PATH"
    bash "$BP_SRC/install.sh"
    tput setaf 2
    echo "  → bp-tracker installed."
    tput sgr0
fi

##################################################################################################################################

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename $0) done"
echo "##############################################################"
echo

if [ ${#FAILED[@]} -gt 0 ]; then
    tput setaf 1
    echo "The following apps failed to install:"
    for f in "${FAILED[@]}"; do
        echo "  - $f"
    done
    tput sgr0
else
    tput setaf 2
    echo "All apps installed successfully."
    tput sgr0
fi

echo
tput sgr0
