#!/bin/bash
#
# Debian Battery Optimizer
# Optimiza laptops con Intel + NVIDIA en Debian para máxima duración de batería.
#
# Probado en: Debian Trixie (13) con GNOME/Wayland
# Hardware soportado: Intel 12th-14th gen + NVIDIA dGPU (RTX 3000/4000)
#
# Uso:
#   sudo ./install.sh          # Instalación interactiva
#   sudo ./install.sh --remove # Desinstalar todo
#   sudo ./install.sh --status # Ver estado actual
#
# https://github.com/mrtx/debian-battery-optimizer

set -euo pipefail

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="/var/lib/debian-battery-optimizer/backup"
STAMP_FILE="/var/lib/debian-battery-optimizer/installed"

# --- Colores ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Helpers ---
info()  { echo -e "${BLUE}[*]${NC} $1"; }
ok()    { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[x]${NC} $1"; }
ask()   { echo -en "${CYAN}[?]${NC} $1 "; }

die() { err "$1"; exit 1; }

need_root() {
    [ "$(id -u)" -eq 0 ] || die "Este script necesita root. Ejecuta: sudo $0"
}

# --- Detección de hardware ---
detect_hardware() {
    info "Detectando hardware..."
    echo ""

    # CPU
    CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs)
    TOTAL_CORES=$(nproc --all)
    TOTAL_THREADS=$(grep -c ^processor /proc/cpuinfo)

    # Detectar P-cores vs E-cores (Intel 12th+ hybrid)
    # Heurística: los hybrid tienen más threads que 2x cores lógicos esperados
    P_CORES=0
    E_CORES=0
    if [ -f /sys/devices/cpu_core/cpus ]; then
        P_CORES=$(cat /sys/devices/cpu_core/cpus 2>/dev/null | tr ',' '\n' | wc -l)
    fi
    if [ -f /sys/devices/cpu_atom/cpus ]; then
        E_CORES=$(cat /sys/devices/cpu_atom/cpus 2>/dev/null | tr ',' '\n' | wc -l)
    fi

    echo -e "  CPU: ${BOLD}$CPU_MODEL${NC}"
    echo "  Threads totales: $TOTAL_THREADS"
    if [ "$P_CORES" -gt 0 ] || [ "$E_CORES" -gt 0 ]; then
        echo "  P-cores: $P_CORES, E-cores: $E_CORES (híbrido)"
    fi

    # GPU NVIDIA
    NVIDIA_GPU=""
    NVIDIA_PCI=""
    if lspci | grep -qi "NVIDIA"; then
        NVIDIA_PCI=$(lspci | grep -i "NVIDIA" | grep -iE "VGA|3D" | head -1 | cut -d' ' -f1)
        NVIDIA_GPU=$(lspci | grep -i "NVIDIA" | grep -iE "VGA|3D" | head -1 | sed 's/.*: //')
        echo -e "  GPU: ${BOLD}$NVIDIA_GPU${NC}"
        echo "  PCI: $NVIDIA_PCI"

        # Verificar driver instalado
        if dpkg -l | grep -q "nvidia-driver\|nvidia-current"; then
            NVIDIA_DRIVER=$(dpkg -l | grep -E "nvidia-driver|nvidia-kernel-dkms" | head -1 | awk '{print $3}')
            echo "  Driver: $NVIDIA_DRIVER"
        else
            warn "Driver NVIDIA propietario NO detectado"
            warn "Este script necesita el driver propietario de NVIDIA instalado"
            NVIDIA_GPU=""
        fi
    else
        warn "No se detectó GPU NVIDIA dedicada"
    fi

    # iGPU Intel
    INTEL_GPU=""
    if lspci | grep -qi "Intel.*Graphics"; then
        INTEL_GPU=$(lspci | grep -i "Intel.*Graphics" | head -1 | sed 's/.*: //')
        echo "  iGPU: $INTEL_GPU"
    fi

    # Batería
    BAT_PATH=""
    for bat in /sys/class/power_supply/BAT*; do
        if [ -d "$bat" ]; then
            BAT_PATH="$bat"
            break
        fi
    done

    if [ -n "$BAT_PATH" ]; then
        BAT_NAME=$(basename "$BAT_PATH")
        if [ -f "$BAT_PATH/energy_full_design" ]; then
            BAT_DESIGN=$(awk '{printf "%.1f", $1/1000000}' "$BAT_PATH/energy_full_design")
            BAT_FULL=$(awk '{printf "%.1f", $1/1000000}' "$BAT_PATH/energy_full")
            BAT_HEALTH=$(awk "BEGIN {printf \"%.0f\", ($BAT_FULL/$BAT_DESIGN)*100}")
            echo "  Batería: ${BAT_DESIGN}Wh diseño, ${BAT_FULL}Wh actual (${BAT_HEALTH}% salud)"
        fi
    else
        warn "No se detectó batería"
    fi

    # AC adapter
    AC_PATH=""
    for ac in /sys/class/power_supply/AC* /sys/class/power_supply/ACAD*; do
        if [ -d "$ac" ]; then
            AC_PATH="$ac"
            AC_NAME=$(basename "$ac")
            break
        fi
    done
    if [ -z "$AC_PATH" ]; then
        # Buscar cualquier supply tipo Mains
        for ps in /sys/class/power_supply/*; do
            if [ -f "$ps/type" ] && [ "$(cat "$ps/type")" = "Mains" ]; then
                AC_PATH="$ps"
                AC_NAME=$(basename "$ps")
                break
            fi
        done
    fi
    [ -n "$AC_PATH" ] && echo "  AC adapter: $AC_NAME" || warn "No se detectó adaptador AC"

    # Desktop Environment
    DE="unknown"
    if [ -n "${XDG_CURRENT_DESKTOP:-}" ]; then
        DE="$XDG_CURRENT_DESKTOP"
    elif pgrep -x gnome-shell >/dev/null 2>&1; then
        DE="GNOME"
    elif pgrep -x plasmashell >/dev/null 2>&1; then
        DE="KDE"
    fi
    echo "  Desktop: $DE"

    echo ""
}

# --- Detectar cuántos cores desactivar ---
calculate_cores_to_disable() {
    # Estrategia: desactivar la mitad de los threads
    # En CPUs híbridas, idealmente desactivar E-cores primero
    CORES_TO_KEEP=$((TOTAL_THREADS / 2))
    [ "$CORES_TO_KEEP" -lt 2 ] && CORES_TO_KEEP=2
    FIRST_CORE_OFF=$CORES_TO_KEEP
    LAST_CORE_OFF=$((TOTAL_THREADS - 1))
}

# --- Preguntas interactivas ---
configure() {
    echo -e "${BOLD}=== Configuración ===${NC}"
    echo ""

    # NVIDIA
    INSTALL_NVIDIA_OPT="n"
    if [ -n "$NVIDIA_GPU" ] && [ -n "$INTEL_GPU" ]; then
        ask "Bloquear NVIDIA en batería y usar solo iGPU Intel? (Ahorra 8-15W) [Y/n]"
        read -r ans
        INSTALL_NVIDIA_OPT="${ans:-y}"
        INSTALL_NVIDIA_OPT="${INSTALL_NVIDIA_OPT,,}"
        [ "$INSTALL_NVIDIA_OPT" != "n" ] && INSTALL_NVIDIA_OPT="y"
    fi

    # CPU cores
    INSTALL_CORE_OPT="n"
    if [ "$TOTAL_THREADS" -gt 4 ]; then
        calculate_cores_to_disable
        ask "Desactivar cores $FIRST_CORE_OFF-$LAST_CORE_OFF en batería? (Mantiene $CORES_TO_KEEP threads) [Y/n]"
        read -r ans
        INSTALL_CORE_OPT="${ans:-y}"
        INSTALL_CORE_OPT="${INSTALL_CORE_OPT,,}"
        [ "$INSTALL_CORE_OPT" != "n" ] && INSTALL_CORE_OPT="y"
    fi

    # TLP
    INSTALL_TLP="n"
    ask "Instalar perfil TLP optimizado para batería? [Y/n]"
    read -r ans
    INSTALL_TLP="${ans:-y}"
    INSTALL_TLP="${INSTALL_TLP,,}"
    [ "$INSTALL_TLP" != "n" ] && INSTALL_TLP="y"

    # Memory
    INSTALL_MEMORY="n"
    if grep -q zram /proc/swaps 2>/dev/null; then
        ask "Optimizar parámetros de memoria para zram? [Y/n]"
        read -r ans
        INSTALL_MEMORY="${ans:-y}"
        INSTALL_MEMORY="${INSTALL_MEMORY,,}"
        [ "$INSTALL_MEMORY" != "n" ] && INSTALL_MEMORY="y"
    fi

    # GNOME bloat
    INSTALL_GNOME_OPT="n"
    if echo "$DE" | grep -qi gnome; then
        ask "Desactivar gnome-software/packagekit en batería? [Y/n]"
        read -r ans
        INSTALL_GNOME_OPT="${ans:-y}"
        INSTALL_GNOME_OPT="${INSTALL_GNOME_OPT,,}"
        [ "$INSTALL_GNOME_OPT" != "n" ] && INSTALL_GNOME_OPT="y"
    fi

    # iGPU compositor
    INSTALL_IGPU_COMPOSITOR="n"
    if echo "$DE" | grep -qi gnome && [ -n "$INTEL_GPU" ] && [ -n "$NVIDIA_GPU" ]; then
        ask "Forzar Mutter a usar solo iGPU Intel? (Evita que GNOME active NVIDIA) [Y/n]"
        read -r ans
        INSTALL_IGPU_COMPOSITOR="${ans:-y}"
        INSTALL_IGPU_COMPOSITOR="${INSTALL_IGPU_COMPOSITOR,,}"
        [ "$INSTALL_IGPU_COMPOSITOR" != "n" ] && INSTALL_IGPU_COMPOSITOR="y"
    fi

    echo ""
}

# --- Backup ---
backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        local rel="${file#/}"
        mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
        cp "$file" "$BACKUP_DIR/$rel"
    fi
}

# --- Instalación ---
install_all() {
    echo -e "${BOLD}=== Instalando ===${NC}"
    echo ""

    mkdir -p "$BACKUP_DIR"
    mkdir -p /var/lib/debian-battery-optimizer

    # --- Dependencias ---
    if [ "$INSTALL_TLP" = "y" ]; then
        if ! dpkg -l | grep -q "^ii.*tlp "; then
            info "Instalando TLP..."
            apt-get update -qq && apt-get install -y -qq tlp tlp-rdw
            systemctl enable tlp
            ok "TLP instalado"
        fi
    fi

    # --- NVIDIA optimization ---
    if [ "$INSTALL_NVIDIA_OPT" = "y" ]; then
        info "Configurando bloqueo NVIDIA en batería..."

        # Modprobe blacklist
        backup_file /etc/modprobe.d/nvidia-battery-blacklist.conf
        cat > /etc/modprobe.d/nvidia-battery-blacklist.conf << 'MODPROBE'
# debian-battery-optimizer: bloquea carga automática de NVIDIA
# Se carga manualmente con modprobe -i al conectar AC
install nvidia /bin/false
install nvidia-modeset /bin/false
install nvidia-drm /bin/false
install nvidia-uvm /bin/false
MODPROBE
        ok "Blacklist NVIDIA instalado"

        # Power management options
        backup_file /etc/modprobe.d/nvidia-powersave.conf

        # Detectar nombre del módulo NVIDIA (nvidia-current vs nvidia)
        NVIDIA_MOD="nvidia"
        if modinfo nvidia-current >/dev/null 2>&1; then
            NVIDIA_MOD="nvidia-current"
        fi

        cat > /etc/modprobe.d/nvidia-powersave.conf << MODPROBE
# debian-battery-optimizer: D3 dynamic power management
options $NVIDIA_MOD NVreg_DynamicPowerManagement=0x02 NVreg_PreserveVideoMemoryAllocations=1
MODPROBE
        ok "NVIDIA powersave configurado"

        # Udev runtime PM
        backup_file /etc/udev/rules.d/80-nvidia-pm.rules
        cat > /etc/udev/rules.d/80-nvidia-pm.rules << 'UDEV'
# debian-battery-optimizer: runtime PM para GPU NVIDIA
ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="auto"
ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="auto"
UDEV
        ok "Udev NVIDIA runtime PM instalado"
    fi

    # --- Battery mode script ---
    info "Generando battery-mode.sh..."

    # Detectar PCI address de la NVIDIA
    NVIDIA_PCI_FULL=""
    if [ -n "$NVIDIA_PCI" ]; then
        NVIDIA_PCI_FULL="0000:$NVIDIA_PCI"
    fi

    cat > /usr/local/bin/battery-mode.sh << SCRIPT
#!/bin/bash
# debian-battery-optimizer: cambia entre modo batería y AC
# Uso: battery-mode.sh [battery|ac|status]
MODE=\${1:-battery}

if [ "\$MODE" = "status" ]; then
    echo "=== Battery Optimizer Status ==="
    echo "Cores online: \$(cat /sys/devices/system/cpu/online)"
SCRIPT

    if [ "$INSTALL_NVIDIA_OPT" = "y" ] && [ -n "$NVIDIA_PCI_FULL" ]; then
        cat >> /usr/local/bin/battery-mode.sh << SCRIPT
    echo "GPU power state: \$(cat /sys/bus/pci/devices/$NVIDIA_PCI_FULL/power_state 2>/dev/null || echo 'N/A')"
    echo "NVIDIA modules: \$(lsmod | grep nvidia | awk '{print \$1}' | tr '\n' ' ')"
SCRIPT
    fi

    if [ -f /sys/class/power_supply/*/power_now ]; then
        cat >> /usr/local/bin/battery-mode.sh << 'SCRIPT'
    for pn in /sys/class/power_supply/BAT*/power_now; do
        [ -f "$pn" ] && echo "Power draw: $(awk '{printf "%.1f W", $1/1000000}' "$pn")"
    done
