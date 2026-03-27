#!/bin/bash
#
# MRTX Debian Post-Install Setup
# Personaliza una instalación limpia de Debian 13 (Trixie) con GNOME.
#
# Incluye: temas, iconos, fuentes, extensiones GNOME, TLP, GRUB theme,
#           configuración dconf completa.
#
# Uso:
#   ./setup.sh              # Instalación interactiva
#   ./setup.sh --all        # Instalar todo sin preguntar
#   ./setup.sh --remove     # Desinstalar personalizaciones
#   ./setup.sh --status     # Ver qué está instalado
#
# Compatible con Debian 13+ y actualizaciones menores.
# Re-ejecutable: puede correrse múltiples veces sin problemas.

set -euo pipefail

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STAMP_FILE="$HOME/.local/share/mrtx-setup/installed"

# --- Colores ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${BLUE}[*]${NC} $1"; }
ok()    { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[x]${NC} $1"; }
ask()   { echo -en "${CYAN}[?]${NC} $1 "; }

die() { err "$1"; exit 1; }

# --- Verificaciones ---
check_debian() {
    if [ ! -f /etc/os-release ]; then
        die "No se detectó /etc/os-release"
    fi
    . /etc/os-release
    if [[ "$ID" != "debian" ]]; then
        die "Este script es para Debian. Detectado: $ID"
    fi
    if [[ "${VERSION_CODENAME:-}" != "trixie" ]] && [[ "${VERSION_ID:-0}" -lt 13 ]]; then
        warn "Diseñado para Debian 13 (Trixie). Detectado: ${PRETTY_NAME:-desconocido}"
        ask "Continuar de todas formas? [y/N]"
        read -r ans
        [[ "${ans,,}" == "y" ]] || exit 0
    fi
    ok "Debian $(cat /etc/debian_version) detectado"
}

check_gnome() {
    if ! command -v gnome-shell &>/dev/null; then
        die "GNOME Shell no detectado. Este script requiere GNOME."
    fi
    GNOME_VER=$(gnome-shell --version | grep -oP '\d+' | head -1)
    ok "GNOME Shell $GNOME_VER detectado"
}

check_internet() {
    if ! ping -c 1 -W 3 1.1.1.1 &>/dev/null; then
        die "Sin conexión a internet"
    fi
}

# ============================================================
# MÓDULO 1: Paquetes base
# ============================================================
install_packages() {
    info "Instalando paquetes base..."

    local PKGS=(
        # Power management
        tlp
        tlp-rdw
        # GNOME tools
        gnome-tweaks
        gnome-shell-extension-prefs
        dconf-cli
        # Temas e iconos
        papirus-icon-theme
        # Fuentes
        fonts-jetbrains-mono
        # Utilidades
        curl
        wget
        git
        unzip
        zram-tools
        # Multimedia codecs
        gstreamer1.0-plugins-bad
        gstreamer1.0-plugins-ugly
        gstreamer1.0-libav
    )

    sudo apt update -qq
    sudo apt install -y "${PKGS[@]}" 2>&1 | tail -3

    # Habilitar TLP
    sudo systemctl enable --now tlp.service 2>/dev/null || true

    ok "Paquetes base instalados"
}

# ============================================================
# MÓDULO 2: TLP (optimización de batería)
# ============================================================
install_tlp_config() {
    info "Aplicando configuración TLP optimizada..."

    local TLP_CONF="$SCRIPT_DIR/configs/tlp/01-battery-optimized.conf"
    if [ ! -f "$TLP_CONF" ]; then
        warn "No se encontró configs/tlp/01-battery-optimized.conf, saltando TLP"
        return
    fi

    sudo mkdir -p /etc/tlp.d
    sudo cp "$TLP_CONF" /etc/tlp.d/01-battery-optimized.conf
    sudo tlp start 2>/dev/null || true

    ok "TLP configurado"
}

# ============================================================
# MÓDULO 3: Fuentes (JetBrains Mono Nerd Font)
# ============================================================
install_fonts() {
    info "Instalando JetBrains Mono Nerd Font..."

    local FONT_DIR="$HOME/.local/share/fonts/JetBrainsMono"

    # Si ya está instalada, saltar
    if [ -d "$FONT_DIR" ] && [ "$(ls -1 "$FONT_DIR"/*.ttf 2>/dev/null | wc -l)" -gt 5 ]; then
        ok "JetBrains Mono Nerd Font ya instalada"
        return
    fi

    mkdir -p "$FONT_DIR"
    local TMP_DIR=$(mktemp -d)

    # Descargar última versión de Nerd Fonts
    local NF_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
    info "  Descargando desde GitHub..."
    if curl -sL "$NF_URL" -o "$TMP_DIR/JetBrainsMono.zip"; then
        unzip -qo "$TMP_DIR/JetBrainsMono.zip" -d "$FONT_DIR"
        fc-cache -f "$FONT_DIR" 2>/dev/null
        ok "JetBrains Mono Nerd Font instalada"
    else
        warn "No se pudo descargar la fuente. Instala manualmente desde nerdfonts.com"
    fi
    rm -rf "$TMP_DIR"
}

# ============================================================
# MÓDULO 4: Temas GTK (WhiteSur)
# ============================================================
install_themes() {
    info "Instalando temas..."

    # --- WhiteSur GTK Theme ---
    if [ -d "$HOME/.themes/WhiteSur-Dark" ]; then
        ok "WhiteSur-Dark ya instalado"
    else
        info "  Instalando WhiteSur GTK Theme..."
        local TMP_DIR=$(mktemp -d)
        git clone --depth=1 https://github.com/vinceliuice/WhiteSur-gtk-theme.git "$TMP_DIR/whitesur" 2>/dev/null
        cd "$TMP_DIR/whitesur"
        ./install.sh -c Dark -l 2>/dev/null || ./install.sh 2>/dev/null
        cd "$SCRIPT_DIR"
        rm -rf "$TMP_DIR"
        ok "WhiteSur-Dark instalado"
    fi

    # --- Sweet Cursors ---
    if [ -d "$HOME/.icons/Sweet-cursors" ]; then
        ok "Sweet-cursors ya instalado"
    else
        info "  Instalando Sweet Cursors..."
        local TMP_DIR=$(mktemp -d)
        local SWEET_URL="https://github.com/EliverLara/Sweet/releases/latest/download/Sweet-cursors.tar.xz"
        if curl -sL "$SWEET_URL" -o "$TMP_DIR/sweet.tar.xz" 2>/dev/null; then
            mkdir -p "$HOME/.icons"
            tar -xf "$TMP_DIR/sweet.tar.xz" -C "$HOME/.icons/"
            ok "Sweet-cursors instalado"
        else
            # Alternativa: descargar desde el repo directamente
            git clone --depth=1 https://github.com/EliverLara/Sweet.git "$TMP_DIR/sweet-repo" 2>/dev/null
            if [ -d "$TMP_DIR/sweet-repo/kde/cursors/Sweet-cursors" ]; then
                cp -r "$TMP_DIR/sweet-repo/kde/cursors/Sweet-cursors" "$HOME/.icons/"
                ok "Sweet-cursors instalado"
            else
                warn "No se pudo instalar Sweet-cursors"
            fi
        fi
        rm -rf "$TMP_DIR"
    fi

    # Papirus ya se instala via apt en install_packages
    ok "Temas listos"
}

# ============================================================
# MÓDULO 5: Wallpaper
# ============================================================
install_wallpaper() {
    info "Configurando wallpaper..."

    local WP_SRC="$SCRIPT_DIR/assets/wallpapers/macWallpaper.jpg"
    local WP_DST="$HOME/.local/share/backgrounds/macWallpaper.jpg"

    if [ ! -f "$WP_SRC" ]; then
        warn "No se encontró assets/wallpapers/macWallpaper.jpg, saltando wallpaper"
        return
    fi

    mkdir -p "$HOME/.local/share/backgrounds"
    cp "$WP_SRC" "$WP_DST"

    # Se aplica via dconf en el módulo de GNOME settings
    ok "Wallpaper copiado"
}

# ============================================================
# MÓDULO 6: Extensiones GNOME
# ============================================================
install_gnome_extensions() {
    info "Instalando extensiones GNOME..."

    # Extensiones a instalar (UUID)
    # Solo las que realmente están habilitadas y son útiles
    local EXTENSIONS=(
        "blur-my-shell@aunetx"
        "clipboard-history@alexsaveau.dev"
        "compiz-alike-magic-lamp-effect@hermes83.github.com"
        "compiz-windows-effect@hermes83.github.com"
        "dash-to-dock@micxgx.gmail.com"
        "desktop-cube@schneegans.github.com"
        "just-perfection-desktop@just-perfection"
        "openbar@neuromorph"
        "rounded-window-corners@fxgn"
        "search-light@icedman.github.com"
        "space-bar@luchrioh"
        "top-bar-organizer@julian.gse.jsts.xyz"
        "transparent-top-bar@zhanghai.me"
        "user-theme@gnome-shell-extensions.gcampax.github.com"
        "Vitals@CoreCoding.com"
        "extension-list@tu.berry"
        "executor@raujonas.github.io"
        "useless-gaps@pimsnel.com"
        "display-brightness-ddcutil@themightydeity.github.com"
        "battery-monitor@vjay.github.io"
        "batterytime@typeof.pw"
        "colorful-battery-indicator@aneruam"
    )

    local EXT_DIR="$HOME/.local/share/gnome-shell/extensions"
    mkdir -p "$EXT_DIR"

    local GNOME_VER=$(gnome-shell --version | grep -oP '\d+' | head -1)
    local INSTALLED=0
    local SKIPPED=0

    for uuid in "${EXTENSIONS[@]}"; do
        if [ -d "$EXT_DIR/$uuid" ]; then
            ((SKIPPED++))
            continue
        fi

        # Buscar en extensions.gnome.org
        local info_url="https://extensions.gnome.org/extension-info/?uuid=${uuid}&shell_version=${GNOME_VER}"
        local ext_info
        ext_info=$(curl -sf "$info_url" 2>/dev/null) || {
            # Intentar sin versión específica
            ext_info=$(curl -sf "https://extensions.gnome.org/extension-info/?uuid=${uuid}" 2>/dev/null) || {
                warn "  No se encontró: $uuid"
                continue
            }
        }

        local download_url
        download_url=$(echo "$ext_info" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ver = d.get('shell_version_map', {})
# Buscar la versión más cercana
for v in ['${GNOME_VER}', '${GNOME_VER}.0']:
    if v in ver:
        print(ver[v]['pk'])
        sys.exit(0)
# Si no, usar la última disponible
if ver:
    print(list(ver.values())[-1]['pk'])
" 2>/dev/null) || {
            warn "  No se pudo obtener versión compatible: $uuid"
            continue
        }

        if [ -n "$download_url" ]; then
            local zip_url="https://extensions.gnome.org/download-extension/${uuid}.shell-extension.zip?version_tag=${download_url}"
            local tmp_zip=$(mktemp --suffix=.zip)

            if curl -sL "$zip_url" -o "$tmp_zip" 2>/dev/null; then
                mkdir -p "$EXT_DIR/$uuid"
                unzip -qo "$tmp_zip" -d "$EXT_DIR/$uuid" 2>/dev/null
                ((INSTALLED++))
            else
                warn "  Error descargando: $uuid"
            fi
            rm -f "$tmp_zip"
        fi
    done

    ok "Extensiones: $INSTALLED nuevas, $SKIPPED ya existentes"

    # Habilitar extensiones via gsettings
    info "Habilitando extensiones..."
    local ENABLED_LIST=(
        "blur-my-shell@aunetx"
        "clipboard-history@alexsaveau.dev"
        "compiz-alike-magic-lamp-effect@hermes83.github.com"
        "compiz-windows-effect@hermes83.github.com"
        "dash-to-dock@micxgx.gmail.com"
        "desktop-cube@schneegans.github.com"
        "just-perfection-desktop@just-perfection"
        "openbar@neuromorph"
        "rounded-window-corners@fxgn"
        "search-light@icedman.github.com"
        "space-bar@luchrioh"
        "top-bar-organizer@julian.gse.jsts.xyz"
        "transparent-top-bar@zhanghai.me"
        "user-theme@gnome-shell-extensions.gcampax.github.com"
        "Vitals@CoreCoding.com"
        "extension-list@tu.berry"
        "executor@raujonas.github.io"
        "useless-gaps@pimsnel.com"
        "display-brightness-ddcutil@themightydeity.github.com"
        "battery-monitor@vjay.github.io"
        "batterytime@typeof.pw"
        "colorful-battery-indicator@aneruam"
    )

    local ext_str="["
    for ext in "${ENABLED_LIST[@]}"; do
        ext_str+="'$ext', "
    done
    ext_str="${ext_str%, }]"

    gsettings set org.gnome.shell enabled-extensions "$ext_str" 2>/dev/null || true
    gsettings set org.gnome.shell disable-user-extensions false 2>/dev/null || true

    ok "Extensiones habilitadas"
}

# ============================================================
# MÓDULO 7: Configuración GNOME (dconf)
# ============================================================
apply_gnome_settings() {
    info "Aplicando configuración GNOME..."

    local DCONF_FILE="$SCRIPT_DIR/configs/gnome/dconf-full.ini"
    if [ ! -f "$DCONF_FILE" ]; then
        warn "No se encontró configs/gnome/dconf-full.ini, aplicando settings mínimos..."
        apply_minimal_gnome_settings
        return
    fi

    # Importar dconf completo
    dconf load / < "$DCONF_FILE"

    # Actualizar paths del wallpaper al usuario actual
    local WP_PATH="file://$HOME/.local/share/backgrounds/macWallpaper.jpg"
    gsettings set org.gnome.desktop.background picture-uri "$WP_PATH" 2>/dev/null || true
    gsettings set org.gnome.desktop.background picture-uri-dark "$WP_PATH" 2>/dev/null || true

    ok "Configuración GNOME aplicada"
}

apply_minimal_gnome_settings() {
    # Tema oscuro
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    gsettings set org.gnome.desktop.interface gtk-theme 'WhiteSur-Dark'
    gsettings set org.gnome.desktop.interface icon-theme 'Papirus'
    gsettings set org.gnome.desktop.interface cursor-theme 'Sweet-cursors'
    gsettings set org.gnome.desktop.interface accent-color 'teal'

    # Fuentes
    gsettings set org.gnome.desktop.interface font-name 'JetBrainsMono Nerd Font Mono Semi-Bold 13'
    gsettings set org.gnome.desktop.interface document-font-name 'JetBrainsMono Nerd Font Semi-Bold 13'
    gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrainsMono Nerd Font Semi-Bold Italic 11'

    # Fuentes rendering
    gsettings set org.gnome.desktop.interface font-antialiasing 'grayscale'
    gsettings set org.gnome.desktop.interface font-hinting 'medium'

    # Animaciones
    gsettings set org.gnome.desktop.interface enable-animations true

    # Batería en top bar
    gsettings set org.gnome.desktop.interface show-battery-percentage true

    # Wallpaper
    local WP_PATH="file://$HOME/.local/share/backgrounds/macWallpaper.jpg"
    gsettings set org.gnome.desktop.background picture-uri "$WP_PATH" 2>/dev/null || true
    gsettings set org.gnome.desktop.background picture-uri-dark "$WP_PATH" 2>/dev/null || true
    gsettings set org.gnome.desktop.background picture-options 'zoom'

    # Teclado ES + GB
    gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'es'), ('xkb', 'gb')]"

    # Notificaciones: no banners
    gsettings set org.gnome.desktop.notifications show-banners false

    # Shell theme
    gsettings set org.gnome.shell.extensions.user-theme name 'WhiteSur-Dark' 2>/dev/null || true

    # Dock apps
    gsettings set org.gnome.shell favorite-apps "['org.gnome.Nautilus.desktop', 'org.gnome.Settings.desktop']"

    ok "Settings mínimos aplicados"
}

