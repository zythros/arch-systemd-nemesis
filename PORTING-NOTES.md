# Porting notes: artix-nemesis (OpenRC) → arch-systemd-nemesis (systemd)

This documents exactly what changed going from `zythros/artix-nemesis`
(Artix Linux, OpenRC) to this repo (Arch Linux, systemd), and — more
importantly — *why*, since "just swap `rc-service` for `systemctl`" undersells
how much of artix-nemesis exists specifically to work around things systemd
does natively. Written at port time, 2026-08-21.

## Removed entirely — systemd already does this

- **`lib.sh`'s pacman "nohook" machinery.** artix-nemesis has to run every
  pacman transaction through a hand-rolled config with an empty `HookDir`
  (plus moving `/usr/share/libalpm/hooks` aside) because pacman hooks like
  `dbus-reload.hook` / `dconf-update.hook` / `gvfsd.hook` hang on
  Artix/OpenRC — no guaranteed system D-Bus session while running as root
  during a transaction. On Arch+systemd, `dbus.service` is socket-activated
  and always available, so hooks just run. `pkg_install()` here is a plain
  `pacman -S`.
- **`802`'s `dbus-launch --exit-with-session dwm` session wrapper.** Needed
  on Artix because dwm doesn't start a session bus and nothing else does
  either. On systemd, `pam_systemd` + `dbus-user-session` auto-provision a
  per-login session bus for any greeter session (LightDM included) — a plain
  `Exec=dwm` session file is enough for flameshot and friends to find a bus.
- **`803`'s `podman` shared-root OpenRC service.** artix-nemesis writes a
  custom `/etc/init.d/shared-root` running `mount --make-rshared /` at boot,
  because OpenRC has no equivalent of what systemd's
  `systemd-remount-fs.service` already does unconditionally for the root
  mount at boot. Not needed here at all.
- **Arch `[extra]` repo bootstrapping** (`801`, `880`, `881` all added
  `artix-archlinux-support` + a hand-written `[extra]` section so
  `nvidia-utils` etc. would resolve). This repo *is* Arch — `[extra]` is
  already there. Whole blocks deleted.
- **All `-openrc` companion packages** (`connman-openrc`, `mpd-openrc`,
  `cups-openrc`, `avahi-openrc`, `libvirt-openrc`, `snapper-openrc`,
  `nvidia-utils-openrc`, …). Each Arch package ships its systemd unit(s)
  directly; there's no separate init-integration package to pull in.
- **`870`'s `virt-what` dependency**, used only because
  `systemd-detect-virt` doesn't exist without systemd. Replaced with
  `systemd-detect-virt` itself (ships with the `systemd` package, already
  installed).
- **`861`'s manual `systemd-sysusers`/`systemd-tmpfiles --create` calls.**
  artix-nemesis has to invoke these by hand post-install because the nohook
  pacman config it runs everything through skips the pacman hooks that would
  normally do this. With normal hooks running, this happens automatically —
  moot here, and also moot because 861 no longer runs mpd as a system user
  at all (see below).

## Real fixes that carry over unchanged — not init-system issues

- **`803`'s flameshot `useX11LegacyScreenshot=true` fix.** flameshot's
  portal-based screenshot capture (`org.freedesktop.portal.Screenshot`)
  times out because dwm has no `xdg-desktop-portal` backend implementing it
  — a dwm/minimal-WM gap, not an OpenRC-vs-systemd one. Would happen
  identically here. Kept as-is.
- **`890`/`895` VFIO passthrough and libvirt setup.** Nothing OpenRC-specific
  in either script to begin with; ported essentially unchanged.
- **`830`'s hardened `git pull` failure handling** in the slstatus fork
  clone/update step. General good practice, unrelated to init system.

## Deliberately upgraded, not just translated

- **Networking: `NetworkManager` instead of ConnMan.** artix-nemesis tried
  NetworkManager and abandoned it (see its own `NOTES.md` §8) because
  `/run/NetworkManager` — normally created by `systemd-tmpfiles` at boot —
  doesn't exist under OpenRC, so the daemon couldn't reliably start; it fell
  back to ConnMan (Artix's own default) instead. On Arch+systemd,
  `systemd-tmpfiles` creates that directory natively — NetworkManager is
  the standard choice here, with `nm-connection-editor` as the GUI (still a
  standalone window; dwm has no systray either way).
- **`803`'s gparted: polkit instead of a `sudo` wrapper.** artix-nemesis
  runs gparted via `alacritty -e sudo gparted` because "polkit service not
  available on Artix" (no `elogind`, `pam_systemd`'s login-session
  equivalent). On systemd, `logind` is native and polkit works out of the
  box — the only missing piece for a bare WM like dwm is an authentication
  *agent* to show the GUI prompt, since (unlike GNOME/KDE) dwm doesn't start
  one itself. This repo installs `xfce-polkit` (a lightweight, DE-independent
  agent) and autostarts it via `~/.xprofile`; gparted's own packaged
  `.desktop` (which invokes `gparted-pkexec`) then just works, with a proper
  scoped privilege prompt instead of a blanket `sudo`.
- **`861` MPD: a `systemd --user` service instead of a system service
  patched to run as a regular user.** artix-nemesis runs MPD as an OpenRC
  system service and patches its `command_user=` line plus `chown`s
  `/var/lib/mpd`, purely to get it running as a normal user so it can reach
  the PipeWire socket. On systemd, MPD's package ships a proper `mpd.service`
  *user* unit — the idiomatic path is `systemctl --user enable --now
  mpd.service` with config/data under `~/.config/mpd` and
  `~/.local/share/mpd`. `loginctl enable-linger` replaces the "always
  running regardless of login" behavior the old system-service setup had for
  free.
- **`837`'s RGB-at-boot and `835`'s spacenavd: systemd units instead of
  OpenRC `openrc-run` / `/etc/local.d` scripts.** Mechanical rewrites
  (`Type=oneshot` / `Type=forking` unit files), but worth calling out since
  they're hand-written custom services either way.
- **`840` snapper: systemd timers instead of daemons.** `snapper-timeline`/
  `snapper-cleanup` ship as `.timer` units on the systemd path rather than
  always-running OpenRC services — arguably the more correct model for
  "run hourly" / "run on a schedule" work regardless of init system.

## Left as an open question, same as upstream

- `snapper-rollback` and `spnavcfg` are still AUR-only on Arch too — the
  "don't silently reach for AUR" policy from artix-nemesis carries over
  unchanged, including the same commented-out opt-in pattern gated behind
  `801-chaotic-aur-setup.sh`.