SCRIPT
    fi

    cat >> /usr/local/bin/battery-mode.sh << 'SCRIPT'
    exit 0
fi

SCRIPT

    # Battery mode
    cat >> /usr/local/bin/battery-mode.sh << 'SCRIPT'
if [ "$MODE" = "battery" ]; then
SCRIPT

    if [ "$INSTALL_NVIDIA_OPT" = "y" ]; then
        cat >> /usr/local/bin/battery-mode.sh << SCRIPT
    # Kill GPU monitors (e.g. GNOME Vitals extension)
    pkill -f nvidia-smi 2>/dev/null || true

    # Stop persistenced
    systemctl stop nvidia-persistenced 2>/dev/null || true

    # Unload NVIDIA modules (order matters)
    modprobe -r nvidia_uvm 2>/dev/null || true
    modprobe -r nvidia_drm 2>/dev/null || true
    modprobe -r nvidia_modeset 2>/dev/null || true
    modprobe -r nvidia 2>/dev/null || true

    # Enable runtime PM for D3
    echo auto > /sys/bus/pci/devices/$NVIDIA_PCI_FULL/power/control 2>/dev/null || true

SCRIPT
    fi

    if [ "$INSTALL_CORE_OPT" = "y" ]; then
        cat >> /usr/local/bin/battery-mode.sh << SCRIPT
    # Disable cores $FIRST_CORE_OFF-$LAST_CORE_OFF
    for i in \$(seq $FIRST_CORE_OFF $LAST_CORE_OFF); do
        echo 0 > /sys/devices/system/cpu/cpu\$i/online 2>/dev/null || true
    done