# ============================================================
# MÓDULO 8: GRUB Theme (darkmatter)
# ============================================================
install_grub_theme() {
    info "Instalando tema GRUB (darkmatter)..."

    if [ -d /boot/grub/themes/darkmatter ]; then
        ok "Tema GRUB darkmatter ya instalado"
        return
    fi

    local TMP_DIR=$(mktemp -d)
    git clone --depth=1 https://gitlab.com/VandalByte/darkmatter-grub-theme.git "$TMP_DIR/darkmatter" 2>/dev/null || {
        # Alternativa: GitHub mirror
        git clone --depth=1 https://github.com/VandalByte/darkmatter-grub-theme.git "$TMP_DIR/darkmatter" 2>/dev/null || {
            warn "No se pudo descargar el tema GRUB"
            rm -rf "$TMP_DIR"
            return
        }
    }

    sudo mkdir -p /boot/grub/themes/darkmatter
    if [ -d "$TMP_DIR/darkmatter/darkmatter" ]; then
        sudo cp -r "$TMP_DIR/darkmatter/darkmatter/"* /boot/grub/themes/darkmatter/
    elif [ -f "$TMP_DIR/darkmatter/theme.txt" ]; then
        sudo cp -r "$TMP_DIR/darkmatter/"* /boot/grub/themes/darkmatter/
    fi

    # Configurar GRUB
    if ! grep -q 'darkmatter' /etc/default/grub 2>/dev/null; then
        echo 'GRUB_THEME="/boot/grub/themes/darkmatter/theme.txt"' | sudo tee -a /etc/default/grub >/dev/null
    fi
    sudo update-grub 2>/dev/null || true

    rm -rf "$TMP_DIR"
    ok "Tema GRUB instalado"
}

