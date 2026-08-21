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
#   - polkit + polkit-gnome instead of gparted's alacritty+sudo wrapper.
#     dwm has no session infrastructure of its own to launch a polkit agent
#     (unlike GNOME/KDE), so polkit-gnome (a standalone agent binary — no
#     GNOME desktop dependency at runtime despite the package name) is
#     autostarted via ~/.xprofile. Once it's running, gparted's own packaged
#     .desktop (Exec=gparted-pkexec) prompts for auth properly — no custom
#     wrapper needed. (xfce-polkit was tried first — confirmed AUR-only on
#     a live run, not in official Arch repos at all — swapped for
#     polkit-gnome, which is.)
#   - podman needs no shared-root fixup: systemd-remount-fs.service already
#     marks / as a shared mount at boot, unconditionally, on every systemd box.
#   - ttf-jetbrains-mono-nerd + noto-fonts-emoji added to fix "tofu" (missing
#     glyph) boxes seen live on this install: one in the dwm/slstatus status
#     bar (a Nerd Font icon glyph baked into the zythros/slstatus config.h),
#     one in distrobox's container-indicator prompt icon (needs an emoji
#     font). Neither font was present before — artix-nemesis's own history
#     added then reverted JetBrainsMono Nerd Font, but only because it was
#     bundled with starship, which the user didn't want; the font itself was
#     never the problem. Re-added standalone here, plus the emoji font,
#     which wasn't part of that original bundle at all.
#   - Dark theme defaults added (GTK settings.ini + gsettings, qt5ct/qt6ct
#     pointed at a bundled dark color scheme). Not in artix-nemesis at all —
#     dwm has no portal signaling "prefer dark" to apps on either distro, so
#     this applies equally there if wanted, just added here first.
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
    polkit-gnome          # standalone polkit auth agent (autostarted via ~/.xprofile) —
                           # xfce-polkit was tried first, confirmed AUR-only live, not official
    gparted              # partition editor (uses its own pkexec desktop entry)
    # mullvad-browser-bin # privacy browser — AUR-only (confirmed live: not in official Arch
                           # repos, only AUR), disabled by default (run 801 + uncomment to opt in)
    gimp                 # image editor
    # freetube            # YouTube frontend — AUR-only (freetube/freetube-bin/freetube-git all
                           # AUR, confirmed live), disabled by default (run 801 + uncomment to opt in)
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
    ttf-jetbrains-mono-nerd # Nerd Font icons (status bar glyphs, prompt icons); set as the
                            # fontconfig default for the generic "monospace" family below
    noto-fonts-emoji      # emoji glyphs (e.g. distrobox's container-indicator prompt icon)
    # sublime-text-4      # text editor — AUR/chaotic-aur only, disabled by default (run 801 + uncomment to opt in)
    python-yaml          # dep: blood-pressure-tracker
    python-matplotlib    # dep: blood-pressure-tracker
)
# ─────────────────────────────────────────────────────────────────────────────

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
echo "################### Installing base apps"
echo "########################################################################"
tput sgr0
echo
echo "Running as: $USER (home: $HOME) — per-user config (fish, polkit-gnome"
echo "autostart, alacritty, etc.) is written relative to these, not hardcoded."
echo

##################################################################################################################################
# Authenticate sudo once up front; keepalive prevents expiry during long installs
##################################################################################################################################

sudo -v
while true; do timeout 30 sudo -v; sleep 50; done &
SUDO_KEEPALIVE=$!
trap 'kill $SUDO_KEEPALIVE 2>/dev/null' EXIT

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
        polkit-gnome)
            # dwm has no built-in session infrastructure to launch a polkit
            # agent (unlike GNOME/KDE), so autostart one via ~/.xprofile.
            # Once running, any app's pkexec/PolicyKit prompt (gparted, etc.)
            # gets a proper GUI auth dialog instead of needing a sudo wrapper.
            # (xfce-polkit was the original choice but is AUR-only — confirmed
            # on a live run, not in official Arch repos. polkit-gnome is a
            # standalone agent binary despite the package name — no GNOME
            # desktop dependency at runtime.)
            XPROFILE="$HOME/.xprofile"
            if grep -qF "polkit-gnome" "$XPROFILE" 2>/dev/null; then
                echo "  → ~/.xprofile already starts polkit-gnome — skipping."
            else
                tput setaf 6
                echo "  → adding polkit-gnome autostart to ~/.xprofile ..."
                tput sgr0
                cat >> "$XPROFILE" <<'XPROFILE_ENTRY'

# polkit-gnome — standalone PolicyKit auth agent (dwm has no session shell of its own)
/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &
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
        ttf-jetbrains-mono-nerd)
            # Set as the fontconfig-level default for the generic "monospace"
            # family so every app that asks for "monospace" (alacritty's
            # config.h, dwm's status bar via slstatus, etc.) gets the Nerd
            # Font's icon glyphs instead of falling back to tofu boxes for
            # codepoints the base monospace font doesn't cover.
            FONTCONF="/etc/fonts/local.conf"
            if grep -qF 'JetBrainsMono Nerd Font' "$FONTCONF" 2>/dev/null; then
                echo "  → $FONTCONF already prefers JetBrainsMono Nerd Font — skipping."
            else
                sudo tee "$FONTCONF" > /dev/null <<'FONTCONF_EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <alias>
    <family>monospace</family>
    <prefer>
      <family>JetBrainsMono Nerd Font</family>
    </prefer>
  </alias>
