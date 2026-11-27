#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
source "$SCRIPT_DIR/lib/rc.sh"

on_error() {
    local status=$?
    printf 'install.sh: failed near line %s (status %s)\n' "${BASH_LINENO[0]:-${LINENO}}" "$status" >&2
    exit "$status"
}
trap on_error ERR

INSTALL_ROOT="${HOME:?HOME must be set}/.bashmaster"
ASSUME_YES=0
EDIT_BASHRC=1

usage() {
    printf 'Usage: %s [--install-dir DIR] [--yes] [--no-bashrc]\n' "${0##*/}"
}

while (($#)); do
    case $1 in
        --install-dir)
            (($# >= 2)) || { usage >&2; exit 2; }
            INSTALL_ROOT=$2
            shift 2
            ;;
        --yes)
            ASSUME_YES=1
            shift
            ;;
        --no-bashrc)
            EDIT_BASHRC=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'install.sh: unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ $INSTALL_ROOT != /* ]]; then
    INSTALL_ROOT="$(pwd -P)/$INSTALL_ROOT"
fi
while [[ $INSTALL_ROOT != / && $INSTALL_ROOT == */ ]]; do
    INSTALL_ROOT=${INSTALL_ROOT%/}
done
if [[ $INSTALL_ROOT == / || $INSTALL_ROOT == "$HOME" ]]; then
    printf 'install.sh: refusing unsafe install root: %s\n' "$INSTALL_ROOT" >&2
    exit 1
fi
if [[ -L $INSTALL_ROOT ]]; then
    printf 'install.sh: refusing a symlink as install root: %s\n' "$INSTALL_ROOT" >&2
    exit 1
fi

if (( ! ASSUME_YES )); then
    [[ -t 0 ]] || {
        printf 'install.sh: non-interactive use requires --yes\n' >&2
        exit 2
    }
    printf 'Install BashMaster into %s? [y/N] ' "$INSTALL_ROOT"
    read -r answer
    [[ $answer == [yY] || $answer == [yY][eE][sS] ]] || {
        printf 'Installation cancelled.\n'
        exit 1
    }
fi

if (( EDIT_BASHRC )); then
    bm_rc_validate "$HOME/.bashrc"
fi

if [[ -L $INSTALL_ROOT/.bashmaster-install ]]; then
    printf 'install.sh: refusing a symlinked installation marker: %s\n' "$INSTALL_ROOT/.bashmaster-install" >&2
    exit 1
elif [[ -e $INSTALL_ROOT/.bashmaster-install ]]; then
    [[ $(<"$INSTALL_ROOT/.bashmaster-install") == 'BashMaster managed install v1' ]] || {
        printf 'install.sh: unrecognized installation marker in %s\n' "$INSTALL_ROOT" >&2
        exit 1
    }
elif [[ -d $INSTALL_ROOT ]] && [[ -n $(find "$INSTALL_ROOT" -mindepth 1 -maxdepth 1 -print -quit) ]]; then
    printf 'install.sh: refusing to overwrite a non-empty unmanaged directory: %s\n' "$INSTALL_ROOT" >&2
    exit 1
fi

if [[ -e $INSTALL_ROOT && ! -d $INSTALL_ROOT ]]; then
    printf 'install.sh: install root is not a directory: %s\n' "$INSTALL_ROOT" >&2
    exit 1
fi
for managed_path in bin lib builtin config plugins plugins/available plugins/enabled cache logs docs; do
    if [[ -L $INSTALL_ROOT/$managed_path ]]; then
        printf 'install.sh: refusing a symlinked managed path: %s\n' "$INSTALL_ROOT/$managed_path" >&2
        exit 1
    fi
done
for config_path in \
    "$INSTALL_ROOT/install.sh" \
    "$INSTALL_ROOT/uninstall.sh" \
    "$INSTALL_ROOT/README.md" \
    "$INSTALL_ROOT/config/bashmaster.conf" \
    "$INSTALL_ROOT/config/bashmaster.conf.example" \
    "$INSTALL_ROOT/config/trusted.list" \
    "$INSTALL_ROOT/config/splash.conf.example" \
    "$INSTALL_ROOT/config/quickbar.conf.example" \
    "$INSTALL_ROOT/config/splash" \
    "$INSTALL_ROOT/config/quickbar" \
    "$INSTALL_ROOT/config/splash/config.conf" \
    "$INSTALL_ROOT/config/quickbar/config.conf"; do
    if [[ -L $config_path ]]; then
        printf 'install.sh: refusing a symlinked configuration path: %s\n' "$config_path" >&2
        exit 1
    fi
done

for managed_tree in bin lib builtin docs; do
    if [[ -d $INSTALL_ROOT/$managed_tree ]] &&
       find "$INSTALL_ROOT/$managed_tree" -type l -print -quit | grep -q .; then
        printf 'install.sh: refusing symbolic links under managed directory: %s\n' \
            "$INSTALL_ROOT/$managed_tree" >&2
        exit 1
    fi
done

mkdir -p -- "$INSTALL_ROOT"/{bin,lib,builtin,config,plugins/available,plugins/enabled,cache,logs,docs}
printf '%s\n' 'BashMaster managed install v1' > "$INSTALL_ROOT/.bashmaster-install"
chmod 600 "$INSTALL_ROOT/.bashmaster-install"

cp -R -- "$SCRIPT_DIR/lib/." "$INSTALL_ROOT/lib/"
cp -- "$SCRIPT_DIR/bin/bashmaster" "$INSTALL_ROOT/bin/bashmaster"
cp -- "$SCRIPT_DIR/install.sh" "$INSTALL_ROOT/install.sh"
cp -- "$SCRIPT_DIR/uninstall.sh" "$INSTALL_ROOT/uninstall.sh"
chmod 755 "$INSTALL_ROOT/bin/bashmaster"
chmod 755 "$INSTALL_ROOT/install.sh" "$INSTALL_ROOT/uninstall.sh"
cp -R -- "$SCRIPT_DIR/builtin/." "$INSTALL_ROOT/builtin/"
cp -R -- "$SCRIPT_DIR/docs/." "$INSTALL_ROOT/docs/"
cp -- "$SCRIPT_DIR/README.md" "$INSTALL_ROOT/README.md"
cp -R -- "$SCRIPT_DIR/config/." "$INSTALL_ROOT/config/"

for plugin_dir in "$SCRIPT_DIR"/builtin/*; do
    [[ -d $plugin_dir ]] || continue
    plugin_name=${plugin_dir##*/}
    installed_dir="$INSTALL_ROOT/plugins/available/$plugin_name"
    if [[ ! -e $installed_dir && ! -L $installed_dir ]]; then
        cp -R -- "$plugin_dir" "$installed_dir"
    fi
done

if [[ ! -f $INSTALL_ROOT/config/bashmaster.conf ]]; then
    cp -- "$SCRIPT_DIR/config/bashmaster.conf.example" "$INSTALL_ROOT/config/bashmaster.conf"
fi
mkdir -p -- "$INSTALL_ROOT/config/splash" "$INSTALL_ROOT/config/quickbar"
if [[ ! -f $INSTALL_ROOT/config/splash/config.conf ]]; then
    cp -- "$SCRIPT_DIR/config/splash.conf.example" "$INSTALL_ROOT/config/splash/config.conf"
fi
if [[ ! -f $INSTALL_ROOT/config/quickbar/config.conf ]]; then
    cp -- "$SCRIPT_DIR/config/quickbar.conf.example" "$INSTALL_ROOT/config/quickbar/config.conf"
fi
touch "$INSTALL_ROOT/config/trusted.list"
chmod 600 "$INSTALL_ROOT/config/trusted.list"

if (( EDIT_BASHRC )); then
    bm_rc_edit install "$HOME/.bashrc" "$INSTALL_ROOT"
fi

printf 'BashMaster installed at %s\n' "$INSTALL_ROOT"