# ============================================================
# MÓDULO 9: Zram (compresión RAM)
# ============================================================
configure_zram() {
    info "Configurando zram..."

    # zram-tools se instala via apt
    if [ -f /etc/default/zramswap ]; then
        sudo sed -i 's/^#\?ALGO=.*/ALGO=zstd/' /etc/default/zramswap 2>/dev/null || true
        sudo sed -i 's/^#\?PERCENT=.*/PERCENT=50/' /etc/default/zramswap 2>/dev/null || true
        sudo systemctl restart zramswap 2>/dev/null || true
        ok "Zram configurado (zstd, 50%)"
    else
        warn "zramswap no encontrado"
    fi

    # Swappiness más agresivo
    if ! grep -q 'vm.swappiness=150' /etc/sysctl.d/99-zram.conf 2>/dev/null; then
        echo 'vm.swappiness=150' | sudo tee /etc/sysctl.d/99-zram.conf >/dev/null
        sudo sysctl -p /etc/sysctl.d/99-zram.conf 2>/dev/null || true
    fi
}

# ============================================================
# MÓDULO 10: Battery Optimizer (Intel+NVIDIA power management)
# ============================================================
install_battery_optimizer() {
    info "Ejecutando Battery Optimizer (gestión GPU/CPU en batería)..."

    local BOPT_SCRIPT="$SCRIPT_DIR/../battery-optimizer/install.sh"
    if [ ! -f "$BOPT_SCRIPT" ]; then
        warn "No se encontró ../battery-optimizer/install.sh, saltando"
        return
    fi

    # Verificar que hay hardware compatible (laptop con batería)
    if [ ! -d /sys/class/power_supply/BAT0 ] && [ ! -d /sys/class/power_supply/BAT1 ]; then
        warn "No se detectó batería. Battery Optimizer es solo para laptops."
        return
    fi

    # El battery optimizer necesita root
    if [ "$(id -u)" -ne 0 ]; then
        info "Battery Optimizer necesita root. Ejecutando con sudo..."
        sudo bash "$BOPT_SCRIPT"
    else
        bash "$BOPT_SCRIPT"
    fi

    ok "Battery Optimizer ejecutado"
}

