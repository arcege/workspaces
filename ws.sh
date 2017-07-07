#!/bin/bash
# Copyright @ 2017 Michael P. Reilly. All rights reserved.
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
#   list            - show workspaces, '@' shows which is linked with
#                     with ~/workspace, '*' shows the current workspace
#   stack           - show workspaces on the stack, '*' shows current workspace
#   initialize      - (re)create the environment
#   help|-h|--help  - display help information
#   version         - display version number
#   [name]          - same as enter operator
#
# if a workspace has a '.ws.sh' script at the top, it will get source'd with
# the arguments 'enter' or 'leave' when thoe operations are performed
# this is useful for setting and unsetting environment variables or running
# commands specific to a workspace

_WS_SOURCE="${BASH_SOURCE[0]}"  # used by ws+reload later

case $BASH_VERSION in
    "")
        echo "This requires running in a bash shell. Exiting." >&2
        return 1
        ;;
esac

# global constants, per shell
# unfortunately, bash 3 (macos) does not support declaring global vars
WS_VERSION=0.1.7

: ${WS_DIR:=$HOME/workspaces}
: ${WS_DEBUG:=0}
: ${_WS_DEBUGFILE:=$WS_DIR/.log}

# _ws__current is a global variable, but initialized below
declare -a _ws__stack
declare -i _ws__stkpos
declare -i WS_DEBUG

# if _ws__current variable exists (but may be null string), then assume
# the app has been initialized
if [ x${_ws__current:+X} != xX ]; then
    # if the stack is not empty, assume some things are already configured
    _ws__current=""
    _ws__stack=()
    _ws__stkpos=0
fi

_ws_debug () {
    local proc func when lvl=$1
    shift
    proc="$$($(tty))"
    when=$(date +%Y%m%d.%H%M%S)
    func="${FUNCNAME[1]}"  # The calling routine
    if [ "$lvl" -le "$WS_DEBUG" ]; then
        echo "${proc}:${func}[$lvl]${when} $*" >> ${_WS_DEBUGFILE}
    fi
}

# implement a stack
# * last - print the top item on the stack
# * push - add an item to the stack
# * pop - remove the top item off the stack
# * size - return how many items on the stack
# * state - print the top index and what is on the stack
_ws_stack () {
    case $1 in
        last)
            if [ $_ws__stkpos -gt 0 ]; then
                echo "${_ws__stack[$_ws__stkpos]}"
            else
                _ws_debug 3 "empty stack"
                return 1
            fi
            ;;
        push)
            let _ws__stkpos++
            _ws_debug 4 "push \"$2\" to stack"
            _ws__stack[$_ws__stkpos]="$2"
            ;;
        pop)
            # should run __ws_stack last before running pop as we don't return it
            if [ $_ws__stkpos -gt 0 ]; then
                _ws_debug 4 "pop #$_ws__stkpos from stack"
                unset _ws__stack[$_ws__stkpos]
                let _ws__stkpos--
            else
                _ws_debug 3 "empty stack"
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

