__bashmaster_config_get() {
    local file=$1 key=$2 default=${3:-} line
    BM_CONFIG_VALUE=$default
    [[ ! -L $BASHMASTER_ROOT/config && ! -L ${file%/*} && ! -L $file ]] || {
        __bashmaster_error "refusing to read through a symlinked configuration path: $file"
        return 1
    }
    [[ -f $file ]] || return 0
    while IFS= read -r line || [[ -n $line ]]; do
        [[ $line == "$key="* ]] || continue
        BM_CONFIG_VALUE=${line#*=}
        return 0
    done < "$file"
}

__bashmaster_config_bool() {
    case ${1:-} in
        1|yes|true|on) return 0 ;;
        0|no|false|off) return 1 ;;
        *)
            __bashmaster_error "invalid boolean setting: $1"
            return 2
            ;;
    esac
}