# ============================================================
# MÓDULO 11: Kitty Terminal
# ============================================================
install_kitty() {
    info "Configurando Kitty terminal..."

    # Instalar kitty si no existe
    if ! command -v kitty &>/dev/null; then
        info "  Instalando Kitty..."
        curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin launch=n 2>/dev/null
        mkdir -p "$HOME/.local/bin"
        ln -sf "$HOME/.local/kitty.app/bin/kitty" "$HOME/.local/bin/kitty"
        ln -sf "$HOME/.local/kitty.app/bin/kitten" "$HOME/.local/bin/kitten"

        # Desktop integration
        mkdir -p "$HOME/.local/share/applications"
        cp "$HOME/.local/kitty.app/share/applications/kitty.desktop" "$HOME/.local/share/applications/" 2>/dev/null || true
        sed -i "s|Icon=kitty|Icon=$HOME/.local/kitty.app/share/icons/hicolor/256x256/apps/kitty.png|g" \
            "$HOME/.local/share/applications/kitty.desktop" 2>/dev/null || true
        ok "Kitty instalado"
    else
        ok "Kitty ya instalado"
    fi

    # Config
    local KITTY_SRC="$SCRIPT_DIR/configs/kitty/kitty.conf"
    if [ -f "$KITTY_SRC" ]; then
        mkdir -p "$HOME/.config/kitty/sessions"
        cp "$KITTY_SRC" "$HOME/.config/kitty/kitty.conf"

        # Dashboard launcher
        local DASH_SRC="$SCRIPT_DIR/configs/kitty/sessions/launch.sh"
        if [ -f "$DASH_SRC" ]; then
            cp "$DASH_SRC" "$HOME/.config/kitty/sessions/launch.sh"
            chmod +x "$HOME/.config/kitty/sessions/launch.sh"
        fi
        ok "Kitty configurado (Dracula theme, splits, dashboards)"
    fi
}

