# Project Notes

Status snapshot as of 2026-08-21. Working context for
`zythros/arch-systemd-nemesis` (Arch Linux, systemd, dwm, SDDM) — a
systemd/Arch port of `zythros/artix-nemesis` (Artix Linux, OpenRC, dwm,
LightDM). See that repo's own `NOTES.md` for the full history of what led
to this port (Artix stability concerns tracing back to the systemd-ecosystem
seam, not OpenRC itself being unreliable — NetworkManager/tmpfiles, dbus
session gaps, polkit/elogind gaps).

## Repos involved

- **`zythros/arch-systemd-nemesis`** — this repo. Numbered post-install
  setup scripts (`801`–`895`), same run-standalone-or-via-`menu-fzf.sh`
  structure as artix-nemesis, plus standalone utilities
  (`kernel-rollback.sh`, `chaotic-aur-removal.sh`). `lib.sh` has shared
  pacman helpers (much smaller than artix-nemesis's — see below).
- **`zythros/artix-nemesis`** — the source repo this was ported from. Not
  being deprecated; both repos are maintained in parallel for their
  respective machines/inits. `PORTING-NOTES.md` in this repo documents
  every diff between the two and why.
- **`zythros/dwm`** — personal dwm fork, shared by both repos (same
  `config.h`-based setup; nothing dwm-fork-side is init-system-specific).
- **`zythros/slstatus`** — personal slstatus fork, shared by both repos.

## Recent work this session (chronological)

### 1. Repo created — full port from artix-nemesis in one pass
- User's framing: Artix has been less stable than Arch in some regards;
  asked whether that's the init system. Answer worked through: not OpenRC
  itself (mature, simple) but the *seam* — a growing share of the
  Arch-derived package ecosystem carries implicit systemd assumptions
  (`tmpfiles.d`, `logind`, cgroup delegation, `sd_notify`), Arch only tests
  against systemd, and Artix's much smaller maintenance team has to catch
  and patch each mismatch after the fact. Concrete examples already lived
  in artix-nemesis's own history: the abandoned NetworkManager port (its
  §8) and the manual `dbus-launch` wrapper dwm needed (its §3).
