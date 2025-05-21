#!/bin/bash
# DTF-CLI - Delete Temp Files
# Author: YUNG Standard Utility
# Description: Python environment discovery and pruning CLI with interactive and CLI-aware deletion
# Platform: macOS/Linux

ENV_CACHE_FILE="$HOME/.cache/python_env_registry.txt"
DRY_RUN=false
MODE="interactive"

print_header() {
    echo -e "\n🧰 DTF-CLI — PYTHON ENVIRONMENT MANAGER\n-----------------------------"
}

scan_env() {
    local name="$1"
    local path="$2"
    if [[ -d "$path" ]]; then
        ((ENV_COUNT++))
        local sp_path
        sp_path=$(find "$path" -type d -name 'site-packages' 2>/dev/null | head -n 1)
        local sp_size pc_size
        sp_size=$(du -sh "$sp_path" 2>/dev/null | cut -f1)
        pc_size=$(find "$path" -type d -name '__pycache__' ! -path "*site-packages*" -exec du -ch {} + 2>/dev/null | grep total$ | awk '{print $1}')
        [[ -z "$sp_size" ]] && sp_size="0B"
        [[ -z "$pc_size" ]] && pc_size="0B"
        ENV_INFO+=("$ENV_COUNT|$name|$path|$sp_size|$pc_size")
    fi
}

discover_envs() {
    ENV_COUNT=0
    ENV_INFO=()
    scan_env "system" "/usr/bin/python3"
    scan_env "pyenv" "$HOME/.pyenv"
    scan_env "asdf" "$HOME/.asdf/installs/python"
    scan_env "miniconda" "$HOME/miniconda3"
    scan_env "anaconda" "$HOME/anaconda3"
    scan_env "pipx" "$HOME/.local/pipx"
    scan_env "poetry" "$HOME/Library/Caches/pypoetry/virtualenvs"
    find "$HOME" -type d -name "bin" -path "*/venv/bin" 2>/dev/null | while read -r bin_dir; do
        scan_env "venv" "$(dirname "$bin_dir")"
    done
}

write_registry() {
    mkdir -p "$(dirname "$ENV_CACHE_FILE")"
    printf "%s\n" "${ENV_INFO[@]}" > "$ENV_CACHE_FILE"
    echo "📦 Environment registry saved to: $ENV_CACHE_FILE"
}

load_registry() {
    mapfile -t ENV_INFO < "$ENV_CACHE_FILE"
}

list_envs() {
    printf "\n%-4s | %-10s | %-40s | %-10s | %-10s\n" "ID" "Type" "Path" "Site-Pkgs" "Pycache"
    printf '%.0s-' {1..90}; echo
    for entry in "${ENV_INFO[@]}"; do
        IFS="|" read -r id name path sp pc <<< "$entry"
        printf "%-4s | %-10s | %-40s | %-10s | %-10s\n" "$id" "$name" "$path" "$sp" "$pc"
    done
}

delete_env_by_id() {
    local id="$1"
    local mode="$2"
    for entry in "${ENV_INFO[@]}"; do
        IFS="|" read -r eid etype epath esp epc <<< "$entry"
        if [[ "$eid" == "$id" ]]; then
            if [[ "$mode" == "interactive" ]]; then
                echo -e "\n🧹 [$eid] Candidate for deletion:"
                echo "   Type        : $etype"
                echo "   Path        : $epath"
                echo "   Site-Pkgs   : $esp"
                echo "   __pycache__ : $epc"
                read -p "   ❓ Delete this environment? [y/N]: " confirm
                [[ "$confirm" != "y" && "$confirm" != "Y" ]] && echo "   ❌ Skipped." && return
            fi

            echo "🧹 Deleting ID $id [$etype]..."
            if [[ "$DRY_RUN" == true ]]; then
                echo "   💡 Dry-run: would delete $epath"
                return
            fi
            case "$mode" in
                native|interactive)
                    rm -rf "$epath"
                    ;;
                cli)
                    case "$etype" in
                        pyenv) pyenv uninstall -f "$(basename "$epath")" ;;
                        asdf) asdf uninstall python "$(basename "$epath")" ;;
                        miniconda|anaconda) conda env remove -n "$(basename "$epath")" ;;
                        pipx) pipx uninstall "$(basename "$epath")" ;;
                        venv|poetry|system|*) rm -rf "$epath" ;;
                    esac
                    ;;
            esac
            echo "✅ Deleted $epath"
        fi
    done
}

print_header

case "$1" in
    discover)
        discover_envs
        list_envs
        write_registry
        ;;
    list)
        load_registry
        list_envs
        ;;
    delete)
        load_registry
        shift
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --cli) MODE="cli" ;;
                --native) MODE="native" ;;
                --interactive) MODE="interactive" ;;
                --dry-run) DRY_RUN=true ;;
                *) delete_env_by_id "$1" "$MODE" ;;
            esac
            shift
        done
        ;;
    help|*)
        echo "Usage:"
        echo "  $0 discover         → Scan and register all environments"
        echo "  $0 list             → List cached environments"
        echo "  $0 delete <ID..>    → Delete env(s) by ID"
        echo "     Options: --cli, --native, --interactive (default), --dry-run"
        ;;
esac