</fontconfig>
FONTCONF_EOF
                tput setaf 6
                echo "  → wrote $FONTCONF (monospace → JetBrainsMono Nerd Font)"
                tput sgr0
            fi
            sudo fc-cache -f &>/dev/null
            MATCHED=$(fc-match monospace 2>/dev/null)
            if echo "$MATCHED" | grep -qi 'jetbrainsmono nerd'; then
                tput setaf 2; echo "  → verified: fc-match monospace → $MATCHED"; tput sgr0
            else
                tput setaf 3
                echo "  → WARNING: fc-match monospace returned '$MATCHED', not JetBrainsMono Nerd Font."
                echo "    Check manually: fc-match monospace"
                tput sgr0
            fi
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
# Dark theme defaults (GTK + Qt)
#
# dwm has no desktop environment / xdg-desktop-portal telling apps "prefer
# dark" — GTK and Qt apps each need to be told directly, through their own
# mechanisms, or they fall back to a light default:
#   - GTK3/GTK4 apps (gimp, darktable, gparted, nm-connection-editor, ...):
#     ~/.config/gtk-{3,4}.0/settings.ini + the matching gsettings key.
#   - Qt5/Qt6 apps (kdenlive, vlc's Qt UI, ...): qt5ct/qt6ct, pointed at a
#     bundled dark color scheme (no hand-rolled palette to maintain).
# mullvad-browser (Firefox-based) isn't covered by either — its dark mode
# is a separate per-app toggle in about:preferences, not something a
# system-wide GTK/Qt setting reaches.
##################################################################################################################################

echo
tput setaf 3
echo "── Dark theme defaults (GTK + Qt) ────────────────────────────"
tput sgr0

GTK_DARK_THEME="Adwaita-dark"   # change here to switch, e.g. to Arc-Dark if you install arc-gtk-theme
QT_COLOR_SCHEME="darker"        # one of: airy, darker, dusk, ia_ora, sand, simple, waves (bundled with qt5ct/qt6ct)

for pkg in gnome-themes-extra gsettings-desktop-schemas dconf qt5ct qt6ct; do
    if pacman -Q "$pkg" &>/dev/null; then
        echo "$pkg already installed — skipping."
    else
        echo "Installing $pkg ..."
        pkg_install "$pkg" && echo "$pkg installed." || echo "WARNING: $pkg failed to install — dark theme fixup below may not fully apply." >&2
    fi
done

# GTK3 + GTK4: both read ~/.config/gtk-{3,4}.0/settings.ini independently
for ver in 3.0 4.0; do
    GTK_CONF="$HOME/.config/gtk-$ver/settings.ini"
    mkdir -p "$(dirname "$GTK_CONF")"
    if grep -q 'gtk-application-prefer-dark-theme=1' "$GTK_CONF" 2>/dev/null; then
        echo "  → gtk-$ver/settings.ini already prefers dark — skipping."
    else
        cat > "$GTK_CONF" <<EOF
[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=$GTK_DARK_THEME
EOF
        tput setaf 6; echo "  → wrote $GTK_CONF"; tput sgr0
    fi
done

# Some GTK apps read the theme via GSettings/dconf instead of settings.ini directly
if command -v gsettings &>/dev/null; then
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface gtk-theme "$GTK_DARK_THEME" 2>/dev/null || true
    echo "  → gsettings color-scheme/gtk-theme set to dark."
fi

# Qt5/Qt6: point qt5ct/qt6ct at a bundled dark color scheme (no custom
# palette file to hand-maintain). Both packages register their platform
# theme plugin under the name "qt5ct" — QT_QPA_PLATFORMTHEME=qt5ct is the
# ArchWiki-documented setting that covers Qt5 *and* Qt6 apps together.
for qtver in qt5ct qt6ct; do
    QT_CONF="$HOME/.config/$qtver/$qtver.conf"
    SCHEME_PATH="/usr/share/$qtver/colors/${QT_COLOR_SCHEME}.conf"
    mkdir -p "$(dirname "$QT_CONF")"
    if grep -qF "$SCHEME_PATH" "$QT_CONF" 2>/dev/null; then
        echo "  → $qtver already uses the $QT_COLOR_SCHEME color scheme — skipping."
    else
        cat > "$QT_CONF" <<EOF
[Appearance]
color_scheme_path=$SCHEME_PATH
custom_palette=true
style=Fusion
EOF
        tput setaf 6; echo "  → wrote $QT_CONF ($QT_COLOR_SCHEME scheme)"; tput sgr0
    fi
done

XPROFILE="$HOME/.xprofile"
if grep -qF 'QT_QPA_PLATFORMTHEME' "$XPROFILE" 2>/dev/null; then
    echo "  → ~/.xprofile already exports QT_QPA_PLATFORMTHEME — skipping."
else
    cat >> "$XPROFILE" <<'XPROFILE_ENTRY'

# Qt apps: use qt5ct/qt6ct for theming (covers both Qt5 and Qt6 apps —
# see 803-apps-setup.sh's dark-theme section for why "qt5ct" is correct
# for both)
export QT_QPA_PLATFORMTHEME=qt5ct
XPROFILE_ENTRY
    tput setaf 6; echo "  → added QT_QPA_PLATFORMTHEME export to ~/.xprofile"; tput sgr0
fi

tput setaf 2
echo "  → Dark theme defaults applied. Takes effect on next app launch for GTK;"
echo "    Qt apps need a fresh login (xprofile re-sourced) to pick up the env var."
echo "    mullvad-browser isn't covered — toggle dark mode manually in its"
echo "    about:preferences (Appearance) if you use it."
tput sgr0

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
echo "###################  $(basename "$0") done"
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