# ============================================================
# MÓDULO 12: Zsh + Oh My Zsh + Powerlevel10k
# ============================================================
install_zsh() {
    info "Configurando Zsh..."

    # Instalar zsh si no existe
    if ! command -v zsh &>/dev/null; then
        sudo apt install -y -qq zsh
    fi

    # Oh My Zsh
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        info "  Instalando Oh My Zsh..."
        RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" 2>/dev/null
        ok "Oh My Zsh instalado"
    else
        ok "Oh My Zsh ya instalado"
    fi

    # Powerlevel10k
    local P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    if [ ! -d "$P10K_DIR" ]; then
        info "  Instalando Powerlevel10k..."
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR" 2>/dev/null
        ok "Powerlevel10k instalado"
    fi

    # Plugins
    local CUSTOM_PLUGINS="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"
    if [ ! -d "$CUSTOM_PLUGINS/zsh-autosuggestions" ]; then
        info "  Instalando zsh-autosuggestions..."
        git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$CUSTOM_PLUGINS/zsh-autosuggestions" 2>/dev/null
    fi
    if [ ! -d "$CUSTOM_PLUGINS/zsh-syntax-highlighting" ]; then
        info "  Instalando zsh-syntax-highlighting..."
        git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting "$CUSTOM_PLUGINS/zsh-syntax-highlighting" 2>/dev/null
    fi

    # Zoxide (cd replacement)
    if ! command -v zoxide &>/dev/null; then
        info "  Instalando zoxide..."
        sudo apt install -y -qq zoxide 2>/dev/null || {
            curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash 2>/dev/null
        }
    fi

    # Configurar .zshrc solo si Oh My Zsh lo acaba de crear (default) o no existe
    if [ ! -f "$HOME/.zshrc" ] || grep -q "robbyrussell" "$HOME/.zshrc" 2>/dev/null; then
        info "  Generando .zshrc base con Powerlevel10k..."
        cat > "$HOME/.zshrc" << 'ZSHRC'
# --- Powerlevel10k instant prompt ---
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# --- Oh My Zsh ---
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
source $ZSH/oh-my-zsh.sh

# --- Powerlevel10k ---
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# --- PATH ---
export PATH=$HOME/.local/bin:$PATH
typeset -U PATH

# --- Aliases ---
# Añade tus aliases aquí

# --- Zoxide (mejor cd) ---
eval "$(zoxide init zsh)" 2>/dev/null
alias cd="z"
ZSHRC
        ok ".zshrc generado (edítalo para añadir tus aliases y PATH)"
    else
        ok ".zshrc existente respetado (no se sobreescribe)"
    fi

    # Cambiar shell por defecto a zsh
    if [ "$(basename "$SHELL")" != "zsh" ]; then
        info "  Cambiando shell por defecto a zsh..."
        chsh -s "$(which zsh)" 2>/dev/null || {
            warn "No se pudo cambiar shell automáticamente. Ejecuta: chsh -s \$(which zsh)"
        }
    fi

    ok "Zsh listo (Oh My Zsh + Powerlevel10k + plugins + zoxide)"
    info "  Ejecuta 'p10k configure' para personalizar el prompt"
}

# ============================================================
# MÓDULO 13: Conky (desktop monitor)
# ============================================================
install_conky() {
    info "Instalando Conky (Mimosa Dark theme)..."

    # Instalar conky
    if ! command -v conky &>/dev/null; then
        sudo apt install -y -qq conky-all
    fi

    # Instalar playerctl (para widget de música)
    if ! command -v playerctl &>/dev/null; then
        sudo apt install -y -qq playerctl
    fi

    # Copiar tema Mimosa
    local CONKY_SRC="$SCRIPT_DIR/configs/conky/Mimosa"
    if [ -d "$CONKY_SRC" ]; then
        mkdir -p "$HOME/.config/conky/Mimosa"
        cp -r "$CONKY_SRC/"* "$HOME/.config/conky/Mimosa/"
        chmod +x "$HOME/.config/conky/Mimosa/start.sh" 2>/dev/null || true
        chmod +x "$HOME/.config/conky/Mimosa/scripts/"* 2>/dev/null || true

        # Instalar fuentes del tema
        local FONT_DIR="$HOME/.local/share/fonts"
        mkdir -p "$FONT_DIR"
        for f in "$CONKY_SRC/fonts/"*.ttf; do
            [ -f "$f" ] && cp "$f" "$FONT_DIR/"
        done
        if [ -f "$CONKY_SRC/fonts/Abel.zip" ]; then
            unzip -qo "$CONKY_SRC/fonts/Abel.zip" -d "$FONT_DIR/" 2>/dev/null || true
        fi
        fc-cache -f "$FONT_DIR" 2>/dev/null

        ok "Conky Mimosa Dark instalado"
    fi

    # Autostart conky
    local AUTOSTART_DIR="$HOME/.config/autostart"
    mkdir -p "$AUTOSTART_DIR"
    cat > "$AUTOSTART_DIR/conky-mimosa.desktop" << 'DESKTOP'
[Desktop Entry]
Type=Application
Name=Conky Mimosa
Exec=bash -c "sleep 5 && conky -c ~/.config/conky/Mimosa/Mimosa.conf"
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Comment=Conky desktop monitor (Mimosa Dark theme)
DESKTOP

    ok "Conky autostart configurado"
}

# ============================================================
# MÓDULO 14: Firewall (ufw)
# ============================================================
install_firewall() {
    info "Configurando firewall (ufw)..."

    if ! command -v ufw &>/dev/null; then
        sudo apt install -y -qq ufw
    fi

    # Reglas base: denegar entrante, permitir saliente
    sudo ufw default deny incoming 2>/dev/null
    sudo ufw default allow outgoing 2>/dev/null

    # SSH (por si accedes remotamente)
    sudo ufw allow ssh 2>/dev/null

    # Tailscale (si lo usas)
    if command -v tailscale &>/dev/null; then
        sudo ufw allow in on tailscale0 2>/dev/null
    fi

    # KDE Connect / GSConnect (descubrimiento LAN)
    sudo ufw allow 1714:1764/tcp 2>/dev/null
    sudo ufw allow 1714:1764/udp 2>/dev/null

    # Habilitar
    echo "y" | sudo ufw enable 2>/dev/null

    ok "Firewall configurado (deny incoming, allow SSH + Tailscale + GSConnect)"
}