SCRIPT
    fi

    if [ "$INSTALL_GNOME_OPT" = "y" ]; then
        cat >> /usr/local/bin/battery-mode.sh << 'SCRIPT'
    # Stop background bloat
    systemctl stop packagekit 2>/dev/null || true
    systemctl mask --runtime packagekit 2>/dev/null || true
    pkill -f gnome-software 2>/dev/null || true

SCRIPT
    fi

    # AC mode
    cat >> /usr/local/bin/battery-mode.sh << 'SCRIPT'
elif [ "$MODE" = "ac" ]; then
SCRIPT

    if [ "$INSTALL_CORE_OPT" = "y" ]; then
        cat >> /usr/local/bin/battery-mode.sh << SCRIPT
    # Enable all cores
    for i in \$(seq $FIRST_CORE_OFF $LAST_CORE_OFF); do
        echo 1 > /sys/devices/system/cpu/cpu\$i/online 2>/dev/null || true
    done

SCRIPT
    fi

    if [ "$INSTALL_NVIDIA_OPT" = "y" ]; then
        cat >> /usr/local/bin/battery-mode.sh << SCRIPT
    # Load NVIDIA modules (bypass blacklist with -i)
    modprobe -i $NVIDIA_MOD 2>/dev/null || true
    modprobe -i ${NVIDIA_MOD}-modeset 2>/dev/null || true
    modprobe -i ${NVIDIA_MOD}-drm 2>/dev/null || true
    modprobe -i ${NVIDIA_MOD}-uvm 2>/dev/null || true
    echo on > /sys/bus/pci/devices/$NVIDIA_PCI_FULL/power/control 2>/dev/null || true
    systemctl start nvidia-persistenced 2>/dev/null || true

