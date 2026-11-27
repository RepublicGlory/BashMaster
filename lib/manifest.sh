declare -gA BM_MANIFEST=()
BM_CSV_ITEMS=()

__bashmaster_manifest_validate() {
    local directory=${1:-} expected_name=${2:-}
    local file="$directory/plugin.conf"
    local line key value
    local -A seen=()
    BM_MANIFEST=()

    [[ -d $directory && ! -L $directory &&
       -f $file && ! -L $file &&
       -f $directory/plugin.sh && ! -L $directory/plugin.sh ]] || {
        __bashmaster_error "plugin package must contain plugin.conf and plugin.sh: $directory"
        return 1
    }

    while IFS= read -r line || [[ -n $line ]]; do
        [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
        [[ $line == *=* ]] || {
            __bashmaster_error "invalid manifest line in $file"
            return 1
        }
        key=${line%%=*}
        value=${line#*=}
        [[ $key =~ ^(name|version|description|hooks|commands)$ ]] || {
            __bashmaster_error "unknown manifest key '$key' in $file"
            return 1
        }
        [[ -z ${seen[$key]+present} ]] || {
            __bashmaster_error "duplicate manifest key '$key' in $file"
            return 1
        }
        seen[$key]=1
        BM_MANIFEST[$key]=$value
    done < "$file"

    for key in name version description hooks commands; do
        [[ -n ${seen[$key]+present} ]] || {
            __bashmaster_error "missing manifest key '$key' in $file"
            return 1
        }
    done
    __bashmaster_valid_name "${BM_MANIFEST[name]}" || {
        __bashmaster_error "invalid plugin name in $file"
        return 1
    }
    [[ -z $expected_name || ${BM_MANIFEST[name]} == "$expected_name" ]] || {
        __bashmaster_error "plugin name does not match directory: $directory"
        return 1
    }
    [[ ${BM_MANIFEST[version]} =~ ^[0-9][A-Za-z0-9.+_-]*$ ]] || {
        __bashmaster_error "invalid plugin version in $file"
        return 1
    }
    [[ -n ${BM_MANIFEST[description]} && ${BM_MANIFEST[description]} != *$'\r'* ]] || {
        __bashmaster_error "invalid plugin description in $file"
        return 1
    }

    __bashmaster_split_csv "${BM_MANIFEST[hooks]}" || {
        __bashmaster_error "invalid hooks list in $file"
        return 1
    }
    local hook
    for hook in "${BM_CSV_ITEMS[@]}"; do
        case $hook in
            on_load|on_unload|on_prompt) ;;
            *)
                __bashmaster_error "unsupported hook '$hook' in $file"
                return 1
                ;;
        esac
    done
    __bashmaster_split_csv "${BM_MANIFEST[commands]}" || {
        __bashmaster_error "invalid commands list in $file"
        return 1
    }
}

__bashmaster_manifest_declares() {
    local list=${BM_MANIFEST[$1]:-} item
    shift
    __bashmaster_split_csv "$list" || return 1
    for item in "${BM_CSV_ITEMS[@]}"; do
        [[ $item == "$1" ]] && return 0
    done
    return 1
}
