#!/bin/bash
# Copyright @ 2107 Michael P. Reilly.  All rights reserved.
# A subshell to run a command or interactive shell within a workspace.

#set -x


if [ x${_WS_SOURCE:+X} = xX ] && [ -r "${_WS_SOURCE}" ]; then
    :
elif [ -r $HOME/.ws/ws.sh ]; then
    _WS_SOURCE=$HOME/.ws/ws.sh
elif [ -r $HOME/.bash.d/ws.sh ]; then
    _WS_SOURCE=$HOME/.bash.d/ws.sh
elif [ -r $HOME/.bash/ws.sh ]; then
    _WS_SOURCE=$HOME/.bash/ws.sh
else
    echo "Error: unable to find ws.sh" >&2
    exit 255
fi

export _WS_SOURCE
source "$_WS_SOURCE"

if [ $# -gt 0 ]; then
    while true; do
        case $1 in
            -h|--help)
                echo "$0 {workspace} [cmd args...]"
                echo "$0 -h|--help||--version"
                exit
                ;;
            --version)
                echo "$WS_VERSION"
                exit
                ;;
            -*|--*)
                echo "Uknown option: $1" >&2
                exit 1
                ;;
            *)
                break
                ;;
        esac
    done
fi

if [ $# -lt 1 ]; then
    echo "Error: expecting workspace" >&2
    exit 1
else
    wsname=$1
    shift
fi
_ws_cmd_enter $wsname

if [ $# -gt 0 ]; then
    exec env _WS_SHELL_WORKSPACE="$wsname" $SHELL -i "$@"
else
    exec env _WS_SHELL_WORKSPACE="$wsname" $SHELL -i
fi