SCRIPT
    fi

    if [ "$INSTALL_GNOME_OPT" = "y" ]; then
        cat >> /usr/local/bin/battery-mode.sh << 'SCRIPT'
    # Unmask packagekit
    systemctl unmask --runtime packagekit 2>/dev/null || true

SCRIPT
    fi

    echo "fi" >> /usr/local/bin/battery-mode.sh
    chmod +x /usr/local/bin/battery-mode.sh
    ok "battery-mode.sh instalado"

    # --- Udev rule for AC/battery switch ---
    if [ -n "$AC_NAME" ]; then
        info "Configurando cambio automático AC/batería..."
        backup_file /etc/udev/rules.d/85-battery-optimizer.rules
        cat > /etc/udev/rules.d/85-battery-optimizer.rules << UDEV
# debian-battery-optimizer: auto-switch on plug/unplug
SUBSYSTEM=="power_supply", KERNEL=="$AC_NAME", ATTR{online}=="0", RUN+="/usr/local/bin/battery-mode.sh battery"
SUBSYSTEM=="power_supply", KERNEL=="$AC_NAME", ATTR{online}=="1", RUN+="/usr/local/bin/battery-mode.sh ac"
UDEV
        ok "Regla udev AC/batería instalada ($AC_NAME)"
    fi

    # --- Systemd boot service ---
    info "Configurando servicio de boot..."
    backup_file /etc/systemd/system/battery-optimizer.service
    cat > /etc/systemd/system/battery-optimizer.service << SERVICE
