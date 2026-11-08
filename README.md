# Tailscale Desktop for Omarchy

[日本語](README.ja.md)

A Tailscale bar widget for [Omarchy](https://omarchy.org/) that offers what the
Windows and macOS Tailscale menus offer, in the same order.

> Community plugin, derived from Omarchy's built-in `omarchy.tailscale` widget.
> Not affiliated with Tailscale or Omarchy.

## What's in the panel

1. **Connect** — the on/off switch (right-click the bar icon does the same)
2. **Account** — switch accounts, add an account, log out (press twice), open the admin console
3. **This device** — name, Tailscale IP, MagicDNS name, and when its key expires; copy any of them
4. **Network devices** — split into My devices, Tagged devices, and each other user's devices.
   Offline machines are listed dimmed with when they were last seen. Copy a
   machine's name, DNS name, IPv4 or IPv6, or send it files with Taildrop.
5. **Exit nodes** — None, Recommended (`auto:any`, showing what Tailscale suggests),
   every exit node on the tailnet, Mullvad regions when available, plus
   **Allow local network access** and **Run exit node**
6. **Preferences** — Use Tailscale DNS settings, Use Tailscale subnets, Allow incoming connections
7. **About** — the Tailscale version (and an available update), and **Bug report**, which
   copies the ID `tailscale bugreport` prints

The Windows-only items (Run unattended, Launch at startup) have no Linux
counterpart: `tailscaled` is a systemd service.

## Install

```bash
omarchy plugin add https://github.com/MoomA-0750/omarchy-tailscale-desktop.git --enable
omarchy plugin disable omarchy.tailscale   # hide the built-in widget; tailscaled keeps running
```

### Let the panel change settings

Turning Tailscale on or off and changing any setting needs your user to be
Tailscale's operator. Choose **Authorize Tailscale operator** in the panel
once; it runs `pkexec tailscale set --operator=$USER`. Or from a terminal:

```bash
sudo tailscale set --operator=$USER
```

## Keyboard

| Key | Action |
| --- | --- |
| `j` / `k`, arrows | Move the cursor |
| `Enter` / `Space` | Activate the row |
| `t` | Toggle Tailscale |
| `c` / `n` / `d` | Copy the selected machine's IP / name / DNS name |
| `s` | Send files to the selected machine |
| `/` | Search machines (large tailnets) |
| `Esc` | Close |

## Requirements

- Omarchy with the Quickshell-based `omarchy-shell`
- `tailscale` on `PATH`, `wl-copy` for copying

## Languages

Follows the language picked under Setup > Language. The strings this plugin
adds ship in English and Japanese (`i18n/`); the rest come from Omarchy's own
catalog.

## License

MIT. See [LICENSE](LICENSE).
