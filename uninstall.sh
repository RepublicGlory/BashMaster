#!/usr/bin/env bash
set -euo pipefail

INSTALL_ROOT="${HOME:?HOME must be set}/.bashmaster"
ASSUME_YES=0
BACKUP_CONFIG=0

on_error() {
    local status=$?
    printf 'uninstall.sh: failed near line %s (status %s)\n' "${BASH_LINENO[0]:-${LINENO}}" "$status" >&2
    exit "$status"
}
trap on_error ERR

usage() {
    printf 'Usage: %s [--install-dir DIR] [--yes] [--backup]\n' "${0##*/}"
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
        --backup)
            BACKUP_CONFIG=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'uninstall.sh: unknown option: %s\n' "$1" >&2
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
if [[ -L $INSTALL_ROOT ]]; then
    printf 'uninstall.sh: refusing a symlink as install root: %s\n' "$INSTALL_ROOT" >&2
    exit 1
fi
if [[ $INSTALL_ROOT == / || $INSTALL_ROOT == "$HOME" ||
      ! -f $INSTALL_ROOT/.bashmaster-install ]]; then
    printf 'uninstall.sh: refusing to remove an unrecognized installation: %s\n' "$INSTALL_ROOT" >&2
    exit 1
fi
if [[ $(<"$INSTALL_ROOT/.bashmaster-install") != 'BashMaster managed install v1' ]]; then
    printf 'uninstall.sh: refusing to remove an unrecognized installation: %s\n' "$INSTALL_ROOT" >&2
    exit 1
fi

if (( ! ASSUME_YES )); then
    [[ -t 0 ]] || {
        printf 'uninstall.sh: non-interactive use requires --yes\n' >&2
        exit 2
    }
    printf 'Remove BashMaster from %s? [y/N] ' "$INSTALL_ROOT"
    read -r answer
    [[ $answer == [yY] || $answer == [yY][eE][sS] ]] || {
        printf 'Uninstallation cancelled.\n'
        exit 1
    }
fi

source "$INSTALL_ROOT/lib/rc.sh"
if (( BACKUP_CONFIG )) && [[ -d $INSTALL_ROOT/config ]]; then
    timestamp=$(date '+%Y%m%d%H%M%S')
    backup="${INSTALL_ROOT}.backup.${timestamp}.tar.gz"
    if [[ -e $backup || -L $backup ]]; then
        backup="${INSTALL_ROOT}.backup.${timestamp}.$$.tar.gz"
    fi
    [[ ! -e $backup && ! -L $backup ]] || {
        printf 'uninstall.sh: backup path already exists: %s\n' "$backup" >&2
        exit 1
    }
    tar -C "$INSTALL_ROOT" -czf "$backup" config
    printf 'Configuration backup saved to %s\n' "$backup"
fi

rc_had_block=0
if [[ -f $HOME/.bashrc ]] &&
   [[ $(grep -Fxc '# >>> BashMaster >>>' "$HOME/.bashrc" || :) == 1 ]] &&
   [[ $(grep -Fxc '# <<< BashMaster <<<' "$HOME/.bashrc" || :) == 1 ]]; then
    rc_had_block=1
fi
staging="${INSTALL_ROOT}.uninstall.$$"
[[ ! -e $staging && ! -L $staging ]] || {
    printf 'uninstall.sh: temporary path already exists: %s\n' "$staging" >&2
    exit 1
}
mv -- "$INSTALL_ROOT" "$staging"
if ! bm_rc_edit remove "$HOME/.bashrc" "$staging"; then
    mv -- "$staging" "$INSTALL_ROOT" || :
    printf 'uninstall.sh: rc update failed; attempted to restore the installation\n' >&2
    exit 1
fi
if ! rm -rf -- "$staging"; then
    if mv -- "$staging" "$INSTALL_ROOT"; then
        if (( rc_had_block )); then
            bm_rc_edit install "$HOME/.bashrc" "$INSTALL_ROOT" || :
        fi
    fi
    printf 'uninstall.sh: failed to remove installation; attempted rollback\n' >&2
    exit 1
fi

if [[ -e $INSTALL_ROOT ]]; then
    printf 'uninstall.sh: installation root remains: %s\n' "$INSTALL_ROOT" >&2
    exit 1
fi
if [[ -f $HOME/.bashrc ]] &&
   grep -Fq '# >>> BashMaster >>>' "$HOME/.bashrc"; then
    printf 'uninstall.sh: BashMaster block remains in ~/.bashrc\n' >&2
    exit 1
fi
printf 'BashMaster uninstalled; no managed root or marked .bashrc block remains.\n'
