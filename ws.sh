#!/bin/bash
# A shell program to handle workspaces in parallel with virtualenv.
# Environment variables are set to the desired workspace.

# process arguments and options
# operations
#   enter [name]    - set envvars and change to workspace directory, if no
#                     name given, then show current workspace
#   leave           - leave workspace, resetting envvars and directory
#   create <name>   - create a new workspace
#   destroy <name>  - delete an existing workspace
#   current         - show the current workspace (same as enter operator with no name)
#   relink          - (re)create ~/workspace symbolic link
#   list            - show workspaces, '*' shows which is linked with
#                     with ~/workspace
#   initialize      - (re)create the environment
#   [name]          - same as enter operator
#
# if a workspace has a '.ws.sh' script at the top, it will get source'd with
# the arguments 'enter' or 'leave' when thoe operations are performed
# this is useful for setting and unsetting environment variables or running
# commands specific to a workspace

if [ -z "$BASH_VERSION" ]; then
    echo This requires running in a bash shell.  Exiting. >&2
    return 1
fi

# global constants, per shell
: ${WS_DIR:=$HOME/workspaces}
# it may seem controversial to make such a variable read-only, but when
# the entire foundation of the program is based on this structure
# existing, it doesn't seem unreasonable, especially when a new shell
# could be spawned with WS_DIR set differently.
declare -r WS_DIR  # make it read-only
declare _ws__current
declare -a _ws__stack
declare -i _ws__stkpos

if [ ${#_ws__stack[@]} -eq 0 ]; then
    # if the stack is not empty, assume some things are already configured
    _ws__current=""
    _ws__stack=()
    _ws__stkpos=0
fi

_ws_stack () {
    # implement a stack
    case $1 in
        last)
            if [ $_ws__stkpos -gt 0 ]; then
                echo "${_ws__stack[$_ws__stkpos]}"
            else
                return 1
            fi
            ;;
        push)
            let _ws__stkpos++
            _ws__stack[$_ws__stkpos]="$2"
            ;;
        pop)
            # should run __ws_stack last before running pop as we don't return it
            if [ $_ws__stkpos -gt 0 ]; then
                unset _ws__stack[$_ws__stkpos]
                let _ws__stkpos--
            else
                return 1
            fi
            ;;
        size):
            echo $_ws__stkpos
            ;;
        state)
            echo "stack.pos=$_ws__stkpos"
            echo "stack=${_ws__stack[*]}"
            ;;
        *) echo "ws_stack: invalid op: $1" >&2; return 2;;
    esac
}

_ws_validate () {
    local index linkptr wsdir=$(_ws_getdir "$_ws__current")
    linkptr=$(_ws_getlink)
    if [ ${#_ws__stack[*]} -ne $_ws__stkpos ]; then
        _ws__stkpos=$index
    fi
    if [ ! -d "$linkptr" ]; then
        echo "Error: $HOME/workspace pointing nowhere; removing" >&2
        rm -f $HOME/workspace
    fi
    if [ x${_ws__current:+X} = xX -a ! -d "$wsdir" ]; then
        echo "Error: $_ws__current is not a valid workspace; leaving" >&2
        _ws_leave
    fi
}

_ws_getdir () {
    # print the workspace directory for a name, return 1 if it does not exist
    local wsdir="$WS_DIR/${1:-$_ws__current}"
    echo "$wsdir"
    if [ ! -d "$wsdir" ]; then
        return 1
    fi
}

_ws_getlink () {
    # print the referent or return 1 if exists and is not a symlink
    if [ -h $HOME/workspace ]; then
        readlink $HOME/workspace
    else
        return 1
    fi
}

_ws_resetlink () {
    # change the symlink, or error if exists and is not a symlink
    if [ -z "$1" -o ! -d "$1" ]; then
        echo "Error: invalid workspace" >&2
        return 1
    elif [ ! -e $HOME/workspace -o -h $HOME/workspace ]; then
        rm -f $HOME/workspace
        ln -s "$1" $HOME/workspace
    elif [ -e $HOME/workspace ]; then
        echo Error: ~/workspace is not a symlink. >&2
        return 1
    fi
}

_ws_generate_config () {
    # Create an empty configuration script in the workspace
    cat <<'EOF' > $1/.ws.sh
:
# this is sourced by `ws` (workspaces)
# commands could be run and the environment/shell could be modified
# anything set by the enter operation should be wound back by leave

case ${1:-enter} in
    enter)
        ;;

    leave)
        ;;
esac
EOF
}

_ws_config () {
    # run $HOME/.ws.sh script, passing either "enter" or "leave"
    # run $WORKSPACE/.ws.sh script, passing either "enter" or "leave"
    # calls to .ws.sh are NOT sandboxed as they should affect the environment
    # the 'leave' should try to put back anything that was change by 'enter'
    if [ x${_ws__current:+X} = xX ]; then
        local op="${1:-enter}"
        local wsdir=$(_ws_getdir)
        if [ -f "$HOME/.ws.sh" ]; then
            source "$HOME/.ws.sh" "$op"
        fi
        if [ -f "$wsdir/.ws.sh" ]; then
            source "$wsdir/.ws.sh" "$op"
        fi
    fi
}

