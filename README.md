# Debian Post-Install

Post-install scripts for Debian 13 (Trixie) with GNOME. Two independent tools in one repo:

- **battery-optimizer/** — Cuts laptop power draw from ~21W to ~8W on battery (Intel + NVIDIA)
- **desktop-setup/** — Full GNOME desktop customization (themes, extensions, terminal, etc.)

Each one works standalone. Use both or just the one you need.

<!-- TODO: Add screenshot of full desktop here -->
<!-- ![Desktop](screenshots/desktop.png) -->

---

## Battery Optimizer

Intelligent power management for laptops with Intel hybrid CPUs and NVIDIA dedicated GPUs. Automatically switches between performance (AC) and power-saving (battery) profiles.

### What it does

| Optimization | Power saved | How |
|---|---|---|
| NVIDIA GPU shutdown | 8-15W | Unloads modules + PCI remove on battery, reloads on AC |
| CPU core management | 1-3W | Disables half the threads on battery |
| TLP aggressive profile | 2-5W | CPU throttle, ASPM powersupersave, WiFi power save |
| Memory optimization | ~1W | Zram with aggressive swappiness |
| Background bloat killer | ~1W | Stops gnome-software and packagekit on battery |
| iGPU compositor | ~2W | Forces Mutter to Intel GPU only |

**Result:** 2-3h battery life becomes 6-7h.

### How it works

```
AC plugged in                    Battery (unplugged)
─────────────                    ───────────────────
All 16 threads active            8 threads only (P-cores)
NVIDIA loaded + D3 idle          NVIDIA completely removed from PCI bus
CPU boost ON                     CPU boost OFF, max 50%
Performance profile              Low-power profile
```

The switch is automatic via udev rules — plug/unplug the charger and it applies instantly. A systemd service applies the correct profile at boot.

### Install

```bash
cd battery-optimizer
sudo ./install.sh           # Interactive — choose what to enable
sudo ./install.sh --status  # Check current state
sudo ./install.sh --remove  # Uninstall everything
```

### Compatibility

- Debian 13+ (Trixie) with GNOME/Wayland
- Intel 12th-14th gen hybrid CPUs (P-cores + E-cores)
- NVIDIA RTX 3000/4000 series with proprietary drivers
- Should work on Ubuntu 24.04+ and derivatives with minor adjustments

### Recovery

If something goes wrong:

```bash
sudo battery-optimizer-recover.sh   # Restore all cores + NVIDIA
```

Or from TTY (Ctrl+Alt+F3):

```bash
# Re-enable all CPU cores
for i in $(seq 1 15); do echo 1 > /sys/devices/system/cpu/cpu$i/online; done

# Remove NVIDIA blacklist and reload
rm /etc/modprobe.d/zz-nvidia-blacklist.conf
modprobe -i nvidia
```

---

## Desktop Setup

Full GNOME desktop customization in one script. Modular — pick what you want.

<!-- TODO: Add screenshots -->
<!-- ![GNOME Desktop](screenshots/gnome-desktop.png) -->
<!-- ![Top Bar](screenshots/top-bar.png) -->
<!-- ![Kitty Terminal](screenshots/kitty.png) -->
<!-- ![Conky](screenshots/conky.png) -->

### Modules

| # | Module | What it installs |
|---|--------|-----------------|
| 1 | **Packages** | TLP, Papirus icons, GNOME Tweaks, multimedia codecs, zram-tools |
| 2 | **TLP config** | Optimized battery profile (CPU throttle, ASPM, WiFi power save) |
| 3 | **Fonts** | JetBrains Mono Nerd Font (from GitHub releases) |
| 4 | **GTK Themes** | WhiteSur-Dark + Papirus icons + Sweet cursors |
| 5 | **Wallpaper** | Included wallpaper applied to both light/dark mode |
| 6 | **GNOME Extensions** | 22 extensions (see list below) |
| 7 | **GNOME Config** | Full dconf import — themes, fonts, keybindings, extension settings |
| 8 | **GRUB Theme** | Darkmatter boot theme |
| 9 | **Zram** | Compressed RAM swap with zstd, aggressive swappiness |
| 10 | **Battery Optimizer** | Runs `battery-optimizer/install.sh` (laptop only) |
| 11 | **Kitty Terminal** | Dracula theme, splits, tab bar, dashboard layouts |
| 12 | **Zsh** | Oh My Zsh + Powerlevel10k + autosuggestions + syntax-highlighting + zoxide |
| 13 | **Conky** | Mimosa Dark desktop monitor (clock, weather, CPU, network, music) |
| 14 | **Firewall** | ufw — deny incoming, allow SSH/Tailscale/GSConnect |
| 15 | **SSD Optimization** | fstab noatime + commit=60, fstrim weekly timer |
| 16 | **Sysctl Dev** | inotify watches 524K, file-max 2M, TCP reuse, network buffers |

### GNOME Extensions included

| Extension | What it does |
|-----------|-------------|
| Blur My Shell | Glass effect on overview and panel |
| Dash to Dock | macOS-style dock at bottom |
| Desktop Cube | 3D workspace transitions |
| OpenBar | Fully customizable top bar (islands style) |
| Space Bar | Workspace indicator in top bar |
| Just Perfection | Fine-tune every GNOME Shell element |
| Rounded Window Corners | Rounded corners on all windows |
| Compiz Magic Lamp | Magic lamp minimize animation |
| Compiz Windows Effect | Wobbly windows |
| Search Light | Spotlight-style app search |
| Vitals | CPU, RAM, GPU, battery stats in top bar |
| Clipboard History | Clipboard manager |
| Top Bar Organizer | Reorder top bar elements |
| Transparent Top Bar | Transparent bar when no window maximized |
| User Theme | Load custom shell themes |
| Executor | Run shell commands in top bar |
| Extension List | Quick access to enable/disable extensions |
| Useless Gaps | Window gaps for aesthetics |
| DDC Brightness | External monitor brightness control |
| Battery Monitor | Detailed battery info |
| Battery Time | Time remaining estimate |
| Colorful Battery | Color-coded battery indicator |

### Install

```bash
cd desktop-setup
./setup.sh              # Interactive — choose modules
./setup.sh --all        # Install everything
./setup.sh --status     # See what's installed
./setup.sh --remove     # Uninstall customizations
```

### Customization

The script is designed to be forked and modified:

- **Wallpaper:** Replace `assets/wallpapers/macWallpaper.jpg` with yours
- **GNOME config:** Export your own with `dconf dump / > configs/gnome/dconf-full.ini`
- **Kitty config:** Edit `configs/kitty/kitty.conf`
- **TLP config:** Edit `configs/tlp/01-battery-optimized.conf`
- **Conky theme:** Swap `configs/conky/Mimosa/` with any Conky theme
- **Extensions list:** Edit the `EXTENSIONS` array in `setup.sh`

---

## Compatibility

| | Supported |
|---|---|
| **OS** | Debian 13 (Trixie), should work on Debian 12+, Ubuntu 24.04+ |
| **Desktop** | GNOME 43+ with Wayland |
| **Hardware** | Any x86_64 (battery-optimizer requires Intel + NVIDIA) |
| **Updates** | Safe to re-run after system updates |

## Re-running

Both scripts are idempotent. Running them again will:
- Skip already installed components
- Update configs to latest version
- Not break existing customizations

## Project structure

```
debian-post-install/
├── README.md
├── LICENSE
├── screenshots/             # Add your screenshots here
├── battery-optimizer/
│   └── install.sh           # Standalone battery optimization script
└── desktop-setup/
    ├── setup.sh             # Main desktop customization script
    ├── assets/
    │   └── wallpapers/
    ├── configs/
    │   ├── conky/Mimosa/    # Conky theme + fonts + scripts
    │   ├── gnome/           # dconf export
    │   ├── kitty/           # Kitty terminal config + dashboards
    │   └── tlp/             # TLP battery profile
    └── ...
```

## License

MIT
