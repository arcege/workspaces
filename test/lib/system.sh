:
# determine the system and necessary ramifications
# side effects
# * set $is_linux and $ws_uname
# exit with an error if unable to find uname or if unable to determine OS type

case $OSTYPE in
    darwin*) is_linux=false;;
    linux*) is_linux=true;;
    *)
        if [ -x /bin/uname ]; then
            ws_uname=/bin/uname
        elif [ -x /usr/bin/uname ]; then
            ws_uname=/usr/bin/uname
        else
            echo 'unable to find "uname" in /bin /or /usr/bin' >&2
            exit 1
        fi
        case $($ws_uname -s) in
            Darwin) is_linux=false;;
            Linux) is_linux=true;;
            *)
                echo "Unsupported system type"
                exit 1
                ;;
        esac
        ;;
esac
