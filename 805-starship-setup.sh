#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Install the starship prompt and reproduce, byte-for-byte, the
#             prompt config observed live on a machine that had been set up
#             via kirodubes/fish-tweak-tool (a GTK4 fish configurator).
#
#             Deliberately NOT using fish-tweak-tool, fisher, or any AUR
#             helper to get here. fish-tweak-tool itself is only distributed
#             through the author's own custom pacman repo
#             (erikdubois.github.io/nemesis_repo) added with `SigLevel =
#             Never` — i.e. pacman does zero signature verification on
#             anything from it. That's a materially bigger trust ask than
#             this repo's existing AUR story (801's Chaotic AUR path is
#             properly key-signed), so rather than add that repo just to get
#             one static config file, this script writes the exact same
#             starship.toml directly and installs starship from Arch's own
#             official `extra` repo.
#
#             starship itself needs nothing fisher-related at runtime — it's
#             a standalone binary; `fisher`/fish-tweak-tool were only ever
#             the *authoring* tool for the config below, not a runtime
#             dependency of the result. Confirmed by inspecting the live
#             machine: `fisher list` was empty and no fish_prompt.fish
#             function file existed — starship owns the whole prompt itself
#             via `starship init fish`.
#
#             Nerd Font glyphs (powerline separators, OS/git/lang icons) need
#             a Nerd Font in the terminal — already covered by 803's
#             ttf-jetbrains-mono-nerd (added for the tofu-box fix, set as the
#             fontconfig "monospace" default), so no separate font install
#             needed here.
#
#             One deliberate deviation from the byte-for-byte capture:
#             [git_status] (dirty/staged/ahead-behind indicators) is dropped
#             from the format. $git_branch just reads .git/HEAD — safe. But
#             $git_status has to query git's actual status machinery on
#             every prompt render in whatever directory you're in, which is
#             what lets a malicious repo's .git/config run code just from
#             cd-ing in — same bug class as CVE-2022-20001 in fish's own
#             __fish_git_prompt, still open against starship's git_status
#             module upstream (github.com/starship/starship/issues/3974).
#             See the comment at [git_branch]/[git_status] in the written
#             config for how to add it back if you've weighed that tradeoff.
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

# ── Config ───────────────────────────────────────────────────────────────
# PALETTE: which [palettes.*] table in starship.toml is active. Both "tide"
# (Tide rainbow/Tango colours — what the source machine had live) and "kiro"
# (gruvbox dark + orange signature) are written into the file either way;
# this just picks which one the top-level `palette =` line points at, so
# re-theming later is a one-line edit, not a script rewrite.
PALETTE="tide"
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

echo
tput setaf 2
echo "########################################################################"
echo "################### starship prompt setup"
echo "########################################################################"
tput sgr0
echo

echo "Running as: $USER (home: $HOME) — per-user config (starship.toml, fish config.fish)"

##################################################################################################################################
# Authenticate sudo once; keepalive prevents expiry during install
##################################################################################################################################

sudo -v
while true; do timeout 30 sudo -v; sleep 50; done &
SUDO_KEEPALIVE=$!
trap 'kill $SUDO_KEEPALIVE 2>/dev/null' EXIT

##################################################################################################################################
# Step 1: Install starship (official `extra` repo — no AUR, no third-party
# repo needed)
##################################################################################################################################

echo
tput setaf 3
echo "── Installing starship ─────────────────────────────────────────────────"
tput sgr0

if pacman -Q starship &>/dev/null; then
    echo "  starship already installed — skipping."
elif pkg_install starship; then
    tput setaf 2; echo "  starship installed."; tput sgr0
else
    tput setaf 1; echo "ERROR: failed to install starship" >&2; tput sgr0; exit 1
fi

##################################################################################################################################
# Step 2: Write ~/.config/starship.toml
#
# Content below is a direct capture of the live config on the source
# machine — not fetched from anywhere, not regenerated by any tool at
# runtime. This script owns the file outright (no "managed block" that
# gets silently overwritten by some other tool on next run).
##################################################################################################################################

echo
tput setaf 3
echo "── Writing ~/.config/starship.toml (palette: $PALETTE) ────────────────────"
tput sgr0

STARSHIP_CONF="$HOME/.config/starship.toml"
MARKER="palette = \"$PALETTE\""

mkdir -p "$(dirname "$STARSHIP_CONF")"

