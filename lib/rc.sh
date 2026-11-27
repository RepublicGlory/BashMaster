BM_RC_START='# >>> BashMaster >>>'
BM_RC_END='# <<< BashMaster <<<'

bm_rc_error() {
    printf 'BashMaster: %s\n' "$*" >&2
}

bm_rc_remove_from_file() {
    local rc_file=$1 output=$2
    local starts=0 ends=0
    if [[ -f $rc_file ]]; then
        starts=$(grep -Fxc -- "$BM_RC_START" "$rc_file" || :)
        ends=$(grep -Fxc -- "$BM_RC_END" "$rc_file" || :)
    fi
    if [[ $starts == 0 && $ends == 0 ]]; then
        if [[ -f $rc_file ]]; then
            cat -- "$rc_file" > "$output" || return 1
        else
            : > "$output"
        fi
        return 0
    fi
    if [[ $starts != 1 || $ends != 1 ]]; then
        bm_rc_error 'refusing to edit .bashrc: marked block is malformed or duplicated'
        return 1
    fi
    awk -v start="$BM_RC_START" -v end="$BM_RC_END" '
        $0 == start {
            if (inside) bad = 1
            inside = 1
            next
        }
        $0 == end {
            if (!inside) bad = 1
            inside = 0
            next
        }
        !inside { print }
        END {
            if (inside || bad) exit 2
        }
    ' "$rc_file" > "$output" || {
        bm_rc_error 'refusing to edit .bashrc: marked block is unbalanced'
        return 1
    }
}

bm_rc_validate() {
    local rc_file=$1 temporary
    [[ ! -L $rc_file ]] || {
        bm_rc_error "refusing to edit a symlinked rc file: $rc_file"
        return 1
    }
    temporary=$(mktemp "${TMPDIR:-/tmp}/bashmaster-rc-check.XXXXXX") || return 1
    if ! bm_rc_remove_from_file "$rc_file" "$temporary"; then
        rm -f -- "$temporary"
        return 1
    fi
    rm -f -- "$temporary"
}

bm_rc_backup() {
    local rc_file=$1 timestamp backup suffix=0
    [[ -f $rc_file ]] || return 0
    timestamp=$(date '+%Y%m%d%H%M%S')
    backup="${rc_file}.bashmaster.${timestamp}.bak"
    while [[ -e $backup || -L $backup ]]; do
        suffix=$((suffix + 1))
        backup="${rc_file}.bashmaster.${timestamp}.$$.$suffix.bak"
    done
    cp -p -- "$rc_file" "$backup"
    printf 'BashMaster: backed up %s to %s\n' "$rc_file" "$backup"
}

bm_rc_edit() {
    local operation=$1 rc_file=$2 root=${3:-}
    local directory temporary filtered quoted_source starts ends state=0 block_at_end=0
    bm_rc_validate "$rc_file" || return 1
    directory=${rc_file%/*}
    [[ $directory != "$rc_file" ]] || directory=.
    mkdir -p -- "$directory"
    temporary=$(mktemp "$directory/.bashmaster-rc.XXXXXX")
    filtered=$(mktemp "$directory/.bashmaster-rc.XXXXXX")
    if [[ -f $rc_file ]]; then
        starts=$(grep -Fxc -- "$BM_RC_START" "$rc_file" || :)
        ends=$(grep -Fxc -- "$BM_RC_END" "$rc_file" || :)
        [[ $starts == 1 && $ends == 1 && $(tail -n 1 -- "$rc_file") == "$BM_RC_END" ]] &&
            block_at_end=1
    fi
    if ! bm_rc_remove_from_file "$rc_file" "$filtered"; then
        rm -f -- "$temporary" "$filtered"
        return 1
    fi

    case $operation in
        install)
            printf -v quoted_source '%q' "$root/lib/bootstrap.sh"
            if [[ $block_at_end == 1 && -f $root/config/rc_added_newline ]]; then
                state=$(<"$root/config/rc_added_newline")
            elif [[ -s $rc_file ]] && [[ $(tail -c 1 -- "$rc_file" | wc -l) == 0 ]]; then
                state=1
            fi
            [[ $state == 0 || $state == 1 ]] || {
                bm_rc_error 'invalid rc rollback metadata'
                rm -f -- "$temporary" "$filtered"
                return 1
            }
            if [[ -s $filtered ]] && [[ $(tail -c 1 -- "$filtered" | wc -l) == 0 ]]; then
                printf '\n' >> "$filtered"
            fi
            printf '%s\n' "$BM_RC_START" >> "$filtered"
            printf 'if [[ $- == *i* && -t 0 && -t 1 && -r %s ]]; then source %s; fi\n' \
                "$quoted_source" "$quoted_source" >> "$filtered"
            printf '%s\n' "$BM_RC_END" >> "$filtered"
            printf '%s\n' "$state" > "$root/config/rc_added_newline"
            ;;
        remove)
            ;;
        *)
            bm_rc_error "unknown .bashrc operation: $operation"
            rm -f -- "$temporary" "$filtered"
            return 2
            ;;
    esac

    if [[ $operation == remove && ! -f $rc_file ]]; then
        rm -f -- "$temporary" "$filtered"
        return 0
    fi
    if [[ $operation == remove && $block_at_end == 1 && -n $root &&
          -f $root/config/rc_added_newline &&
          $(<"$root/config/rc_added_newline") == 1 && -s $filtered ]]; then
        truncate -s -1 "$filtered"
    fi
    if [[ -f $rc_file ]] && cmp -s -- "$rc_file" "$filtered"; then
        rm -f -- "$temporary" "$filtered"
        return 0
    fi
    bm_rc_backup "$rc_file"
    if [[ -f $rc_file ]]; then
        if ! chmod --reference="$rc_file" "$filtered"; then
            rm -f -- "$temporary" "$filtered"
            return 1
        fi
    fi
    if ! mv -- "$filtered" "$rc_file"; then
        rm -f -- "$temporary" "$filtered"
        return 1
    fi
    rm -f -- "$temporary"
}
