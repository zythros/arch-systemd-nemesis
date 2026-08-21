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
  `xfce-polkit` (a standalone auth agent, autostarted via `~/.xprofile`)
  instead of a `sudo` wrapper, since systemd's native `logind` makes polkit
  actually work; MPD runs as a `systemd --user` service instead of a system
  service hand-patched to run as a normal user; spacenavd and RGB-at-boot
  got real systemd unit files instead of custom OpenRC scripts; snapper
  uses `.timer` units instead of always-running daemons.
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

## Open / deferred items

- **Nothing in this repo has been run against real hardware yet.** Unlike
  artix-nemesis's `NOTES.md` (which documents fixes confirmed live on
  `artix-pc`), everything here is a desk port — reasoned through carefully,
  syntax-checked, but not empirically verified. Treat first-run output on
  the actual Arch/SDDM machine as the real test, especially:
  - SDDM's native `~/.xprofile` sourcing (wallpaper/slstatus/spice-vdagent
    autostart all depend on it).
  - `xfce-polkit` actually showing a GUI prompt for gparted's
    `gparted-pkexec` desktop entry (depends on the package still shipping
    that policykit-integrated `.desktop` on current Arch).
  - NetworkManager starting cleanly (the whole reason it's used here
    instead of ConnMan is the assumption that systemd-tmpfiles fixes the
    `/run/NetworkManager` gap — should be true, wasn't re-derived from a
    live systemd-tmpfiles.d file for `NetworkManager.conf` specifically).
  - MPD's `systemd --user` service actually reaching the audio device
    without the old `command_user`/`chown /var/lib/mpd` dance.
- `snapper-rollback` and `spnavcfg` are still AUR-only on Arch too — same
  "don't silently reach for AUR" policy as artix-nemesis carries over
  unchanged (opt-in via `801-chaotic-aur-setup.sh` + manual install only).
- Target machine confirmed to be the **same physical hardware as
  artix-nemesis's `artix-pc`, reformatted** (see Environment notes) — so
  the fixed hardware IDs carried over unmodified (`880`'s `DISPLAY_GPU_MODEL
  ="GA106"`, `890`'s GA102 passthrough GPU detection, `836`'s
  `PRINTER_IP="10.0.100.103"`) should still be correct, since they describe
  physical devices/LAN endpoints that don't change on a reformat.
  **Still worth re-confirming, not hardware IDs**: anything reformat-
  sensitive — `895`'s `VM_DISK_DIR="/mnt/vmssd"` mount point, `840`'s BTRFS
  subvolume/`.snapshots` layout assumptions, GRUB vs. systemd-boot choice
  (both `880`/`881`/`890` branch on this) — since a reformat can easily
  change partitioning, mount points, or bootloader even on identical
  hardware.

## Environment notes

- This session's own sandbox (where `git init`/`commit`/`push` actually ran
  from) is a plain systemd Arch Linux box, user `kiro` — same sandbox used
  for artix-nemesis work, not the actual target machine either way.
- `gh` auth: authenticated as GitHub user `zythros`.
- Target machine for this repo: an Arch Linux + systemd + dwm + SDDM
  install on the **same physical machine as artix-nemesis's `artix-pc`,
  reformatted** (confirmed by the user) — not a separate box. Hostname/user
  (`artix-pc`/`artix` on the old install) not yet confirmed for the Arch
  reformat; don't assume they carried over.