# check if the application is set up properly
# * verify the stack is correct
# * verify that ~/workspace points to a directory, if not remove it
# * verify that the current workspace exists, if not leave it
_ws_validate () {
    local index linkptr wsdir=$(_ws_getdir "$_ws__current")
    linkptr=$(_ws_link get)
    if [ ${#_ws__stack[*]} -ne $_ws__stkpos ]; then
        _ws_debug 0 "fixing stack index"
        _ws__stkpos=$index
    fi
    if [ ! -d "$linkptr" ]; then
        _ws_debug 0 "removing ~/workspace"
        echo "Error: $HOME/workspace pointing nowhere; removing" >&2
        _ws_link
    fi
    if [ x${_ws__current:+X} = xX -a ! -d "$wsdir" ]; then
        _ws_debug 0 "leaving $_ws__current"
        echo "Error: $_ws__current is not a valid workspace; leaving" >&2
        _ws_leave
    fi
}

# print the workspace directory
# arguments:
#   workspace name, if not given use current workspace
# result code:
#   1 if no workspace name given and no current workspace
#   1 if if workspace does not exist
_ws_getdir () {
    # print the workspace directory for a name, return 1 if it does not exist
    local wsname=${1:-$_ws__current}
    if [ -z "$wsname" ]; then
        _ws_debug 2 "no workspace"
        return 1
    fi
    local wsdir="$WS_DIR/${1:-$_ws__current}"
    echo "$wsdir"
    if [ ! -d "$wsdir" ]; then
        _ws_debug 2 "workspace does not exist"
        return 1
    fi
}


# manage the ~/workspace symbolic link
# operations include:
# -  get  - return the referant (readline)
# -  set  - replace the symlink
# -  del  - delete the symlink
_ws_link () {
    local linkfile="$HOME/workspace"
    _ws_debug 0 link "X${1}X" "Y${2}Y"
    case $1 in
        get)
            if [ -h ${linkfile} ]; then
                readlink ${linkfile}
            else
                _ws_debug 3 "no link"
                return 1
            fi
            ;;
        set)
            if [ -z "$2" -o ! -d "$2" ]; then
                echo "Error: invalid workspace" >&2
                _ws_debug 2 "workspace does not exist"
                return 1
            elif [ ! -e ${linkfile} -o -h ${linkfile} ]; then
                rm -f ${linkfile}
                ln -s "$2" ${linkfile}
                _ws_debug 2 "$2"
            elif [ -e ${linkfile} ]; then
                echo "Error: ~/workspace is not a symlink" >&2
                _ws_debug 1 "~/workspace is not a symlink"
                return 1;
            fi
            ;;
        del)
            if [ -h ${linkfile} ]; then
                rm -f ${linkfile}
            elif [ -e ${linkfile} ]; then
                echo "Error: ~/workspace is not a symlink" >&2
                _ws_debug 1 "~/workspace is not a symlink"
                return 1
            fi
            ;;
    esac
}

# copy the skel hook script to the workspace
# arguments:
#   workspace directory
_ws_copy_skel () {
    if [ -f "$WS_DIR/.skel.sh" ]; then
        cp -p "$WS_DIR/.skel.sh" "$1/.ws.sh"
        _ws_debug 3 "copy .skel.sh to $1"
    else
        _ws_debug 4 "no .skel.sh to copy"
    fi
}

# create an "empty" hook script
# arguments:
#   filename
_ws_generate_hook () {
    # Create an empty hook script in the workspace
    if [ -n "$1" ]; then
        _ws_debug 3 "create %1"
        cat <<'EOF' > "$1"
:
# this is sourced by `ws` (workspaces)
# commands could be run and the environment/shell could be modified.
# anything set by the enter operation should be wound back by leave;
# similarly, anything set by create should be removed by destroy.
_wshook__op=${1:-enter}
_wshook__workspace=$2

# any variables you use here should be unset at the end; local
# would not work as this is source'd
case ${_wshook__op} in
    # the current context is NOT this workspace
    create)
        ;;

    # the current context is NOT this workspace
    destroy)
        ;;

    # the current context IS this workspace
    enter)
        ;;

    # the current context IS this workspace
    leave)
        ;;
esac
unset _wshook__op _wshook__workspace
EOF
    fi
}

_ws_hooks () {
    # run $HOME/.ws.sh script, passing "create", "destroy", "enter" or "leave"
    # run $WORKSPACE/.ws.sh script, passing either "enter" or "leave"
    # calls to .ws.sh are NOT sandboxed as they should affect the environment
    # the 'leave' should try to put back anything that was change by 'enter'
    local wsdir rc op="${1:-enter}" context=$2
    case ${op}:${2:+X} in
        # if no workspace, then just return
        enter:|leave:) return ;;
    esac
    wsdir=$(_ws_getdir "$context")
    rc=$?
    if [ -f "$WS_DIR/.ws.sh" ]; then
        source "$WS_DIR/.ws.sh" "$op" "$wsdir"
        _ws_debug 2 "called $WS_DIR/.ws.sh $op $wsdir; rc=$?"
    fi
    if [ $rc -eq 0 -a -f "$wsdir/.ws.sh" ]; then
        source "$wsdir/.ws.sh" "$op" "$wsdir"
        _ws_debug 2 "called $wsdir/.sh.sh $op $wsdir; rc=$?"
    fi
}