# ============================================================
# MÓDULO 15: Optimizaciones SSD/fstab
# ============================================================
optimize_fstab() {
    info "Optimizando fstab para SSD..."

    local FSTAB="/etc/fstab"

    # Solo modificar si ext4 y no tiene noatime
    if grep -q "ext4" "$FSTAB" && ! grep -q "noatime" "$FSTAB"; then
        sudo cp "$FSTAB" "${FSTAB}.bak.$(date +%s)"

        # Añadir noatime y commit=60 a particiones ext4
        sudo sed -i '/ext4/ s/errors=remount-ro/noatime,commit=60,errors=remount-ro/' "$FSTAB"

        ok "fstab optimizado (noatime + commit=60)"
        warn "Los cambios se aplican en el próximo reinicio"
    else
        ok "fstab ya optimizado o no usa ext4"
    fi

    # Verificar fstrim.timer
    if ! systemctl is-enabled fstrim.timer &>/dev/null; then
        sudo systemctl enable --now fstrim.timer
        ok "fstrim.timer habilitado (TRIM semanal)"
    else
        ok "fstrim.timer ya habilitado"
    fi
}

# ============================================================
# MÓDULO 16: Sysctl para desarrollo
# ============================================================
optimize_sysctl_dev() {
    info "Aplicando sysctl para desarrollo..."

    local SYSCTL_FILE="/etc/sysctl.d/99-dev-optimizations.conf"

    sudo tee "$SYSCTL_FILE" > /dev/null << 'SYSCTL'
# MRTX post-install: sysctl para desarrollo

# inotify watches (IDEs como IntelliJ/VS Code necesitan muchos)
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 1024

# Network: reutilizar sockets TIME_WAIT (dev servers, docker)
net.ipv4.tcp_tw_reuse = 1

# Network: buffer sizes para mejor throughput
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216

# File handles (Docker, muchos procesos dev)
fs.file-max = 2097152

# Permitir unprivileged user namespaces (Docker rootless, Flatpak)
kernel.unprivileged_userns_clone = 1
SYSCTL

    sudo sysctl --system -q 2>/dev/null
    ok "Sysctl dev optimizations aplicadas"
}

# ============================================================
# DESINSTALACIÓN
# ============================================================
remove_all() {
    echo -e "${BOLD}=== Desinstalación ===${NC}"
    echo ""
    warn "Esto eliminará las personalizaciones aplicadas por este script."
    ask "Continuar? [y/N]"
    read -r ans
    [[ "${ans,,}" == "y" ]] || exit 0

    info "Restaurando GNOME a valores por defecto..."
    # Reset tema
    gsettings reset org.gnome.desktop.interface gtk-theme 2>/dev/null || true
    gsettings reset org.gnome.desktop.interface icon-theme 2>/dev/null || true
    gsettings reset org.gnome.desktop.interface cursor-theme 2>/dev/null || true
    gsettings reset org.gnome.desktop.interface font-name 2>/dev/null || true
    gsettings reset org.gnome.desktop.interface color-scheme 2>/dev/null || true
    gsettings reset org.gnome.shell.extensions.user-theme name 2>/dev/null || true

    info "Deshabilitando extensiones..."
    gsettings reset org.gnome.shell enabled-extensions 2>/dev/null || true

    info "Eliminando TLP custom config..."
    sudo rm -f /etc/tlp.d/01-battery-optimized.conf 2>/dev/null || true

    # Battery Optimizer
    if [ -f /usr/local/bin/battery-mode.sh ]; then
        info "Desinstalando Battery Optimizer..."
        local BOPT_SCRIPT="$SCRIPT_DIR/../battery-optimizer/install.sh"
        if [ -f "$BOPT_SCRIPT" ]; then
            sudo bash "$BOPT_SCRIPT" --remove 2>/dev/null || {
                # Limpieza manual si el script falla
                sudo rm -f /usr/local/bin/battery-mode.sh
                sudo rm -f /usr/local/bin/battery-optimizer-recover.sh
                sudo rm -f /etc/udev/rules.d/85-battery-optimizer.rules
                sudo rm -f /etc/udev/rules.d/80-nvidia-pm.rules
                sudo systemctl disable battery-optimizer.service 2>/dev/null || true
                sudo rm -f /etc/systemd/system/battery-optimizer.service
                sudo systemctl daemon-reload 2>/dev/null || true
                # Reactivar todos los cores
                for i in $(seq 1 15); do
                    echo 1 | sudo tee /sys/devices/system/cpu/cpu$i/online >/dev/null 2>&1 || true
                done
            }
        fi
    fi

    info "Eliminando tema GRUB..."
    if grep -q 'darkmatter' /etc/default/grub 2>/dev/null; then
        sudo sed -i '/GRUB_THEME.*darkmatter/d' /etc/default/grub
        sudo update-grub 2>/dev/null || true
    fi

    info "Eliminando conky autostart..."
    rm -f "$HOME/.config/autostart/conky-mimosa.desktop" 2>/dev/null || true

    info "Eliminando firewall rules..."
    if command -v ufw &>/dev/null; then
        echo "y" | sudo ufw disable 2>/dev/null || true
    fi

    info "Eliminando sysctl dev..."
    sudo rm -f /etc/sysctl.d/99-dev-optimizations.conf 2>/dev/null || true
    sudo sysctl --system -q 2>/dev/null || true

    info "Restaurando fstab..."
    local FSTAB_BAK=$(ls -t /etc/fstab.bak.* 2>/dev/null | head -1)
    if [ -n "$FSTAB_BAK" ]; then
        sudo cp "$FSTAB_BAK" /etc/fstab
        ok "fstab restaurado desde backup"
    fi

    rm -f "$STAMP_FILE" 2>/dev/null || true
    ok "Personalizaciones eliminadas. Reinicia la sesión para ver los cambios."
}

