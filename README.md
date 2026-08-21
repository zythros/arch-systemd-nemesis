# arch-systemd-nemesis

Numbered post-install setup scripts for **Arch Linux + systemd + dwm**,
mirroring the run-standalone-or-via-fzf-menu structure of
[`zythros/artix-nemesis`](https://github.com/zythros/artix-nemesis), which
targets Artix Linux + OpenRC + dwm.

Companion repos: [`zythros/dwm`](https://github.com/zythros/dwm) (personal
dwm fork), [`zythros/slstatus`](https://github.com/zythros/slstatus)
(personal slstatus fork).

## Why a separate repo instead of an OpenRC/systemd branch

The two init systems need genuinely different fixes in enough places
(service management, session D-Bus, polkit, tmpfiles/sysusers handling) that
a single script tree with `if [ init = openrc ]` branches everywhere would be
harder to read and trust than two parallel, individually-auditable repos.
See [`PORTING-NOTES.md`](PORTING-NOTES.md) for exactly what changed and why.

## Usage

```
git clone https://github.com/zythros/arch-systemd-nemesis
cd arch-systemd-nemesis
./menu-fzf.sh
```

Or run any numbered script standalone: `./803-apps-setup.sh`.

**Read every script before running it.** These are tailored to one person's
hardware and preferences (GPU models, printer IP, disk paths, package
choices) — treat them as a reference to adapt, not a turnkey installer.

## Layout

- `801`–`895` — numbered setup scripts, runnable standalone or picked via
  `menu-fzf.sh` (order matters for a few: `802` before `820`/`830`; `801`
  before installing anything you want from Chaotic AUR).
- `lib.sh` — shared pacman helpers, sourced by every numbered script.
- `menu-fzf.sh` — fzf multi-select menu that runs chosen scripts in order.
- `kernel-rollback.sh`, `chaotic-aur-removal.sh` — standalone utilities, not
  wired into the menu.

## License

No license file — personal-use scripts shared for reference. Ask before
reusing verbatim in something you're distributing.
