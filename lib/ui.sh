__bashmaster_ui_clear() {
    printf '\033[H\033[2J'
}

__bashmaster_ui_select() {
    local count=$1
    (( count > 0 )) || return 1
    (
        local original selected=0 key escape sequence i
        original=$(stty -g < /dev/tty) || exit 1
        trap 'stty "$original" < /dev/tty' EXIT
        trap 'exit 130' INT
        stty -echo -icanon min 1 time 0 < /dev/tty || exit 1
        while :; do
            __bashmaster_ui_clear > /dev/tty
            printf 'BashMaster Quickbar  (up/down move, Enter run, q/Esc quit)\n\n' > /dev/tty
            for ((i = 0; i < count; i++)); do
                if (( i == selected )); then
                    printf '  > %s\n' "${BM_QUICKBAR_LABELS[i]}" > /dev/tty
                else
                    printf '    %s\n' "${BM_QUICKBAR_LABELS[i]}" > /dev/tty
                fi
            done
            if (( ${BM_QUICKBAR_TRUNCATED:-0} )); then
                printf '\nOnly the first 10 entries are shown.\n' > /dev/tty
            fi

            if ! IFS= read -r -s -n 1 key < /dev/tty; then
                printf '\n' > /dev/tty
                exit 1
            fi
            case $key in
                q|Q)
                    printf '\n' > /dev/tty
                    exit 1
                    ;;
                $'\r'|'')
                    printf '%s\n' "$selected"
                    exit 0
                    ;;
                $'\033')
                    sequence=
                    IFS= read -r -s -n 1 -t 0.1 escape < /dev/tty || :
                    if [[ $escape == '[' ]]; then
                        IFS= read -r -s -n 1 -t 0.1 sequence < /dev/tty || :
                        case $sequence in
                            A)
                                if (( selected > 0 )); then
                                    selected=$((selected - 1))
                                fi
                                ;;
                            B)
                                if (( selected + 1 < count )); then
                                    selected=$((selected + 1))
                                fi
                                ;;
                        esac
                    else
                        printf '\n' > /dev/tty
                        exit 1
                    fi
                    ;;
                *)
                    ;;
            esac
        done
    )
}