# ============================================================
# STATUS
# ============================================================
show_status() {
    echo -e "${BOLD}=== Estado de personalización ===${NC}"
    echo ""

    # Tema
    local gtk=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null)
    local icons=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null)
    local cursor=$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null)
    echo "  GTK Theme:  $gtk"
    echo "  Iconos:     $icons"
    echo "  Cursor:     $cursor"

    # Fuentes
    local font=$(gsettings get org.gnome.desktop.interface font-name 2>/dev/null)
    echo "  Fuente:     $font"

    # Extensiones
    local exts=$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null | tr ',' '\n' | wc -l)
    echo "  Extensiones habilitadas: ~$exts"

    # TLP
    if [ -f /etc/tlp.d/01-battery-optimized.conf ]; then
        ok "TLP custom config: instalada"
    else
        warn "TLP custom config: no instalada"
    fi

    # GRUB theme
    if [ -d /boot/grub/themes/darkmatter ]; then
        ok "GRUB darkmatter: instalado"
    else
        warn "GRUB darkmatter: no instalado"
    fi

    # Fuentes Nerd
    if [ -d "$HOME/.local/share/fonts/JetBrainsMono" ]; then
        ok "JetBrains Mono Nerd Font: instalada"
    else
        warn "JetBrains Mono Nerd Font: no instalada"
    fi

    # Zram
    if systemctl is-active zramswap &>/dev/null; then
        ok "Zram: activo"
    else
        warn "Zram: inactivo"
    fi

    # Battery Optimizer
    if [ -f /usr/local/bin/battery-mode.sh ]; then
        ok "Battery Optimizer: instalado"
        if [ -d /sys/class/power_supply/BAT0 ] || [ -d /sys/class/power_supply/BAT1 ]; then
            for pn in /sys/class/power_supply/BAT*/power_now; do
                [ -f "$pn" ] && echo "    Consumo actual: $(awk '{printf "%.1f W", $1/1000000}' "$pn")"
            done
        fi
        echo "    Cores online: $(cat /sys/devices/system/cpu/online 2>/dev/null)"
        local mods=$(lsmod | grep nvidia | awk '{print $1}' | tr '\n' ' ')
        echo "    NVIDIA módulos: ${mods:-ninguno (GPU apagada)}"
    else
        warn "Battery Optimizer: no instalado"
    fi

    # Kitty
    if command -v kitty &>/dev/null; then
        ok "Kitty: $(kitty --version 2>/dev/null | head -1)"
    else
        warn "Kitty: no instalado"
    fi

    # Zsh
    if [ -d "$HOME/.oh-my-zsh" ]; then
        ok "Zsh + Oh My Zsh: instalado"
        [ -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" ] && \
            echo "    Powerlevel10k: instalado" || echo "    Powerlevel10k: no"
    else
        warn "Oh My Zsh: no instalado"
    fi

    # Conky
    if [ -f "$HOME/.config/conky/Mimosa/Mimosa.conf" ]; then
        ok "Conky Mimosa: instalado"
    else
        warn "Conky Mimosa: no instalado"
    fi

    # Firewall
    if command -v ufw &>/dev/null; then
        local ufw_status=$(sudo ufw status 2>/dev/null | head -1)
        ok "Firewall (ufw): $ufw_status"
    else
        warn "Firewall (ufw): no instalado"
    fi

    # fstab
    if grep -q "noatime" /etc/fstab 2>/dev/null; then
        ok "fstab: optimizado (noatime)"
    else
        warn "fstab: sin optimizar"
    fi

    # Sysctl dev
    if [ -f /etc/sysctl.d/99-dev-optimizations.conf ]; then
        ok "Sysctl dev: aplicado"
    else
        warn "Sysctl dev: no aplicado"
    fi

    echo ""
}