_ws_enter () {
    # enter the workspace, setting the environment variables and chdir
    # if link=true, then update ~/workspace
    local wsdir wsname=${1:-""}
    wsdir="$(_ws_getdir "$wsname")"
    if [ -z "$wsname" ]; then
        if [ -n "$_ws__current" ]; then
            echo "$_ws__current"
            return 0
        fi
    elif [ ! -d "$wsdir" ]; then
        echo "No workspace exists for $wsname" >&2
        return 1
    else
        _ws_config leave
        if [ -n "$_ws__current" ]; then
            _ws_stack push "$_ws__current:$PWD"
        else
            _ws_stack push "$WORKSPACE:$PWD"
        fi
        _ws__current="$wsname"
        export WORKSPACE="$wsdir"
        cd "$wsdir"
        _ws_config enter
    fi
}

_ws_leave () {
    local oldws oldIFS wsname wsdir
    if [ x{$_ws__current:+X} != xX ]; then
        _ws_config leave
        oldws=$(_ws_stack last)
        oldIFS="$IFS"
        IFS=":"
        set -- $oldws
        IFS="$oldIFS"
        case $1 in
            ""|/*) wsname=""; wsdir="$1";;
            *) wsname="$1"; wsdir=$(_ws_getdir "$wsname");;
        esac
        _ws__current="$wsname"
        _ws_stack pop
        if [ $? -eq 0 ]; then
            export WORKSPACE="$wsdir"
        fi
        cd "$2"  # return to old directory
        _ws_config enter
    fi
}

_ws_create () {
    local wsdir wsname=${1:-""}
    wsdir="$(_ws_getdir "$wsname")"
    if [ -z "$wsname" ]; then
        echo "No name given" >&2
        return 1
    elif [ -d "$wsdir" ]; then
        echo "Workspace already exists" >&2
        return 1
    else
        mkdir "$wsdir"
        _ws_generate_config "$wsdir"
    fi
}

_ws_destroy () {
    local linkptr wsdir wsname=${1:-""}
    wsdir="$(_ws_getdir "$wsname")"
    if [ -z "$wsname" ]; then
        echo "No name given" >&2
        return 1
    elif [ ! -d "$wsdir" ]; then
        echo "No workspace exists" >&2
        return 1
    else
        if [ "$wsname" = "$_ws__current" ]; then
            _ws_leave
        fi
        rm -rf "$wsdir"
        linkptr=$(_ws_getlink)
        if [ $? -eq 0 -a "x$linkptr" = "x$wsdir" ]; then
            rm -f $HOME/workspace
            echo "~/workspace removed"
        fi
    fi
}

_ws_relink () {
    local wsdir wsname="${1:-$_ws__current}"
    if [ -z "$wsname" ]; then
        echo "No name given" >&2
        return 1
    else
        wsdir="$(_ws_getdir $wsname)"
        if [ $? -eq 0 ]; then
            _ws_resetlink "$wsdir"
        else
            echo "No workspace exists" >&2
            return 1
        fi
    fi
}

_ws_list () {
    local link sedscript
    link=$(_ws_getlink)
    if [ $? -eq 1 ]; then
        sedscript=':noop'
    else
        sedscript="/$(basename $link)/s/\$/*/"
    fi
    ls -1 $WS_DIR | sed -e "$sedscript"
}

ws () {
    if [ "x$1" = x--help -o "x$1" = x-h ]; then
        set -- help
    fi
    case $1 in
        help)
            cat <<'EOF'
ws [<cmd>] [<name>]
  enter [<name>]             - show the current workspace or enter one
  leave                      - leave current workspace
  create <name>              - create a new workspace
  destroy name               - destroy a workspace
  current                    - show current workspace (same as \`ws enter\`)
  relink [<name>]            - reset ~/workspace symlink
  list                       - show available workspaces
  initialize                 - create the workspaces structure
  [<name>]                   - same as 'ws enter [<name>]'
EOF
            ;;
        enter)
            _ws_enter "$2"
            ;;
        leave)
            _ws_leave
            ;;
        create)
            _ws_create "$2"
            _ws_enter "$2"
            ;;
        destroy)
            _ws_destroy "$2"
            ;;
        current)
            _ws_enter ""
            ;;
        relink)
            _ws_relink "$2"
            ;;
        list)
            _ws_list
            ;;
        state)
            echo "root=$WS_DIR" "ws='$_ws__current'"
            _ws_stack state
            _ws_list | tr '\n' ' '; echo
            ;;
        validate)
            _ws_validate
            ;;
        initialize)
            mkdir -p $WS_DIR
            # we don't want to delete it
            _ws_create default
            _ws_resetlink $(_ws_getdir default)
            _ws_generate_config "${HOME}"
            ;;
        *)
            _ws_enter "$1"
            ;;
    esac
}

if echo $- | fgrep -q i; then  # only for interactive
    _ws_complete () {
        # handle bash completion
        local cur prev options commands
        COMPREPLY=()
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        options="-h --help"
        commands="create current destroy enter help initialize leave list relink"
        results=$(ws list | tr -d '*' | tr '\n' ' ')
        if [ $COMP_CWORD -eq 1 ] || [[ "${prev:0:1}" == "-" ]]; then
            COMPREPLY=( $(compgen -W "$commands $options $results" -- ${cur}) )
            return 0
        else
            case $prev in
                enter|destroy)
                    COMPREPLY=($(compgen -W "$results" -- $cur))
                    return 0
                    ;;
            esac
        fi
    }

    # activate bash completion
    complete -F _ws_complete ws
fi