[Unit]
Description=Debian Battery Optimizer - Apply power profile at boot
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'if [ "\$(cat /sys/class/power_supply/$AC_NAME/online 2>/dev/null)" = "0" ]; then /usr/local/bin/battery-mode.sh battery; else /usr/local/bin/battery-mode.sh ac; fi'

[Install]
WantedBy=multi-user.target
SERVICE
    systemctl daemon-reload
    systemctl enable battery-optimizer.service
    ok "Servicio battery-optimizer habilitado"

    # --- TLP ---
    if [ "$INSTALL_TLP" = "y" ]; then
        info "Instalando perfil TLP..."
        backup_file /etc/tlp.d/01-battery-optimized.conf
        cat > /etc/tlp.d/01-battery-optimized.conf << 'TLP'
# debian-battery-optimizer: TLP battery profile

# === CPU ===
CPU_ENERGY_PERF_POLICY_ON_AC=balance_performance
CPU_ENERGY_PERF_POLICY_ON_BAT=power

CPU_BOOST_ON_AC=1
CPU_BOOST_ON_BAT=0

CPU_HWP_DYN_BOOST_ON_AC=1
CPU_HWP_DYN_BOOST_ON_BAT=0

CPU_MAX_PERF_ON_AC=100
CPU_MAX_PERF_ON_BAT=50

# === Platform ===
PLATFORM_PROFILE_ON_AC=performance
PLATFORM_PROFILE_ON_BAT=low-power

# === PCIe ASPM ===
PCIE_ASPM_ON_AC=default
PCIE_ASPM_ON_BAT=powersupersave

# === Runtime PM ===
RUNTIME_PM_ON_AC=on
RUNTIME_PM_ON_BAT=auto
RUNTIME_PM_DRIVER_DENYLIST="mei_me nouveau radeon xhci_hcd i2c_hid_acpi i2c_hid"

# === WiFi ===
WIFI_PWR_ON_AC=off
WIFI_PWR_ON_BAT=on

