__bashmaster_error() {
    printf 'bashmaster: %s\n' "$*" >&2
}

__bashmaster_root() {
    if [[ -z ${BASHMASTER_ROOT:-} ]]; then
        __bashmaster_error 'BASHMASTER_ROOT is not set'
        return 1
    fi
}

__bashmaster_valid_name() {
    [[ ${1:-} =~ ^[a-z][a-z0-9_]*$ ]]
}

__bashmaster_split_csv() {
    local value=${1:-}
    local -A seen=()
    BM_CSV_ITEMS=()
    [[ -z $value ]] && return 0
    [[ $value != ,* && $value != *, && $value != *,,* ]] || return 1
    local IFS=,
    read -r -a BM_CSV_ITEMS <<< "$value"
    local item
    for item in "${BM_CSV_ITEMS[@]}"; do
        [[ $item =~ ^[a-z][a-z0-9_]*$ ]] || return 1
        [[ -z ${seen[$item]+present} ]] || return 1
        seen[$item]=1
    done
}