# enter a workspace, or show the current
# the WORKSPACE envvar is set to the workspace
# directory and change to that directory
# the current working directory and the workspace
# are pushed onto a stack
# arguments:
#   workspace name (optional)
# return code:
#   1 if workspace directory does not exist
_ws_enter () {
    local wsdir wsname=${1:-""}
    wsdir="$(_ws_getdir "$wsname")"
    if [ -z "$wsname" ]; then
        if [ -n "$_ws__current" ]; then
            echo "$_ws__current"
            return 0
        fi
    elif [ ! -d "$wsdir" ]; then
        echo "No workspace exists for $wsname" >&2
        _ws_debug 1 "no workspace for $wsname"
        return 1
    else
        _ws_hooks leave $_ws__current
        if [ -n "$_ws__current" ]; then
            _ws_stack push "$_ws__current:$PWD"
        else
            _ws_stack push "$WORKSPACE:$PWD"
        fi
        _ws__current="$wsname"
        export WORKSPACE="$wsdir"
        cd "$wsdir"
        _ws_hooks enter $_ws__current
        _ws_debug 2 "entered $wsname $wsdir"
    fi
}

# leave a workspace, popping the previous context
# off the stack, changing to the old working directory
# and if present, reentering the old workspace
# arguments: none
# result code: 0
_ws_leave () {
    local oldws context oldIFS wsname wsdir
    if [ x{$_ws__current:+X} != xX ]; then
        _ws_hooks leave $_ws__current
        context=$(_ws_stack last)
        oldIFS="$IFS"
        IFS=":"
        set -- $context
        IFS="$oldIFS"
        case $1 in
            ""|/*) wsname=""; wsdir="$1";;
            *) wsname="$1"; wsdir=$(_ws_getdir "$wsname");;
        esac
        oldws="$_ws__current"
        _ws__current="$wsname"
        _ws_debug 2 "leaving $wsname"
        _ws_stack pop
        if [ $? -eq 0 ]; then
            export WORKSPACE="$wsdir"
            _ws_debug 2 "WORKSPACE=$wsdir"
        fi
        cd "$2"  # return to old directory
        _ws_hooks enter $_ws__current
        _ws_debug 2 "left $oldws"
    fi
}

# create a new workspace, entering workspace
# copy the skel hook, run 'create' hooks
# arguments:
#  workspace name
# result code:
#   1 if no workspace name given, or
#     if workspace already exists
_ws_create () {
    local wsdir wsname=${1:-""}
    wsdir="$(_ws_getdir "$wsname")"
    if [ -z "$wsname" ]; then
        echo "No name given" >&2
        _ws_debug 2 "no name"
        return 1
    elif [ -d "$wsdir" ]; then
        echo "Workspace already exists" >&2
        _ws_debug 2 "workspace exists"
        return 1
    else
        mkdir "$wsdir"
        if [ $? -eq 0 ]; then
            _ws_copy_skel "$wsdir"
            _ws_hooks create $wsname
            _ws_debug 1 "$wsdir created"
        else
            _ws_debug 0 "$wsdir exists, but not directory"
            echo "$wsdir is exists but not a directory" >&2
            return 1
        fi
    fi
}

# destroy an existing workspace, leaving workspace if current,
# deleting ~/workspace link if pointing to the workspace
# arguments:
#   workspace name
# result code:
#   1 if no workspace name given, or
#     if no workspace directory exists
_ws_destroy () {
    local linkptr wsdir wsname=${1:-""}
    wsdir="$(_ws_getdir "$wsname")"
    if [ -z "$wsname" ]; then
        echo "No name given" >&2
        return 1
    elif [ ! -d "$wsdir" ]; then
        _ws_debug 2 "workspace does not exit"
        echo "No workspace exists" >&2
        return 1
    else
        if [ "$wsname" = "$_ws__current" ]; then
            _ws_leave
        fi
        _ws_hooks destroy $wsname
        rm -rf "$wsdir"
        linkptr=$(_ws_link get)
        if [ $? -eq 0 -a "x$linkptr" = "x$wsdir" ]; then
            _ws_debug 1 "~/workspace removed"
            _ws_link del
        fi
        _ws_debug 2 "destroyed $wsname"
    fi
}

# update the ~/workspace symlink to a workspace directory
# arguments:
#  workspace name - if not given, use the current workspace
# result code:
#   1 if no workspace given and no current workspace, or
#     if no workspace directory exists
_ws_relink () {
    local wsdir wsname="${1:-$_ws__current}"
    if [ -z "$wsname" ]; then
        echo "No name given" >&2
        _ws_debug 2 "no workspace"
        return 1
    else
        wsdir="$(_ws_getdir $wsname)"
        if [ $? -eq 0 ]; then
            _ws_link set "$wsdir"
        else
            echo "No workspace exists" >&2
            _ws_debug 1 "no workspace exists"
            return 1
        fi
    fi
}

# display to stdout the list of workspaces
# the one that ~/workspace points to is marked with '@'
# the current workspace is marked with '*'
# arguments: none
# result code:
#   1 if WS_DIR does not exist
_ws_list () {
    local link sedscript
    sedscript=""
    link=$(_ws_link get)
    if [ $? -eq 0 ]; then
        sedscript="${sedscript};/^$(basename $link)\$/s/\$/@/"
    fi
    if [ x${_ws__current:+X} = xX ]; then
        sedscript="${sedscript};/^${_ws__current}@\{0,1\}\$/s/\$/*/"
    fi
    if [ ! -d $WS_DIR ]; then
        echo "Fatal: no such directory: $WS_DIR" >&2
        return 1
    fi
    ls -1 $WS_DIR | sed -e "$sedscript"
}