# === Audio ===
SOUND_POWER_SAVE_ON_AC=1
SOUND_POWER_SAVE_ON_BAT=1
SOUND_POWER_SAVE_CONTROLLER=Y

# === Misc ===
NMI_WATCHDOG=0
MEM_SLEEP_ON_BAT=deep
TLP
        ok "Perfil TLP instalado"
    fi

    # --- Memory optimization ---
    if [ "$INSTALL_MEMORY" = "y" ]; then
        info "Optimizando parámetros de memoria..."
        backup_file /etc/sysctl.d/99-battery-memory.conf
        cat > /etc/sysctl.d/99-battery-memory.conf << 'SYSCTL'
# debian-battery-optimizer: memory tuning for zram
vm.swappiness = 100
vm.vfs_cache_pressure = 200
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.watermark_scale_factor = 200
SYSCTL
        sysctl --system -q
        ok "Parámetros de memoria optimizados"
    fi

    # --- GNOME iGPU compositor ---
    if [ "$INSTALL_IGPU_COMPOSITOR" = "y" ]; then
        info "Forzando compositor a iGPU..."
        mkdir -p /etc/environment.d
        backup_file /etc/environment.d/10-prefer-igpu.conf
        cat > /etc/environment.d/10-prefer-igpu.conf << 'ENV'
# debian-battery-optimizer: force GNOME to use Intel iGPU
MUTTER_DEBUG_FORCE_KMS_MODE=simple
ENV
        ok "Compositor forzado a iGPU"
    fi

    # --- GNOME Software D-Bus block ---
    if [ "$INSTALL_GNOME_OPT" = "y" ]; then
        info "Bloqueando respawn de gnome-software..."
        mkdir -p /etc/dbus-1/services
        backup_file /etc/dbus-1/services/org.gnome.Software.service
        cat > /etc/dbus-1/services/org.gnome.Software.service << 'DBUS'
[D-BUS Service]
Name=org.gnome.Software
Exec=/bin/true
DBUS
        ok "gnome-software bloqueado via D-Bus"
    fi

    # --- Recovery script ---
    info "Instalando script de recuperación..."
    cat > /usr/local/bin/battery-optimizer-recover.sh << RECOVER
#!/bin/bash
# debian-battery-optimizer: recovery script
# Ejecutar desde TTY si GNOME no arranca: sudo battery-optimizer-recover.sh

echo "=== Battery Optimizer Recovery ==="
echo ""

echo "[1/4] Activando todos los cores..."
for i in \$(seq 1 $((TOTAL_THREADS - 1))); do
    echo 1 > /sys/devices/system/cpu/cpu\$i/online 2>/dev/null
done
echo "  Cores online: \$(cat /sys/devices/system/cpu/online)"

RECOVER

    if [ "$INSTALL_NVIDIA_OPT" = "y" ]; then
        cat >> /usr/local/bin/battery-optimizer-recover.sh << RECOVER
echo "[2/4] Quitando bloqueo NVIDIA..."
if [ -f /etc/modprobe.d/nvidia-battery-blacklist.conf ]; then
    mv /etc/modprobe.d/nvidia-battery-blacklist.conf /etc/modprobe.d/nvidia-battery-blacklist.conf.disabled
    echo "  Blacklist deshabilitado"
fi

echo "[3/4] Cargando módulos NVIDIA..."
modprobe -i $NVIDIA_MOD 2>/dev/null && echo "  nvidia: OK" || echo "  nvidia: FALLO"
modprobe -i ${NVIDIA_MOD}-modeset 2>/dev/null && echo "  modeset: OK" || echo "  modeset: FALLO"
modprobe -i ${NVIDIA_MOD}-drm 2>/dev/null && echo "  drm: OK" || echo "  drm: FALLO"

RECOVER
    else
        cat >> /usr/local/bin/battery-optimizer-recover.sh << 'RECOVER'
echo "[2/4] Sin NVIDIA configurada, saltando..."
echo "[3/4] Sin NVIDIA configurada, saltando..."

RECOVER
    fi

    cat >> /usr/local/bin/battery-optimizer-recover.sh << 'RECOVER'
echo "[4/4] Regenerando initramfs..."
update-initramfs -u 2>/dev/null && echo "  initramfs: OK" || echo "  initramfs: FALLO"