# ============================================================
# MENÚ INTERACTIVO
# ============================================================
interactive_menu() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║       MRTX Debian Post-Install v${VERSION}       ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
    echo ""

    check_debian
    check_gnome
    check_internet
    echo ""

    local DO_PACKAGES="n" DO_TLP="n" DO_FONTS="n" DO_THEMES="n"
    local DO_WALLPAPER="n" DO_EXTENSIONS="n" DO_GNOME="n" DO_GRUB="n" DO_ZRAM="n"
    local DO_BATTERY="n" DO_KITTY="n" DO_ZSH="n" DO_CONKY="n"
    local DO_FIREWALL="n" DO_FSTAB="n" DO_SYSCTL="n"

    echo -e "${BOLD}Selecciona qué instalar:${NC}"
    echo ""

    ask "[1] Paquetes base (tlp, papirus, gnome-tweaks, codecs)? [Y/n]"
    read -r ans; [[ "${ans,,}" != "n" ]] && DO_PACKAGES="y"

    ask "[2] Configuración TLP optimizada para batería? [Y/n]"
    read -r ans; [[ "${ans,,}" != "n" ]] && DO_TLP="y"

    ask "[3] JetBrains Mono Nerd Font? [Y/n]"
    read -r ans; [[ "${ans,,}" != "n" ]] && DO_FONTS="y"

    ask "[4] Temas (WhiteSur-Dark, Papirus, Sweet-cursors)? [Y/n]"
    read -r ans; [[ "${ans,,}" != "n" ]] && DO_THEMES="y"

    ask "[5] Wallpaper? [Y/n]"
    read -r ans; [[ "${ans,,}" != "n" ]] && DO_WALLPAPER="y"

    ask "[6] Extensiones GNOME (~22 extensiones)? [Y/n]"
    read -r ans; [[ "${ans,,}" != "n" ]] && DO_EXTENSIONS="y"

    ask "[7] Configuración GNOME completa (dconf)? [Y/n]"
    read -r ans; [[ "${ans,,}" != "n" ]] && DO_GNOME="y"

    ask "[8] Tema GRUB (darkmatter)? [Y/n]"
    read -r ans; [[ "${ans,,}" != "n" ]] && DO_GRUB="y"

    ask "[9] Zram (compresión RAM)? [Y/n]"
    read -r ans; [[ "${ans,,}" != "n" ]] && DO_ZRAM="y"

    # Solo mostrar si hay batería (es laptop)
    if [ -d /sys/class/power_supply/BAT0 ] || [ -d /sys/class/power_supply/BAT1 ]; then
        echo ""
        ask "[10] Battery Optimizer - gestión NVIDIA/CPU en batería (ahorra 8-15W)? [Y/n]"
        read -r ans; [[ "${ans,,}" != "n" ]] && DO_BATTERY="y"
    fi

    echo ""
    echo -e "${BOLD}--- Terminal y Shell ---${NC}"
    echo ""

    ask "[11] Kitty terminal (Dracula theme, splits, dashboards)? [Y/n]"
    read -r ans; [[ "${ans,,}" != "n" ]] && DO_KITTY="y"

    ask "[12] Zsh + Oh My Zsh + Powerlevel10k + plugins? [Y/n]"
    read -r ans; [[ "${ans,,}" != "n" ]] && DO_ZSH="y"

    echo ""
    echo -e "${BOLD}--- Extras ---${NC}"
    echo ""

    ask "[13] Conky desktop monitor (Mimosa Dark theme)? [Y/n]"
    read -r ans; [[ "${ans,,}" != "n" ]] && DO_CONKY="y"

    ask "[14] Firewall (ufw - deny incoming, allow SSH/Tailscale)? [Y/n]"
    read -r ans; [[ "${ans,,}" != "n" ]] && DO_FIREWALL="y"

    ask "[15] Optimización SSD/fstab (noatime, fstrim)? [Y/n]"
    read -r ans; [[ "${ans,,}" != "n" ]] && DO_FSTAB="y"

    ask "[16] Sysctl para desarrollo (inotify, file handles, network)? [Y/n]"
    read -r ans; [[ "${ans,,}" != "n" ]] && DO_SYSCTL="y"

    echo ""
    echo -e "${BOLD}=== Instalando ===${NC}"
    echo ""

    run_selected "$DO_PACKAGES" "$DO_TLP" "$DO_FONTS" "$DO_THEMES" \
                 "$DO_WALLPAPER" "$DO_EXTENSIONS" "$DO_GNOME" "$DO_GRUB" "$DO_ZRAM" \
                 "$DO_BATTERY" "$DO_KITTY" "$DO_ZSH" "$DO_CONKY" \
                 "$DO_FIREWALL" "$DO_FSTAB" "$DO_SYSCTL"
}

run_selected() {
    local DO_PACKAGES="$1" DO_TLP="$2" DO_FONTS="$3" DO_THEMES="$4"
    local DO_WALLPAPER="$5" DO_EXTENSIONS="$6" DO_GNOME="$7" DO_GRUB="$8" DO_ZRAM="$9"
    local DO_BATTERY="${10:-n}" DO_KITTY="${11:-n}" DO_ZSH="${12:-n}" DO_CONKY="${13:-n}"
    local DO_FIREWALL="${14:-n}" DO_FSTAB="${15:-n}" DO_SYSCTL="${16:-n}"

    [[ "$DO_PACKAGES"   == "y" ]] && install_packages
    [[ "$DO_TLP"        == "y" ]] && install_tlp_config
    [[ "$DO_FONTS"      == "y" ]] && install_fonts
    [[ "$DO_THEMES"     == "y" ]] && install_themes
    [[ "$DO_WALLPAPER"  == "y" ]] && install_wallpaper
    [[ "$DO_EXTENSIONS" == "y" ]] && install_gnome_extensions
    [[ "$DO_GNOME"      == "y" ]] && apply_gnome_settings
    [[ "$DO_GRUB"       == "y" ]] && install_grub_theme
    [[ "$DO_ZRAM"       == "y" ]] && configure_zram
    [[ "$DO_BATTERY"    == "y" ]] && install_battery_optimizer
    [[ "$DO_KITTY"      == "y" ]] && install_kitty
    [[ "$DO_ZSH"        == "y" ]] && install_zsh
    [[ "$DO_CONKY"      == "y" ]] && install_conky
    [[ "$DO_FIREWALL"   == "y" ]] && install_firewall
    [[ "$DO_FSTAB"      == "y" ]] && optimize_fstab
    [[ "$DO_SYSCTL"     == "y" ]] && optimize_sysctl_dev

    # Marcar como instalado
    mkdir -p "$(dirname "$STAMP_FILE")"
    echo "version=$VERSION" > "$STAMP_FILE"
    echo "date=$(date -Iseconds)" >> "$STAMP_FILE"

    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              Setup completado!               ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    warn "Reinicia la sesión GNOME (Alt+F2 -> r -> Enter, o logout) para aplicar todos los cambios."
    echo ""
}

# ============================================================
# MAIN
# ============================================================
main() {
    case "${1:-}" in
        --all)
            check_debian
            check_gnome
            check_internet
            echo ""
            echo -e "${BOLD}Instalando todo...${NC}"
            echo ""
            run_selected "y" "y" "y" "y" "y" "y" "y" "y" "y" "y" "y" "y" "y" "y" "y" "y"
            ;;
        --remove)
            remove_all
            ;;
        --status)
            show_status
            ;;
        --help|-h)
            echo "Uso: $0 [--all|--remove|--status|--help]"
            echo ""
            echo "  (sin args)  Instalación interactiva"
            echo "  --all       Instalar todo sin preguntar"
            echo "  --remove    Desinstalar personalizaciones"
            echo "  --status    Ver qué está instalado"
            ;;
        "")
            interactive_menu
            ;;
        *)
            die "Opción desconocida: $1. Usa --help"
            ;;
    esac
}

main "$@"
