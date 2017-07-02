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
: ${_ws_rootdir:=$HOME/workspaces}
declare -r _ws_rootdir  # make it read-only
declare _ws_current
declare -a _ws_stack
declare -i _ws_stkpos

if [ ${#_ws_stack[@]} -eq 0 ]; then
    # if the stack is not empty, assume some things are already configured
    _ws_current=""
    _ws_stack=()
    _ws_stkpos=0
fi

_ws__stack () {
    # implement a stack
    case $1 in
        last)
            if [ $_ws_stkpos -gt 0 ]; then
                echo "${_ws_stack[$_ws_stkpos]}"
            else
                return 1
            fi
            ;;
        push)
            let _ws_stkpos++
            _ws_stack[$_ws_stkpos]="$2"
            ;;
        pop)
            # should run __ws__stack last before running pop as we don't return it
            if [ $_ws_stkpos -gt 0 ]; then
                unset _ws_stack[$_ws_stkpos]
                let _ws_stkpos--
            else
                return 1
            fi
            ;;
        size):
            echo $_ws_stkpos
            ;;
        state)
            echo "stack.pos=$_ws_stkpos"
            echo "stack=${_ws_stack[*]}"
            ;;
        *) echo "ws_stack: invalid op: $1" >&2; return 2;;
    esac
}

_ws__validate () {
    local index linkptr wsdir=$(_ws__getdir "$_ws_current")
    linkptr=$(_ws__getlink)
    if [ ${#_ws_stack[*]} -ne $_ws_stkpos ]; then
        _ws_stkpos=$index
    fi
    if [ ! -d "$linkptr" ]; then
        echo "Error: $HOME/workspace pointing nowhere; removing" >&2
        rm -f $HOME/workspace
    fi
    if [ x${_ws_current:+X} = xX -a ! -d "$wsdir" ]; then
        echo "Error: $_ws_current is not a valid workspace; leaving" >&2
        _ws__leave
    fi
}

_ws__getdir () {
    # print the workspace directory for a name, return 1 if it does not exist
    local wsdir="$_ws_rootdir/${1:-$_ws_current}"
    if [ -d "$wsdir" ]; then
        echo "$wsdir"
    else
        return 1
    fi
}

_ws__getlink () {
    # print the referent or return 1 if exists and is not a symlink
    if [ -h $HOME/workspace ]; then
        readlink $HOME/workspace
    else
        return 1
    fi
}

_ws__resetlink () {
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

_ws__generate_config () {
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

_ws__config () {
    # run $HOME/.ws.sh script, passing either "enter" or "leave"
    # run $WORKSPACE/.ws.sh script, passing either "enter" or "leave"
    # calls to .ws.sh are NOT sandboxed as they should affect the environment
    # the 'leave' should try to put back anything that was change by 'enter'
    if [ x${_ws_current:+X} = xX ]; then
        local op="${1:-enter}"
        local wsdir=$(_ws__getdir)
        if [ -f "$HOME/.ws.sh" ]; then
            source "$HOME/.ws.sh" "$op"
        fi
        if [ -f "$wsdir/.ws.sh" ]; then
            source "$wsdir/.ws.sh" "$op"
        fi
    fi
}

_ws__enter () {
    # enter the workspace, setting the environment variables and chdir
    # if link=true, then update ~/workspace
    local wsname=${1:-""}
    local wsdir="$_ws_rootdir/$wsname"
    if [ -z "$wsname" ]; then
        if [ -n "$_ws_current" ]; then
            echo "$_ws_current"
            return 0
        fi
    elif [ ! -d "$wsdir" ]; then
        echo "No workspace exists for $wsname" >&2
        return 1
    else
        _ws__config leave
        if [ -n "$_ws_current" ]; then
            _ws__stack push "$_ws_current:$PWD"
        else
            _ws__stack push "$WORKSPACE:$PWD"
        fi
        _ws_current="$wsname"
        export WORKSPACE="$wsdir"
        cd "$wsdir"
        _ws__config enter
    fi
}

_ws__leave () {
    local wsname wsdir
    if [ x{$_ws_current:+X} != xX ]; then
        _ws__config leave
        local oldws=$(_ws__stack last)
        oldIFS="$IFS"
        IFS=":"
        set -- $oldws
        IFS="$oldIFS"
        case $1 in
            ""|/*) wsname=""; wsdir="$1";;
            *) wsname="$1"; wsdir=$(_ws__getdir "$wsname");;
        esac
        _ws_current="$wsname"
        _ws__stack pop
        if [ $? -eq 0 ]; then
            export WORKSPACE="$wsdir"
        fi
        cd "$2"  # return to old directory
        _ws__config enter
    fi
}

_ws__create () {
    local wsname=${1:-""}
    local wsdir="$_ws_rootdir/$wsname"
    if [ -z "$wsname" ]; then
        echo "No name given" >&2
        return 1
    elif [ -d "$wsdir" ]; then
        echo "Workspace already exists" >&2
        return 1
    else
        mkdir "$wsdir"
        _ws__generate_config "$wsdir"
    fi
}

_ws__destroy () {
    local wsname=${1:-""}
    local wsdir="$_ws_rootdir/$wsname"
    if [ -z "$wsname" ]; then
        echo "No name given" >&2
        return 1
    elif [ ! -d "$wsdir" ]; then
        echo "No workspace exists" >&2
        return 1
    else
        if [ "$wsname" = "$_ws_current" ]; then
            _ws__leave
        fi
        rm -rf "$wsdir"
        local linkptr=$(_ws__getlink)
        if [ "x$linkptr" = "x$wsdir" ]; then
            rm -f $HOME/workspace
            echo "~/workspace removed"
        fi
    fi
}

_ws__relink () {
    local wsname="${1:-$_ws_current}"
    if [ -z "$wsname" ]; then
        echo "No name given" >&2
        return 1
    else
        local wsdir="$(_ws__getdir $wsname)"
        _ws__resetlink "$wsdir"
    fi
}

_ws__list () {
    local link
    link=$(_ws__getlink)
    if [ $? -eq 1 ]; then
        sedscript=':noop'
    else
        sedscript="/$(basename $link)/s/\$/*/"
    fi
    ls -1 $_ws_rootdir | sed -e "$sedscript"
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
            _ws__enter "$2"
            ;;
        leave)
            _ws__leave
            ;;
        create)
            _ws__create "$2"
            _ws__enter "$2"
            ;;
        destroy)
            _ws__destroy "$2"
            ;;
        current)
            _ws__enter ""
            ;;
        relink)
            _ws__relink "$2"
            ;;
        list)
            _ws__list
            ;;
        state)
            echo "root=$_ws_rootdir" "ws='$_ws_current'"
            _ws__stack state
            _ws__list | tr '\n' ' '; echo
            ;;
        validate)
            _ws__validate
            ;;
        initialize)
            mkdir -p $_ws_rootdir
            # we don't want to delete it
            _ws__create default
            _ws__resetlink $(_ws__getdir default)
            _ws__generate_config "${HOME}"
            ;;
        *)
            _ws__enter "$1"
            ;;
    esac
}

if echo $- | fgrep -q i; then  # only for interactive
    _ws__complete () {
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
    complete -F _ws__complete ws
fi