echo ""
echo "=== Recovery completo ==="
echo "Si GNOME sigue sin funcionar: sudo systemctl restart gdm"
echo "Para reactivar optimización: sudo mv /etc/modprobe.d/nvidia-battery-blacklist.conf.disabled /etc/modprobe.d/nvidia-battery-blacklist.conf && sudo update-initramfs -u"
RECOVER
    chmod +x /usr/local/bin/battery-optimizer-recover.sh
    ok "Script de recuperación instalado"

    # --- Regenerar initramfs ---
    info "Regenerando initramfs (puede tardar un momento)..."
    update-initramfs -u
    ok "Initramfs actualizado"

    # --- Stamp ---
    cat > "$STAMP_FILE" << STAMP
version=$VERSION
date=$(date -Iseconds)
nvidia=$INSTALL_NVIDIA_OPT
cores=$INSTALL_CORE_OPT
cores_keep=${CORES_TO_KEEP:-$TOTAL_THREADS}
tlp=$INSTALL_TLP
memory=$INSTALL_MEMORY
gnome=$INSTALL_GNOME_OPT
igpu=$INSTALL_IGPU_COMPOSITOR
nvidia_mod=${NVIDIA_MOD:-}
nvidia_pci=${NVIDIA_PCI_FULL:-}
ac_name=${AC_NAME:-}
STAMP

    echo ""
    echo -e "${GREEN}${BOLD}=== Instalación completa ===${NC}"
    echo ""
    echo "Cambios aplicados:"
    [ "$INSTALL_NVIDIA_OPT" = "y" ] && echo "  - NVIDIA bloqueada en batería, se activa con AC"
    [ "$INSTALL_CORE_OPT" = "y" ] && echo "  - Cores $FIRST_CORE_OFF-$LAST_CORE_OFF se desactivan en batería"
    [ "$INSTALL_TLP" = "y" ] && echo "  - TLP con perfil optimizado"
    [ "$INSTALL_MEMORY" = "y" ] && echo "  - Memoria optimizada para zram"
    [ "$INSTALL_GNOME_OPT" = "y" ] && echo "  - gnome-software/packagekit desactivados en batería"
    [ "$INSTALL_IGPU_COMPOSITOR" = "y" ] && echo "  - Compositor forzado a Intel iGPU"
    echo ""
    echo "Comandos útiles:"
    echo "  sudo battery-mode.sh status    # Ver estado actual"
    echo "  sudo battery-mode.sh battery   # Forzar modo batería"
    echo "  sudo battery-mode.sh ac        # Forzar modo AC"
    echo "  sudo battery-optimizer-recover.sh  # Recuperación si algo falla"
    echo ""
    warn "Se recomienda reiniciar para aplicar todos los cambios: sudo reboot"
}

# --- Desinstalación ---
remove_all() {
    echo -e "${BOLD}=== Desinstalando Debian Battery Optimizer ===${NC}"
    echo ""

    if [ ! -f "$STAMP_FILE" ]; then
        warn "No se encontró instalación previa"
        exit 0
    fi

    source "$STAMP_FILE"

    # Restaurar cores
    info "Restaurando todos los cores..."
    for i in $(seq 1 $((TOTAL_THREADS - 1))); do
        echo 1 > /sys/devices/system/cpu/cpu$i/online 2>/dev/null || true
    done
    ok "Todos los cores activos"

    # Quitar archivos instalados
    local files=(
        /etc/modprobe.d/nvidia-battery-blacklist.conf
        /etc/modprobe.d/nvidia-powersave.conf
        /etc/udev/rules.d/80-nvidia-pm.rules
        /etc/udev/rules.d/85-battery-optimizer.rules
        /etc/systemd/system/battery-optimizer.service
        /etc/tlp.d/01-battery-optimized.conf
        /etc/sysctl.d/99-battery-memory.conf
        /etc/environment.d/10-prefer-igpu.conf
        /etc/dbus-1/services/org.gnome.Software.service
        /usr/local/bin/battery-mode.sh
        /usr/local/bin/battery-optimizer-recover.sh
    )

    for f in "${files[@]}"; do
        if [ -f "$f" ]; then
            # Restaurar backup si existe
            local rel="${f#/}"
            if [ -f "$BACKUP_DIR/$rel" ]; then
                cp "$BACKUP_DIR/$rel" "$f"
                ok "Restaurado desde backup: $f"
            else
                rm -f "$f"
                ok "Eliminado: $f"
            fi
        fi
    done

    # Deshabilitar servicio
    systemctl disable battery-optimizer.service 2>/dev/null || true
    systemctl daemon-reload

    # Unmask packagekit
    systemctl unmask packagekit 2>/dev/null || true

    # Regenerar initramfs
    info "Regenerando initramfs..."
    update-initramfs -u
    ok "Initramfs restaurado"

    # Limpiar
    rm -rf /var/lib/debian-battery-optimizer

    echo ""
    ok "Desinstalación completa. Reinicia para aplicar: sudo reboot"
}

