bm_splash_setting_enabled() {
    local key=$1 default=$2
    __bashmaster_config_get "$BASHMASTER_ROOT/config/splash/config.conf" "$key" "$default"
    case $BM_CONFIG_VALUE in
        1|yes|true|on) return 0 ;;
        0|no|false|off) return 1 ;;
        *)
            __bashmaster_error "invalid splash setting '$key=$BM_CONFIG_VALUE'"
            return 2
            ;;
    esac
}

bm_splash_render() {
    local show_user=0 show_host=0 show_time=0 show_os=0
    local setting status os_name= os_line
    if [[ ${1:-} != force ]]; then
        if bm_splash_setting_enabled enabled 1; then
            :
        else
            status=$?
            (( status == 1 )) && return 0
            return "$status"
        fi
    fi
    for setting in show_user show_host show_time show_os; do
        if bm_splash_setting_enabled "$setting" 1; then
            case $setting in
                show_user) show_user=1 ;;
                show_host) show_host=1 ;;
                show_time) show_time=1 ;;
                show_os) show_os=1 ;;
            esac
        else
            status=$?
            (( status == 1 )) || return "$status"
        fi
    done

    printf '\n'
    printf '###  ##   ### #  # #   #  ##   ### ##### #### ### \n'
    printf '#  # #  # #    #  # ## ## #  # #      #   #  #  \n'
    printf '###  ####  ##  #### # # # ####  ##    #   ###   \n'
    printf '#  # #  #    # #  # #   # #  #    #   #   #  #  \n'
    printf '###  #  # ###  #  # #   # #  # ###  #### ###    \n'
    printf '                 BASHMASTER                      \n'
    printf '\n'
    (( show_user )) && printf '  User: %s\n' "$(id -un)"
    (( show_host )) && printf '  Host: %s\n' "$(hostname)"
    (( show_time )) && printf '  Time: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    if (( show_os )); then
        if [[ -r /etc/os-release ]]; then
            while IFS= read -r os_line; do
                [[ $os_line == PRETTY_NAME=* ]] || continue
                os_name=${os_line#PRETTY_NAME=}
                os_name=${os_name#\"}
                os_name=${os_name%\"}
                break
            done < /etc/os-release
        fi
        printf '  OS:   %s\n' "${os_name:-$(uname -s)}"
    fi
    printf '\n'
}

bm_splash_on_load() {
    bm_splash_render
}

bm_splash_command_splash() {
    bm_splash_render force
}