- User asked for a new repo: same script setup, ported to Arch + systemd.
  Naming collision flagged up front — `arch-nemesis` already exists as a
  *different*, unrelated repo (plain Arch + chadwm, different machine,
  noted in artix-nemesis's own `NOTES.md`). Settled on
  **`arch-systemd-nemesis`** after offering alternatives.
- Scope confirmed via question: full port of all 16 scripts + `lib.sh` +
  `menu-fzf.sh` in one pass (not core-first-then-iterate), and create the
  GitHub repo immediately (public, matching artix-nemesis's own visibility)
  rather than staying local-only pending review.
- Read all of artix-nemesis end to end, then rewrote every script. Created
  the repo locally, `git init`, wrote all files, `bash -n` syntax-checked
  every script, committed, `gh repo create zythros/arch-systemd-nemesis
  --public --push`, then renamed the default branch `master` → `main` to
  match artix-nemesis's convention.

### 2. Porting approach — three categories, documented in PORTING-NOTES.md
Full detail lives in the repo's own `PORTING-NOTES.md` (not duplicated
here); summary:
- **Removed entirely** because systemd already does it natively:
  `lib.sh`'s whole pacman-hook-suppression ("nohook") machinery, the
  `dbus-launch` dwm session wrapper, podman's custom `shared-root` OpenRC
  service (`systemd-remount-fs.service` covers it), the Arch `[extra]`
  repo bootstrap (already native on real Arch), every `-openrc` companion
  package, `virt-what` (replaced by systemd's own `systemd-detect-virt`),
  and 861's manual `systemd-sysusers`/`systemd-tmpfiles --create` calls.
- **Kept unchanged** where the fix isn't init-system-related at all: the
  flameshot `useX11LegacyScreenshot=true` fix (dwm/portal-backend gap, not
  OpenRC-vs-systemd), VFIO passthrough, libvirt setup, the hardened
  `git pull` failure handling in slstatus's clone/update step.
- **Deliberately upgraded, not just translated**: NetworkManager replaces
  ConnMan (the `/run/NetworkManager` tmpfiles gap that killed it on OpenRC
  doesn't exist under systemd); gparted goes through `polkit` +
  `xfce-polkit`¹ (a standalone auth agent, autostarted via `~/.xprofile`)
  instead of a `sudo` wrapper, since systemd's native `logind` makes polkit
  actually work; MPD runs as a `systemd --user` service instead of a system
  service hand-patched to run as a normal user; spacenavd and RGB-at-boot
  got real systemd unit files instead of custom OpenRC scripts; snapper
  uses `.timer` units instead of always-running daemons.
  ¹ *Corrected in item 9 below — `xfce-polkit` turned out to be AUR-only;
  swapped for `polkit-gnome`, which is in official Arch repos.*
- These three "upgraded" items are real behavioral changes, not 1:1
  translations — flagged to the user explicitly as worth a second look
  before running `803`/`861` on real hardware, since none of it has been
  verified live yet (see Open items below).

### 3. SDDM correction (user follow-up, same session)
- User: "i should have mentioned the arch install will use sddm instead of
  lightdm." Grepped the whole repo for `LightDM` — found it in `802`
  (writes the xsessions entry), `810`/`820`/`830`/`870` (comments about
  `~/.xprofile` sourcing and PATH propagation), `880` (generic
  "SDDM/LightDM" wording), `PORTING-NOTES.md`.
- **Mechanically this barely mattered**: both SDDM and LightDM read
  `.desktop` session files from `/usr/share/xsessions/`, so `802`'s actual
  write path/logic was untouched — only comments and echo/summary text
  needed correcting to say SDDM.
- Added an explicit new section to `PORTING-NOTES.md` ("Display manager:
  SDDM instead of LightDM") flagging the one real behavioral assumption:
  `~/.xprofile` autostart (used by `810`/`830`/`861`/`870`) relies on SDDM
  sourcing `~/.xprofile` natively before session start — true since SDDM
  0.18, no generic Xsession wrapper needed — but called out as **worth
  spot-checking on first real login** rather than trusting the note blindly,
  since none of this has run on the actual target machine yet.
- Syntax-checked all scripts again after the edits, committed
  (`d4102c7`), pushed.

### 4. Confirmed: same physical machine as artix-nemesis's `artix-pc`, reformatted
- User confirmed this explicitly (not a separate box). Updated the
  hardware-uncertainty note accordingly: fixed hardware IDs carried over
  unmodified from artix-nemesis (`880`'s `DISPLAY_GPU_MODEL="GA106"`,
  `890`'s GA102 passthrough GPU detection, `836`'s
  `PRINTER_IP="10.0.100.103"`) are now **confirmed-good** — they describe
  physical devices/LAN endpoints that don't change on a reformat.
- Narrowed remaining uncertainty to what a reformat genuinely *can* change
  even on identical hardware: `895`'s `VM_DISK_DIR="/mnt/vmssd"` mount
  point, `840`'s BTRFS subvolume/`.snapshots` layout, GRUB-vs-systemd-boot
  choice. Committed (`a40bad8`), pushed.

### 5. Username/hostname — confirmed already handled, added visible banners
- User noted hostname/username will only be decided at Arch install time,
  asked whether scripts check the current username dynamically.
- Audited the whole repo (`grep` for hardcoded `/home/<user>` paths, a
  literal hostname, and confirmed every user-scoped write goes through
  `$USER`/`$HOME`/`whoami`). Result: **already fully dynamic, no changes
  needed to the logic** — this fell out of the `861` MPD rewrite already
  (systemd `--user` service inherently runs as whoever invokes it, so the
  old artix-nemesis `command_user="zythros:audio"` patch + `chown
  zythros:audio /var/lib/mpd` + `chmod 711 /home/zythros` hardcoding
  couldn't survive the port even before this was asked about). `840`'s
  `ALLOW_USERS` already used `$(whoami)`, not a literal name.
- Bootloader (GRUB vs. systemd-boot in `880`/`881`/`890`) and BTRFS
  detection (`840`) were also already runtime-detected (`findmnt`,
  `/boot/loader/loader.conf` vs. `/etc/default/grub` existence checks) —
  nothing install-time-specific hardcoded there either.
- Added visible "Running as: $USER (home: $HOME)" banners to `803` and
  `861`, and an explicit "Detected current user: $CURRENT_USER" echo in
  `840`, purely so this is confirmable at a glance during a live run
  instead of only being correct silently. Committed (`75c35df`), pushed.

### 6. Broader hardcoded-assumption audit (user follow-up: "check the rest")
Grepped the whole repo for IP addresses, kernel-package-name references,
OpenRGB device/zone indices, PCI-address/IOMMU-group literals, subvolume
naming, locale/timezone/keymap, and other absolute-path assumptions beyond
the username/hostname pass in item 5. Three real findings, all fixed:

- **`880`/`881` hardcoded `linux-headers`.** Which kernel flavor
  (`linux`/`linux-lts`/`linux-zen`/`linux-hardened`) an Arch install ends up
  on is itself an install-time decision — `pacman -Q linux-headers` /
  `pacman -S linux-headers` would silently install the *wrong* headers
  package (mismatched to whatever kernel actually booted) on anything but
  vanilla `linux`, breaking DKMS. Added `detect_kernel_pkg()` to `lib.sh`
  (checks which of the four known kernel packages is actually installed);
  both scripts now install `${detected}-headers` instead.
- **`kernel-rollback.sh`'s cache-scan pattern.** Same root issue: the
  `find ... -name 'linux-[0-9]*.pkg.tar.zst'` glob only ever matched the
  vanilla `linux` package, so the whole script would silently find zero
  kernels on `linux-lts`/`-zen`/`-hardened`. Inlined the same
  detect-installed-kernel-flavor logic (kept standalone, not sourcing
  `lib.sh`, matching its original design) and generalized the glob/headers
  pairing. Also replaced the version-string regex used to derive the DKMS
  target kernel version (`sed 's/\.\(arch[^.]*-[0-9]*\)$/-\1/'`, which only
  understood the `linux` package's `.archN-pkgrel` tag convention and would
  silently mis-derive it for other flavors) with reading the real
  `usr/lib/modules/<KVER>` directory name straight out of the package
  archive via `bsdtar -tf` — correct for any flavor without per-flavor
  regex branching, with a fallback + warning if extraction fails.
- **`837`'s `openrgb --device 2 --zone N`.** OpenRGB device indices are
  assigned by *enumeration order*, not a stable hardware ID — genuinely
  not guaranteed to match a previous install's index even on identical
  physical hardware (USB/I2C enumeration timing can vary). Added a
  preflight `openrgb --list-devices` dump during setup (so the actual
  device list for this run is visible in the log) and strengthened the
  comment in the generated boot script to flag the index as something to
  re-verify, rather than silently trusting a carried-over "2".
- Also touched up: `895`'s closing instructions used to print a hardcoded
  `IOMMU group 36: 3f:00.0 + 3f:00.1` — both are stale, install-specific
  facts (PCI bus address and IOMMU grouping can both shift after a
  reformat, e.g. from a BIOS update or ACS-override change, even on
  identical hardware) carried over verbatim from artix-nemesis's own
  machine state. Replaced with a live re-detection (`lspci` for the
  address, `/sys/bus/pci/devices/.../iommu_group` for the group) at the
  point the message is printed, falling back to a manual-lookup command if
  detection fails.
- **Confirmed clean, no changes needed**: no hardcoded subvolume names
  (`@`/`@home`-style), no locale/timezone/keymap references anywhere, no
  hardcoded `/dev/sdX`/`/dev/nvmeX` device paths. `VM_DISK_DIR` (`895`) and
  the BTRFS/`.snapshots` layout assumptions (`840`) remain the two
  legitimately install-time-unknown items — already flagged below, and
  already handled as editable top-of-file config with clear comments
  rather than silent hardcoding.
- `bash -n` syntax-checked all touched files, committed, pushed.

### 7. shellcheck pass (user request: "run shellcheck on all the scripts")
- shellcheck wasn't installed in this session's sandbox and there was no
  sudo access to install it system-wide; fetched the official static
  binary (v0.11.0) from GitHub releases into the scratchpad instead of
  skipping the request.
- Ran at `-S style` (strictest) against all 20 scripts: 60 findings across
  9 rule categories initially. Fixed everything real:
  - `$(basename $0)` unquoted (SC2086) in every script's banners — 34
    instances, cosmetic in practice but cheap to fix.
  - `trap "kill $SUDO_KEEPALIVE ..." EXIT` double-quoted (SC2064) in 5
    scripts — switched to single-quoted (defensive form; functionally
    identical here since the PID is fixed at trap-set time).
  - Three `A && { ... } || { ... }` patterns (SC2015) in 835/837/861,
    where a failure inside the success-block would also trigger the
    failure-block — converted to proper `if`/`then`/`else`.
  - Two indirect `$?` checks (SC2181) in 820/840 — checked directly
    (820's needed restructuring around a heredoc: `if ! python3 - ... <<
    'EOF' ... EOF; then` works fine in bash, `then` just goes on its own
    line after the heredoc terminator).
  - `840`'s `SNAPPER_PACKAGES` was a bare space-separated string expanded
    unquoted (SC2086, the one real non-basename instance) — converted to
    an array, matching how the rest of the repo already handles package
    lists (`803`'s `APPS`, `895`'s `PACKAGES`).
  - `kernel-rollback.sh`: two unquoted expansions inside `${VAR#pattern}`
    (SC2295) — quoted so `KERNEL_PKG` can't be misinterpreted as a glob.
  - Two `ls ... | while read` / `ls ... | head` patterns (SC2012/SC2162)
    in 835/895 — replaced with glob-based `for` loops.
- Left 9 findings (7× SC2088 tilde-in-quotes, 2× SC2016 vars-in-single-
  quotes) as confirmed false positives, not fixed: in `810`/`830` these
  flag `~`/`$HOME` inside strings that are *deliberately* written literally
  into `~/.xprofile`, meant to expand when SDDM sources that file at next
  login — not something this setup script itself should expand now.
  Suppressed with a documented file-level `# shellcheck disable=` comment
  in each (placed before the first real command, so it's file-scoped) so
  they don't come back as noise on a future run, rather than leaving them
  as unexplained warnings.
- `bash -n` and `shellcheck -S style` both exit 0 across all 20 scripts.
  Committed (`d512a6a`), pushed.

### 8. First live evidence from the actual machine: missing-glyph ("tofu") boxes
- User sent two photos from the real target machine via `/remote-control`
  (first live look at this install, not just desk-reasoned): a box-with-`?`
  glyph showing in the dwm/slstatus status bar right before the datetime,
  and the same glyph in fish's prompt specifically *inside a distrobox
  container* (`[arch@bullbox arch]>`).
- Diagnosed as two independent missing-font ("tofu") gaps sharing the same
  symptom, not a script bug: (1) the status bar icon is a Nerd Font
  private-use-area glyph baked into `zythros/slstatus`'s own `config.h`
  (that repo, not this one); (2) the distrobox prompt icon is distrobox's
  own container-indicator emoji, needing an emoji font. Neither font was
  present — traced back to artix-nemesis's own history (§5 there):
  JetBrainsMono Nerd Font was added *and reverted*, but bundled together
  with starship, which the user disliked — the font itself was never
  actually the problem, it just went down with starship.
- User confirmed: add both fonts to `803-apps-setup.sh`. Added
  `ttf-jetbrains-mono-nerd` (verified against archlinux.org's package JSON
  before committing to the name) with a `post_install` case that sets it as
  the fontconfig default for the generic `monospace` family (same
  `fc-match`-verified approach artix-nemesis's reverted attempt used) —
  since alacritty's config and presumably slstatus/dwm both reference
  `"monospace"` rather than a hardcoded font name, this should cover both
  icon sources through one fontconfig alias rather than per-app config.
  Added `noto-fonts-emoji` alongside it (package also verified to exist) —
  no fixup needed, fontconfig's automatic glyph-coverage fallback picks it
  up once installed.
- `bash -n` + `shellcheck -S style` clean on the edited file. Committed,
  pushed.

### 9. Live run of `803` surfaces three AUR-only packages that shouldn't have been there
- User ran `803-apps-setup.sh` for real (via `menu-fzf.sh`) and sent a photo
  of the tail output: `noto-fonts-emoji` installed fine, but the summary
  listed 3 failures — `xfce-polkit`, `mullvad-browser-bin`, `freetube`.
- Checked each against archlinux.org's package search API rather than
  guessing: **all three are AUR-only**, not in any official Arch repo.
  Confirmed via the AUR RPC API too (`xfce-polkit`, `mullvad-browser-bin`,
  `freetube`/`freetube-bin`/`freetube-git` all exist there, none in
  `core`/`extra`/`multilib`). This is a real gap in the original port: I'd
  verified availability rigorously for the two font packages added in item
  8, but never went back and re-verified the rest of the `APPS` list
  inherited from artix-nemesis — this repo's own `pkg_install()` is
  intentionally "official repos only, no AUR fallback," so anything AUR-only
  in `APPS` was always going to silently fail exactly like this.
- Two of the three (`mullvad-browser-bin`, `freetube`) are just apps —
  **commented out**, matching the exact pattern already used for
  `sublime-text-4` (AUR-only, disabled by default, opt in via `801` +
  uncomment). No official-repo substitute exists for either — Mullvad
  Browser and FreeTube are both AUR-packaged-only projects regardless of
  distro.
- `xfce-polkit` is different — it's **load-bearing** for the gparted-via-
  polkit fix designed in item 2/`PORTING-NOTES.md`, not just a convenience
  app, so commenting it out would silently break gparted's auth prompt.
  Searched official Arch repos for a standalone polkit-agent alternative:
  found `polkit-gnome` (in `extra`) — confirmed its actual binary path via
  the package's file listing
  (`/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1`) rather than
  guessing. It's a standalone agent binary despite the package name — no
  GNOME desktop dependency at runtime, same "lightweight agent for a
  DE-less WM" role `xfce-polkit` was meant to fill. Swapped throughout
  `803` (APPS entry, `post_install` case, xprofile autostart line, banner
  text) and in `PORTING-NOTES.md`.
- Didn't stop at the 3 the live run happened to surface — went back and
  checked **every** literal package name referenced anywhere in the repo
  (21 in `803`'s active `APPS`, plus everything else across `802`/`810`/
  `820`/`830`/`835`/`836`/`840`/`861`/`870`/`880`/`881`/`895`) against
  archlinux.org's package API, in bulk. Found two more real bugs, both
  worse than "gracefully skipped" since neither is behind a per-app
  try/warn like `803`'s loop:
  - **`835`'s `spnav`** — not just AUR-only, actually just the *wrong name*.
    The script's own existence-check already tested for both `spnav` and
    `libspnav`, but the actual install command only ever tried `spnav` —
    which doesn't exist under that name in Arch's repos at all. The real
    package is `libspnav` (confirmed in `extra`), and it always installs
    fine under its real name; this line had been silently failing (with a
    caught, non-fatal warning) for no reason. Fixed to install `libspnav`
    directly.
  - **`895`'s `bridge-utils`** — confirmed AUR-only on current Arch
    (deprecated/unmaintained upstream; Arch dropped it from official repos
    at some point). Unlike `803`'s per-app loop, `895` installs its whole
    `PACKAGES` array in one `pacman -S`, and treats *any* failure as fatal
    — so this would have aborted the entire script, not just skipped one
    app. Also confirmed the script never actually calls `brctl` anywhere
    (libvirt manages `virbr0` itself via netlink, not legacy bridge-utils
    tooling) — so it wasn't even needed. Removed from the array entirely.
  - `epson-inkjet-printer-escpr2` (`836`) and `chaotic-keyring`/
    `chaotic-mirrorlist` (`801`/`chaotic-aur-removal.sh`) also don't show up
    in official-repo search, but both are **already correctly handled** —
    the former already has an explicit "AUR-only, not auto-installed"
    fallback warning in the script (matches its own comment, working as
    designed), the latter are intentionally fetched by direct URL from
    Chaotic AUR's own CDN, never expected to be in Arch's official repos.
    No changes needed to either.
- `bash -n` + `shellcheck -S style` clean across the whole repo again after
  all of the above. Committed, pushed.
- **Lesson**: verify every package name against the actual target
  distro's repos before shipping, not just the ones added fresh in a given
  session — an inherited list from a different distro (even a close
  Arch-derivative) can't be assumed correct just because it worked there.

### 10. Re-run confirmed clean after the item 9 fixes
- User pulled the `c4a419e` fixes and re-ran `803` (and/or `895`) on the
  real machine: **confirmed clean — no install failures this time**
  (no more `xfce-polkit`/`mullvad-browser-bin`/`freetube` in the failed
  list; presumably `bridge-utils` no longer aborting `895` either, though
  not explicitly distinguished from `803` in what was confirmed).
- Scope of what's confirmed vs. not, kept precise rather than assumed:
  confirmed is the packages actually installing now (`polkit-gnome`,
  `ttf-jetbrains-mono-nerd`, `noto-fonts-emoji` all succeed).
- **Both follow-ups since confirmed working, visually, on the real
  machine**: tofu boxes are gone from the status bar and distrobox prompt
  (`ttf-jetbrains-mono-nerd`'s fontconfig fix works as designed); gparted
  launched via rofi shows a proper GUI PolicyKit password dialog
  (`polkit-gnome` agent + gparted's packaged `gparted-pkexec` `.desktop`
  entry both confirmed working end-to-end, not just installing cleanly).
  The gparted-via-polkit design from `PORTING-NOTES.md` (item 2 there) is
  now fully live-verified, not just reasoned through.

### 11. Dark theme defaults (user request: apps launching light-themed)
- Root cause, same shape as the tofu-box and polkit gaps: dwm has no
  desktop environment / `xdg-desktop-portal` telling apps "prefer dark" —
  GTK and Qt apps each need it set directly through their own mechanism or
  they default to light.
- Added a new section to `803` (not tied to any single package's
  `post_install`, since it's cross-cutting — same pattern as the alacritty
  config block right before it):
  - **GTK3/GTK4**: `~/.config/gtk-{3,4}.0/settings.ini` with
    `gtk-application-prefer-dark-theme=1` + `gtk-theme-name=Adwaita-dark`,
    plus the equivalent `gsettings set org.gnome.desktop.interface
    color-scheme/gtk-theme` for apps that read GSettings/dconf instead.
    Chose `Adwaita-dark` (via `gnome-themes-extra`) specifically to avoid
    any new AUR risk — no separate "look" opinion beyond dark, given the
    ask was just "prefer dark," not a specific theme.
  - **Qt5/Qt6**: `qt5ct`/`qt6ct`, pointed at their own bundled `darker.conf`
    color scheme (verified both packages ship one via their file listings,
    rather than hand-rolling a custom palette file) plus
    `QT_QPA_PLATFORMTHEME=qt5ct` exported via `~/.xprofile` — confirmed via
    package file listings that both `qt5ct` and `qt6ct` register their
    platform-theme plugin under the same "qt5ct" name, which is why one
    env var covers both Qt5 and Qt6 apps (ArchWiki-documented behavior, not
    independently re-derived from source).
  - `gnome-themes-extra`, `gsettings-desktop-schemas`, `dconf`, `qt5ct`,
    `qt6ct` all verified against archlinux.org's package API before
    committing to the names — same discipline as item 9, not repeating
    that mistake.
  - Explicitly **not covered**: `mullvad-browser` (Firefox-based) — its
    dark mode is a separate per-app toggle in `about:preferences`, not
    reachable by a system-wide GTK/Qt setting. Noted in the script's own
    output, not silently left out.
  - `GTK_DARK_THEME`/`QT_COLOR_SCHEME` are top-of-block variables (same
    pattern as `RGB_COLOR` in `837`, `DISPLAY_GPU_MODEL` in `880`) so a
    different theme/scheme is a one-line edit, not a script rewrite.
- `bash -n` + `shellcheck -S style` clean. Committed, pushed. **Not yet
  run live** — this is desk-reasoned like the rest of a fresh addition
  until confirmed on the actual machine.
- **Confirmed working live**: user pulled, re-ran `803`, and confirmed dark
  mode applied on both a GTK app and a Qt app — meaning the
  `QT_QPA_PLATFORMTHEME=qt5ct` `~/.xprofile` export also survived a fresh
  login as expected. Full item 11 fix verified end-to-end.

### 12. New script: `804-picom-setup.sh` (user request: terminal opacity)
- User asked for `803` to detect bare metal and install picom with terminal
  opacity 90% active / 70% inactive — then, on second thought, asked for it
  as its own script instead of folding into `803`.
- New standalone script, numbered `804` (right after `803-apps-setup.sh`,
  before `810-wallpaper-setup.sh` in both file order and `menu-fzf.sh`).
  Genuinely new to this repo, not a port item — artix-nemesis has no picom
  setup to port from, and dwm itself has no compositor of its own.
- Bare-metal-only via `systemd-detect-virt`, same check `870` uses for
  VM-only gating but inverted (exits 0 with a message if a VM is detected).
  Reasoning: compositing on top of an already-virtualized/passed-through
  display is pure overhead with no payoff for a cosmetic effect.
- Installs `picom` via `pkg_install` (confirmed in official `extra` repo via
  archlinux.org's file listing — same discipline as items 9/11), writes
  `~/.config/picom/picom.conf` with an `opacity-rule` targeting the
  terminal's WM_CLASS (`Alacritty` — alacritty's stock default per 802/803,
  since neither script overrides `window.class`; **not verified against a
  live `xprop`**, flagged in both the script's comments and its closing
  output as something to spot-check), then autostarts picom via
  `~/.xprofile` (same pattern as `803`'s polkit-gnome entry — dwm has no
  session infrastructure of its own to launch a compositor).
- `backend = "xrender"` chosen deliberately over `glx`: this machine has an
  NVIDIA GPU (880/890), and glx compositing on the proprietary NVIDIA driver
  is a known source of tearing/flicker unless separately tuned — xrender is
  slower but reliably "just works" for a plain opacity effect. Left as an
  easy one-line swap if `glx` is later confirmed stable on this hardware.
  `mark-wmwin-focused`/`mark-ovredir-focused` also set, since dwm doesn't
  fully implement the EWMH conventions some WMs rely on for picom's
  `focused` condition to track correctly.
- `TERM_CLASS`/`OPACITY_ACTIVE`/`OPACITY_INACTIVE` are top-of-file config
  variables (same pattern as `RGB_COLOR` in `837`), so retargeting a
  different terminal or opacity level is a one-line edit.
- `bash -n` + `shellcheck -S style -x` clean (fetched the same static
  shellcheck binary approach as item 7, this sandbox still has none
  installed system-wide). Committed (`471ae3f`), pushed. **Not yet run
  live** — desk-reasoned like every fresh addition until confirmed on the
  actual machine, particularly the `Alacritty` WM_CLASS assumption.
- **Live run surfaced a real bug, fixed same session**: user ran it and
  reported the opposite of the intended effect — the *focused* terminal came
  out dimmed, the *unfocused* one came out fully opaque. So the `Alacritty`
  WM_CLASS guess was right (the rule was matching), but focus tracking
  itself was backwards. Root cause: picom's default FocusIn/FocusOut-based
  focus tracking doesn't reliably match dwm's actual focus state. Fix:
  `use-ewmh-active-win = true` — dwm reliably sets/deletes
  `_NET_ACTIVE_WINDOW` on root in its own `focus()` on every change, so
  telling picom to trust that EWMH property instead of raw X focus events is
  the documented fix for exactly this symptom on minimal WMs, not a
  numeric-swap hack papering over the real cause. Idempotency marker in the
  script updated to the new setting (was matching on the opacity-rule text
  itself, which hadn't changed, so it would've skipped regeneration on a
  re-run without this). `bash -n` + `shellcheck -S style -x` clean,
  committed (`a6844c1`), pushed. **Not yet re-confirmed live** — the
  original bug was caught live, but this fix itself hasn't been re-run on
  the machine yet.

## Open / deferred items

- **First live evidence arrived in item 8 above** — the target machine is
  confirmed up and running dwm + slstatus + distrobox + fish already (at
  least some of `802`/`830`/etc. have been run for real), so this is no
  longer a purely desk-reasoned port. Item 10 confirmed `803`/`895` install
  cleanly, and both the font fix and the gparted-via-polkit fix are now
  confirmed visually working too (see item 10). Still open, not yet
  confirmed:
  - SDDM's native `~/.xprofile` sourcing (wallpaper/slstatus/spice-vdagent
    autostart all depend on it) — implicitly confirmed now that slstatus is
    visibly running, and further confirmed by item 11's Qt env var actually
    surviving a fresh login (that only works because SDDM sources
    `~/.xprofile`), so this is effectively confirmed now too.
  - NetworkManager starting cleanly (the whole reason it's used here
    instead of ConnMan is the assumption that systemd-tmpfiles fixes the
    `/run/NetworkManager` gap — should be true, wasn't re-derived from a
    live systemd-tmpfiles.d file for `NetworkManager.conf` specifically).
  - MPD's `systemd --user` service actually reaching the audio device
    without the old `command_user`/`chown /var/lib/mpd` dance.
  - `837`'s new `--list-devices` preflight actually showing device 2 as
    the motherboard on this install — confirm, don't assume.
  - `804`'s picom opacity rule: the `Alacritty` WM_CLASS match is confirmed
    (item 12 — the rule was applying, just backwards), but the
    `use-ewmh-active-win` fix for correct focused/unfocused direction hasn't
    been re-run live yet.
- `snapper-rollback` and `spnavcfg` are still AUR-only on Arch too — same
  "don't silently reach for AUR" policy as artix-nemesis carries over
  unchanged (opt-in via `801-chaotic-aur-setup.sh` + manual install only).
- Still genuinely install-time-unknown, not auto-detectable the way
  username/kernel-flavor were: `895`'s `VM_DISK_DIR="/mnt/vmssd"` mount
  point, `840`'s BTRFS subvolume/`.snapshots` layout, GRUB-vs-systemd-boot
  choice (already runtime-*detected* where it matters in `880`/`881`/`890`,
  just can't be known ahead of time). These are edited-by-hand top-of-file
  config values or already-dynamic detections, not silent assumptions —
  just flagging that a reformat can change them even on identical hardware.
- shellcheck isn't wired into CI or a pre-commit hook — it was run manually
  this session against a point-in-time snapshot. Future edits to any
  script won't be automatically re-checked; worth a GitHub Actions
  workflow (`koalaman/shellcheck-precommit` or just installing the distro
  package and running it in CI) if this repo keeps getting edited, rather
  than relying on remembering to re-run it by hand.

## Environment notes

- This session's own sandbox (where `git init`/`commit`/`push` actually ran
  from) is a plain systemd Arch Linux box, user `kiro` — same sandbox used
  for artix-nemesis work, not the actual target machine either way.
- `gh` auth: authenticated as GitHub user `zythros`.
- Target machine for this repo: an Arch Linux + systemd + dwm + SDDM
  install on the **same physical machine as artix-nemesis's `artix-pc`,
  reformatted** (confirmed by the user) — not a separate box. Hostname/user
  (`artix-pc`/`artix` on the old install) not yet confirmed for the Arch
  reformat; don't assume they carried over. Kernel flavor also not yet
  confirmed — scripts now detect it rather than assuming vanilla `linux`
  (see item 6 above).