# --- Status ---
show_status() {
    echo -e "${BOLD}=== Debian Battery Optimizer - Estado ===${NC}"
    echo ""

    if [ ! -f "$STAMP_FILE" ]; then
        warn "No hay instalación detectada"
        exit 0
    fi

    source "$STAMP_FILE"
    echo "Versión instalada: $version"
    echo "Fecha: $date"
    echo ""

    # Cores
    echo -e "${BOLD}CPU:${NC}"
    echo "  Online: $(cat /sys/devices/system/cpu/online)"
    echo "  Configurado para mantener: $cores_keep threads en batería"

    # NVIDIA
    if [ "$nvidia" = "y" ]; then
        echo ""
        echo -e "${BOLD}NVIDIA:${NC}"
        if [ -n "$nvidia_pci" ]; then
            local pstate=$(cat /sys/bus/pci/devices/$nvidia_pci/power_state 2>/dev/null || echo "N/A")
            echo "  Power state: $pstate"
        fi
        local mods=$(lsmod | grep nvidia | awk '{print $1}' | tr '\n' ' ')
        echo "  Módulos cargados: ${mods:-ninguno}"
    fi

    # Power
    echo ""
    echo -e "${BOLD}Energía:${NC}"
    for pn in /sys/class/power_supply/BAT*/power_now; do
        [ -f "$pn" ] && echo "  Consumo: $(awk '{printf "%.1f W", $1/1000000}' "$pn")"
    done
    if [ -n "$ac_name" ] && [ -f "/sys/class/power_supply/$ac_name/online" ]; then
        local ac_on=$(cat "/sys/class/power_supply/$ac_name/online")
        [ "$ac_on" = "1" ] && echo "  Fuente: AC (conectado)" || echo "  Fuente: Batería"
    fi

    # TLP
    if [ "$tlp" = "y" ]; then
        echo ""
        echo -e "${BOLD}TLP:${NC}"
        systemctl is-active tlp >/dev/null 2>&1 && echo "  Estado: activo" || echo "  Estado: inactivo"
    fi

    echo ""
}

# --- Main ---
main() {
    echo ""
    echo -e "${BOLD}  Debian Battery Optimizer v$VERSION${NC}"
    echo -e "  Optimiza la batería de laptops Intel+NVIDIA en Debian"
    echo ""

    case "${1:-}" in
        --remove|-r)
            need_root
            detect_hardware
            remove_all
            ;;
        --status|-s)
            show_status
            ;;
        --help|-h)
            echo "Uso: sudo $0 [opciones]"
            echo ""
            echo "Opciones:"
            echo "  (sin args)    Instalación interactiva"
            echo "  --remove, -r  Desinstalar todo y restaurar backups"
            echo "  --status, -s  Ver estado actual"
            echo "  --help, -h    Mostrar esta ayuda"
            echo ""
            ;;
        *)
            need_root
            detect_hardware
            if [ -z "$NVIDIA_GPU" ] && [ -z "$INTEL_GPU" ]; then
                die "No se detectó configuración Intel+NVIDIA soportada"
            fi
            configure
            echo ""
            ask "Aplicar todos los cambios? [Y/n]"
            read -r confirm
            confirm="${confirm:-y}"
            if [ "${confirm,,}" != "n" ]; then
                install_all
            else
                info "Cancelado."
            fi
            ;;
    esac
}

main "$@"
