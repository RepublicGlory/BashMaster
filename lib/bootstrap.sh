if [[ $- != *i* || ! -t 0 || ! -t 1 ]]; then
    return 0
fi

if [[ ${__BASHMASTER_INITIALIZED:-0} == 1 ]]; then
    return 0
fi

__BASHMASTER_ROOT_WAS_SET=0
__BASHMASTER_PREVIOUS_ROOT=${BASHMASTER_ROOT:-}
[[ ${BASHMASTER_ROOT+x} ]] && __BASHMASTER_ROOT_WAS_SET=1
BASHMASTER_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
export BASHMASTER_ROOT
__BASHMASTER_INITIALIZED=1

source "$BASHMASTER_ROOT/lib/common.sh"
source "$BASHMASTER_ROOT/lib/config.sh"
source "$BASHMASTER_ROOT/lib/audit.sh"
source "$BASHMASTER_ROOT/lib/manifest.sh"
source "$BASHMASTER_ROOT/lib/plugin.sh"
source "$BASHMASTER_ROOT/lib/ui.sh"
source "$BASHMASTER_ROOT/lib/cli.sh"

bashmaster() {
    __bashmaster_cli_main "$@"
}

__bashmaster_config_get "$BASHMASTER_ROOT/config/bashmaster.conf" startup 1
if __bashmaster_config_bool "$BM_CONFIG_VALUE"; then
    __bashmaster_load_enabled
fi