# Second condition (no literal $git_status token) forces regeneration of a
# file written by an older version of this script, back when git_status was
# in the format — see the git_branch/git_status comment below for why that
# was dropped. Palette match alone isn't enough to call an old file
# "current" since that line didn't change when git_status was removed.
# shellcheck disable=SC2016 # deliberate: literal grep pattern, not shell expansion
if [ -f "$STARSHIP_CONF" ] && grep -qF "$MARKER" "$STARSHIP_CONF" && ! grep -qF '$git_status' "$STARSHIP_CONF"; then
    echo "  → $STARSHIP_CONF already up to date (palette \"$PALETTE\", no git_status) — skipping."
else
    cat > "$STARSHIP_CONF" <<EOF
# Starship prompt — Kiro powerline, dual palette
# Docs: https://starship.rs/config/
#
# Powerline theme: requires a Nerd Font in your terminal for the segment
# separators and glyphs (803-apps-setup.sh installs ttf-jetbrains-mono-nerd
# and sets it as the fontconfig "monospace" default). Retheme the whole
# prompt by swapping the \`palette =\` line below — modules reference
# role-based palette keys only (dir_bg, git_fg, ...), never raw colours, so
# every palette controls both its backgrounds AND its text contrast.
#
# Written by 805-starship-setup.sh — re-run that script (after editing
# PALETTE at its top) to switch palettes; re-run with the same PALETTE to
# regenerate this file from scratch.

"\$schema" = 'https://starship.rs/config-schema.json'

# Insert a blank line between shell prompts
add_newline = true

# Active colour palette — swap this one line to re-theme the whole prompt
#   "kiro" = gruvbox dark + orange signature (Kiro default)
#   "tide" = Tide rainbow / Tango palette (jorgebucaran tide colours)
palette = "$PALETTE"

# Segment order + powerline separators. Each \ joins to the next module
# with no gap;  is the sharp transition (Tide's), repeated as the
# end cap. Flat sharp start — no leading cap.
format = """
\$os\\
[](fg:sig_bg bg:user_bg)\\
\$username\\
[](fg:user_bg bg:dir_bg)\\
\$directory\\
[](fg:dir_bg bg:git_bg)\\
\$git_branch\\
[](fg:git_bg bg:lang_bg)\\
\$python\\
\$nodejs\\
\$rust\\
[](fg:lang_bg bg:time_bg)\\
\$time\\
[](fg:time_bg)\\
\$line_break\\
\$character"""

# ── Tide rainbow theme (Tango palette — jorgebucaran/tide) ──────────
# Values lifted from the live \`tide\` install (rainbow preset).
[palettes.tide]
sig_bg   = "#4d4d4d"  # os + username segment background (Tide os_bg)
sig_icon = "#1793d1"  # OS glyph — Arch blue (Tide os_color)
sig_fg   = "#d7af87"  # context tan (unused now username has user_fg)
user_bg  = "#1793d1"  # username segment background — Arch blue
user_fg  = "#ffffff"  # username text — white
dir_bg   = "#3465a4"  # directory — Tango blue (Tide pwd_bg)
dir_fg   = "#e4e4e4"  # directory text — light (Tide pwd dirs)
git_bg   = "#4e9a06"  # git — Tango green (Tide git_bg)
git_fg   = "#000000"  # git text — black (Tide git colours)
lang_bg  = "#c4a000"  # language versions — gold (Tide cmd_duration/gold)
lang_fg  = "#000000"  # language text — black
time_bg  = "#d3d7cf"  # clock — light grey (Tide time_bg)
time_fg  = "#000000"  # clock text — black (Tide time_color)
char_ok  = "#5fd700"  # prompt char success (Tide character_color)
char_err = "#ff0000"  # prompt char failure (Tide character_color_failure)
char_vi  = "#c4a000"  # prompt char in vi command mode

# ── Kiro default theme (gruvbox dark + orange signature) ────────────
[palettes.kiro]
sig_bg   = "#fe8019"  # gruvbox orange — Kiro signature (os + username)
sig_icon = "#fbf1c7"
sig_fg   = "#fbf1c7"
user_bg  = "#fe8019"  # username segment bg — same as sig (no split)
user_fg  = "#fbf1c7"  # username text (gruvbox cream)
dir_bg   = "#d79921"  # gruvbox yellow
dir_fg   = "#fbf1c7"
git_bg   = "#98971a"  # gruvbox green
git_fg   = "#fbf1c7"
lang_bg  = "#689d6a"  # gruvbox aqua
lang_fg  = "#fbf1c7"
time_bg  = "#665c54"
time_fg  = "#fbf1c7"
char_ok  = "#98971a"
char_err = "#fb4934"
char_vi  = "#d79921"

