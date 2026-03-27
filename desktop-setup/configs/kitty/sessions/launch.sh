#!/bin/bash
# Lanzador de dashboards Kitty (en la instancia actual)
# Uso: dash <nombre>  o  dash (sin args para ver opciones)

case "${1:-}" in
    monitor|mon)
        # btop (izquierda), bmon (derecha-arriba), gping (derecha-abajo)
        btop_id=$(kitten @ launch --type=tab --tab-title Monitor --cwd=home btop)
        sleep 0.5
        kitten @ goto-layout --match title:Monitor splits
        kitten @ focus-window --match id:"$btop_id"
        net_id=$(kitten @ launch --match title:Monitor --location=vsplit --cwd=home bmon)
        sleep 0.3
        kitten @ focus-window --match id:"$net_id"
        kitten @ launch --match title:Monitor --location=hsplit --cwd=home gping 8.8.8.8 1.1.1.1
        kitten @ focus-window --match id:"$btop_id"
        ;;
    dev)
        # zsh (arriba-izq), lazydocker (abajo-izq), lazygit (derecha entera)
        shell_id=$(kitten @ launch --type=tab --tab-title Dev --cwd=current zsh)
        sleep 0.5
        kitten @ goto-layout --match title:Dev splits
        kitten @ focus-window --match id:"$shell_id"
        git_id=$(kitten @ launch --match title:Dev --location=vsplit --cwd=current lazygit)
        sleep 0.3
        kitten @ focus-window --match id:"$shell_id"
        kitten @ launch --match title:Dev --location=hsplit --cwd=current lazydocker
        kitten @ focus-window --match id:"$shell_id"
        ;;
    list|ls)
        echo "Dashboards disponibles:"
        echo "  monitor (mon)  Sistema: btop + bmon + gping"
        echo "  dev            Desarrollo: zsh + lazygit + lazydocker"
        ;;
    *)
        echo "Uso: dash <dashboard>"
        echo ""
        echo "  monitor (mon)  Sistema: btop + bmon + gping"
        echo "  dev            Desarrollo: zsh + lazygit + lazydocker"
        echo ""
        echo "  list           Ver todos los dashboards"
        ;;
esac