# display to stdout the list of workspaces on the stack
# including the current workspace
# arguments: none
# result code: none
_ws_show_stack () {
    local context oldIFS i=${_ws__stkpos}
    if [ x${_ws__current:+X} = xX ]; then
        echo "${_ws__current}*"
        while [ $i -gt 0 ]; do
            context=${_ws__stack[$i]}
            oldIFS="$IFS"
            IFS=":"
            set -- ${context}
            IFS="$oldIFS"
            case $1 in
                ""|/*) echo "($2)";;
                *) echo $1;;
            esac
            let i--
        done
    fi
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
  current                    - show current workspace (same as 'ws enter')
  relink [<name>]            - reset ~/workspace symlink
  list                       - show available workspaces
  stack                      - show workspaces on the stack
  initialize                 - create the workspaces structure
  help|-h|--help             - this message
  version                    - display version number
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
        stack)
            _ws_show_stack
            ;;
        version)
            echo "$WS_VERSION"
            ;;
        state)
            echo "root=$WS_DIR" "ws='$_ws__current'"
            _ws_stack state
            _ws_list | tr '\n' ' '; echo
            ;;
        reload)
            source ${_WS_SOURCE:-${HOME}/.bash/ws.sh}
            ;;
        validate)
            _ws_validate
            ;;
        initialize)
            mkdir -p $WS_DIR
            _ws_generate_hook "${WS_DIR}/.ws.sh"
            _ws_generate_hook "${WS_DIR}/.skel.sh"
            # we don't want to delete it
            _ws_create default
            _ws_link set $(_ws_getdir default)
            ;;
        *)
            _ws_enter "$1"
            ;;
    esac
}

if echo $- | fgrep -q i; then  # only for interactive
    _ws_complete () {
        # handle bash completion
        local cur prev options commands names
        COMPREPLY=()
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        options="-h --help"
        commands="create current destroy enter help initialize leave list relink stack version"
        names=$(ws list | tr -d '*@' | tr '\n' ' ')
        if [ $COMP_CWORD -eq 1 ] || [[ "${prev:0:1}" == "-" ]]; then
            COMPREPLY=( $(compgen -W "$commands $options $names" -- ${cur}) )
            return 0
        else
            case $prev in
                enter|destroy)
                    COMPREPLY=($(compgen -W "$names" -- $cur))
                    return 0
                    ;;
            esac
        fi
    }

    # activate bash completion
    complete -F _ws_complete ws
fi