# OS icon — leads the signature segment
[os]
disabled = false
style = "bg:sig_bg fg:sig_icon"

[os.symbols]
Arch = "󰣇"

# Username — always shown as part of the signature segment
[username]
show_always = true
style_user = "bg:user_bg fg:user_fg"
style_root = "bg:user_bg fg:user_fg"
format = '[ \$user ](\$style)'

# Current directory
[directory]
style = "fg:dir_fg bg:dir_bg"
format = "[ \$path ](\$style)"
truncation_length = 3
truncation_symbol = "…/"
read_only = " "

# Git branch — reads .git/HEAD directly, no git command invocation, so
# nothing here reaches repo-local config.
[git_branch]
symbol = ""
style = "bg:git_bg"
format = '[[ \$symbol \$branch ](fg:git_fg bg:git_bg)](\$style)'

# [git_status] (dirty/staged/ahead-behind indicators) is deliberately NOT
# configured here. Unlike \$git_branch above, it has to query git's own
# status machinery on every prompt render in whatever directory you're in
# — that's what lets a malicious repo's .git/config run code just from
# cd-ing in and looking at the prompt (same bug class as CVE-2022-20001 in
# fish's own __fish_git_prompt, still open against starship's git_status
# module upstream: https://github.com/starship/starship/issues/3974).
# \$git_branch alone doesn't share this exposure (plain file read), so
# it's the only git segment in the format above. Add a [git_status] table
# back (see starship's docs) only if you've weighed that tradeoff yourself.

# ── Language / tool versions (shown only in relevant projects) ──
[python]
symbol = ""
style = "bg:lang_bg"
format = '[[ \$symbol( \$version) ](fg:lang_fg bg:lang_bg)](\$style)'

[nodejs]
symbol = ""
style = "bg:lang_bg"
format = '[[ \$symbol( \$version) ](fg:lang_fg bg:lang_bg)](\$style)'

[rust]
symbol = ""
style = "bg:lang_bg"
format = '[[ \$symbol( \$version) ](fg:lang_fg bg:lang_bg)](\$style)'

# Clock — closes the bar
[time]
disabled = false
time_format = "%R"
style = "bg:time_bg"
format = '[[  \$time ](fg:time_fg bg:time_bg)](\$style)'

[line_break]
disabled = false

# Prompt character on the second line
[character]
disabled = false
success_symbol = '[➜](bold fg:char_ok)'
error_symbol = '[➜](bold fg:char_err)'
vimcmd_symbol = '[➜](bold fg:char_vi)'
EOF
    tput setaf 2; echo "  → wrote $STARSHIP_CONF"; tput sgr0
fi

##################################################################################################################################
# Step 3: Wire starship into fish — suppress fish's own greeting banner (it
# clashes visually with the two-line powerline prompt) and source starship's
# init on every interactive shell. Appended to config.fish itself (below
# 803's `source`/fish_add_path lines), not a separate managed block — this
# repo has no equivalent of fish-tweak-tool's "package owns defaults, this
# file is user's own" split, so config.fish is already the right place for a
# straight, idempotent append.
##################################################################################################################################

echo
tput setaf 3
echo "── Wiring starship into fish (config.fish) ────────────────────────────"
tput sgr0

FISH_CONF="$HOME/.config/fish/config.fish"
mkdir -p "$(dirname "$FISH_CONF")"

if grep -qF 'starship init fish' "$FISH_CONF" 2>/dev/null; then
    echo "  → config.fish already sources starship — skipping."
else
    cat >> "$FISH_CONF" <<'FISH_ENTRY'

# starship prompt (see 805-starship-setup.sh)
function fish_greeting; end
type -q starship; and starship init fish | source
FISH_ENTRY
    tput setaf 6; echo "  → added starship init to $FISH_CONF"; tput sgr0
fi

##################################################################################################################################

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename "$0") done"
echo "##############################################################"
echo
tput setaf 2
echo "Prompt active on next fish login (or run 'exec fish' now). Palette: $PALETTE."
echo "Nerd Font glyphs need ttf-jetbrains-mono-nerd (803) as the terminal font —"
echo "if the powerline separators/icons show as boxes, re-check 803 ran first."
echo "git_status intentionally omitted (branch name only) — see this script's"
echo "header comment for why."
tput sgr0
echo
