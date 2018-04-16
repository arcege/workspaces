:
# determine the system and necessary ramifications
# side effects
# * clear out $PATH
# * set $is_linux and $ws_uname
# * redirect stderr to test.err
# * redirect fd3 to stderr
# * redirect fd4 to /dev/null
# exit with an error if unable to find uname or if unable to determine OS type

# handle internal redirection
exec 2>test.err 3>&2 4>/dev/null

# clear the path, use explicit pathnames in the test script, this
# will ensure that aliases and functions cannot corrupt
PATH=

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
