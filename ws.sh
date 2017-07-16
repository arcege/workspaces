#!/bin/bash
# Copyright @ 2017 Michael P. Reilly. All rights reserved.
# A shell program to handle workspaces in parallel with virtualenv.
# Environment variables are set to the desired workspace.

# process arguments and options
# operations
#   enter [name]                - set envvars and change to workspace directory, if no
#                                 name given, then show current workspace
#   leave                       - leave workspace, resetting envvars and directory
#   create <name> [<cfg*>]...   - create a new workspace
#   destroy <name>|-            - delete an existing workspace ('-' is alias for current workspace)
#   current                     - show the current workspace (same as enter operator with no name)
#   relink                      - (re)create ~/workspace symbolic link
#   list                        - show workspaces, '@' shows which is linked with
#                                 with ~/workspace, '*' shows the current workspace
#   stack                       - show workspaces on the stack, '*' shows current workspace
#   initialize                  - (re)create the environment
#   config <op> <wsname> ...    - modify config variables
#   help|-h|--help              - display help information
#   version                     - display version number
#   [name]                      - same as enter operator
#
# * cfg is either a filename containing variable assignments or variable assignments on the command-line
#   these are added to the .ws/config.sh script read during hooks
# 
# for example:
#    $ cat def.cfg
#    java_dir=/opt/jdk1.8.0_1
#    $ ws create myproduct Repos="MyApi MyCore MyUi" def.cfg
# getting:
#    $ cat ~/workspaces/myproduct/.ws/config.sh
#    : assignment used in .ws/hook.sh
#    # place variable names in _wshook__variables to be unset when hook completes
#    _wshook__variables="java_dir Repos"
#    Repos="MyApi MyCore MyUI"
#    java_dir="/opt/jdk1.8.0_1"
#
# if a workspace has a '.ws/hook.sh' script at the top, it will get source'd
# with the arguments 'enter', 'create', 'destroy', or 'leave' when those
# operations are performed this is useful for setting and unsetting
# environment variables or running commands specific to a workspace
#
# config structure
# workspaces/.ws/
#       config.sh  - file with shell variable assignments
#       hook.sh  - executed for each workspace by _ws_hook
#       skel.sh  - copied to workspace config directory as hook.sh
#    <wsname>/
#       .ws/
#           config.sh  - file with shell variable assignments
#           hook.sh  - executed by _ws_hook
# the config.sh is called on every operation, commands should not be executed
# variables should be assigned

_WS_SOURCE="${BASH_SOURCE[0]}"  # used by ws+reload later

case $BASH_VERSION in
    "")
        echo "This requires running in a bash shell. Exiting." >&2
        return 1
        ;;
esac

# global constants, per shell
# unfortunately, bash 3 (macos) does not support declaring global vars
WS_VERSION=0.2.2

: ${WS_DIR:=$HOME/workspaces}
: ${_WS_DEBUGFILE:=$WS_DIR/.log}

# _ws__current is a global variable, but initialized below
declare -a _ws__stack
declare -i WS_DEBUG

: ${WS_DEBUG:=0}

# if _ws__current variable exists (but may be null string), then assume
# the app has been initialized
if [ x${_ws__current:+X} != xX ]; then
    # if the stack is not empty, assume some things are already configured
    _ws__current=""
    _ws__stack=()
fi

_ws_debug () {
    case $1 in
        config)
            case $2 in
                "")
                    echo "lvl=$WS_DEBUG; file=$_WS_DEBUGFILE"
                    ;;
                reset)
                    WS_DEBUG=0
                    _WS_DEBUGFILE=${WS_DIR}/.log
                    ;;
                [0-9]*)
                    WS_DEBUG=$2
                    ;;
                *)
                    _WS_DEBUGFILE="$2"
                    ;;
            esac
            ;;
        [0-9]*)
            if [ "$1" -le "$WS_DEBUG" ]; then
                local proc func when lvl=$1
                shift
                proc="($$:$(tty))"
                when=$(date +%Y%m%d.%H%M%S)
                func="${FUNCNAME[1]}"  # The calling routine
                echo "${when}${proc}${func}[$lvl] $*" >> ${_WS_DEBUGFILE}
            fi
            ;;
        *)
            echo "Error: unknown argument: $1" >&2
            return 1
            ;;
    esac
}

# implement a stack
# * last - print the top item on the stack
# * push - add an item to the stack
# * pop - remove the top item off the stack
# * size - return how many items on the stack
# * state - print the top index and what is on the stack
_ws_stack () {
    _ws_debug 7 args "$@"
    local last pos=${#_ws__stack[*]}
    let last=pos-1
    case $1 in
        last)
            if [ $pos -gt 0 ]; then
                echo "${_ws__stack[$last]}"
            else
                _ws_debug 3 "empty stack"
                return 1
            fi
            ;;
        push)
            _ws_debug 4 "push \"$2\" to stack"
            _ws__stack[$pos]="$2"
            ;;
        pop)
            # should run __ws_stack last before running pop as we don't return it
            if [ $pos -gt 0 ]; then
                _ws_debug 4 "pop #$last from stack"
                unset _ws__stack[$last]
            else
                _ws_debug 3 "empty stack"
                return 1
            fi
            ;;
        size):
            echo $pos
            ;;
        state)
            echo "stack.size=$pos"
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
    _ws_debug 7 args "$@"
    local rc index linkptr wsdir=$(_ws_getdir)
    wsdir=$(_ws_getdir)
    if [ $? -eq 0 -a x${_ws__current:+X} = xX -a ! -d "$wsdir" ]; then
        _ws_debug 0 "leaving $_ws__current"
        echo "Error: $_ws__current is not a valid workspace; leaving" >&2
        _ws_leave
    fi
    if [ x${_ws__current:+X} = x -a $(_ws_stack size) -gt  0 ]; then
        case $PWD in
            $WS_DIR/*)
                local dir=${PWD##$WS_DIR/}
                _ws__current=${dir%/*}
                _ws_debug 1 "resetting workpace to $_ws__current"
                ;;
            *)
                echo "Error: cannot determine current workspace" >&2
                _ws_debug 0 "cannot determine current workspace"
                return 1
                ;;
        esac
    fi
    linkptr=$(_ws_link get)
    if [ $? -eq 0 -a ! -d "$linkptr" ]; then
        _ws_debug 0 "removing ~/workspace"
        echo "Error: $HOME/workspace pointing nowhere; removing" >&2
        _ws_link del
    fi
}

# print the workspace directory
# arguments:
#   workspace name, if not given use current workspace
# result code:
#   1 if no workspace name given and no current workspace
#   1 if if workspace does not exist
_ws_getdir () {
    _ws_debug 7 args "$@"
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
    _ws_debug 7 args "$@"
    local linkfile="$HOME/workspace"
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

# retrieve, remove or add/change variable in a config file
# arguments
#  file  - config.sh file
#   op  - one of get, del, list, set
#   var  - variable name
#   val  - value to assign
# return code
#   1  - if no config or no var in file (get)
_ws_config_edit () {
    _ws_debug 7 args "$@"
    local file=$1 op=$2 var=$3 val=$4
    if [ ! -f $file -a $op != set ]; then
        _ws_debug 3 "no config file $file"
        return 1
    fi
    case $op in
        get)
            val=$(sed -ne "s/^${var}=\"\([^\"]*\)\".*/\1/p" "$file")
            if [ -z "$val" ]; then
                _ws_debug 3 "no var $var in $file"
                return 1
            else
                echo "$val"
            fi
            ;;
        del)
            sed -i -e "/^${var}=/d" "$file"
            _ws_config_vars_edit "$file" remove "$var"
            ;;
        set)
            if [ ! -f "$file" ]; then
                _ws_generate_config "$file"
            fi
            if [ $? -ne 0 ]; then
                _ws_debug 1 "no $file"
                echo "Error: cannot create config file: $file" >&2
                return 1
            fi
            if grep -q "^${var}=" "$file"; then
                sed -i -e "/^${var}=/s/=.*/=\"${val}\"/" "$file"
            else
                echo "${var}=\"${val}\"" >> "$file"
            fi
            _ws_config_vars_edit "$file" add "$var"
            ;;
        list)
            if [ "x$var" = x-v -o "x$var" = x--verbose ]; then
                fgrep '=' "$file" | fgrep -v _wshook_
            else
                sed -ne '/_wshook_/d;/=.*/s///p' "$file"
            fi
            ;;
    esac
}

# add or remove variable names from _wshook__variables
# arguments
#   file  - config.sh file
#   op  - one of add or remove
#   var  - variable name
_ws_config_vars_edit () {
    local file="$1" op="$2" var="$3" sedscr
    if [ ! -f "$file" ]; then
        _ws_debug 2 "File missing: $file" >&2
        return 1
    fi
    case $op in
        add)
            sedscr="/^_wshook__variables=/{;/${var}/!s/\"$/ ${var}&/;}"
            ;;
        remove)
            sedscr="/^_wshook__variables=/s/ ${var}//"
            ;;
        *)
            _ws_debug 2 "Invalid op: $op" >&2
            return 1
            ;;
    esac
    sed -i -e "$sedscr" "$file"
}

# ws+config subcommand
_ws_config () {
    local wsdir op="$1" wsname="$2" var="$3" val="$4"
    case $op in
        help)
            echo "ws config op args ..."
            echo "  list <wsname>   - show variables in workspace's config"
            echo "  del <wsname> <var>  - remove variable from config"
            echo "  get <wsname> <var>  - return value of variable from config"
            echo "  set <wsname> <var> <val> - set value of variable in config"
            echo "wsname could be --global for the global configs"
            return 0
            ;;
        list) ;;
        del|get)
            if [ -z "$var" ]; then
                echo 'config: expecting variable name' >&2
                return 1
            fi
            ;;
        set)
            if [ -z "$var" ]; then
                echo 'config: expecting variable name' >&2
                return 1
            elif [ -z "$val" ]; then
                echo 'config: expecting value' >&2
                return 1
            fi
            ;;
        "")
            echo "config: expecting 'del', 'get', 'list' or 'set'" >&2
            return 1
            ;;
    esac
    if [ -z "$wsname" ]; then
        echo 'config: expecting workspace name' >&2
        return 1
    elif [ "x${wsname}" = x--global ]; then
        wsdir=$WS_DIR
    elif [ "x${wsname}" = x- ]; then
        wsdir="$(_ws_getdir $_ws__current)"
        if [ $? -ne 0 ]; then
            return 1
        fi
    else
        wsdir=$(_ws_getdir $wsname)
        if [ $? -ne 0 ]; then
            echo "config: No existing workspace" >&2
            return 1
        fi
    fi
    file=$wsdir/.ws/config.sh
    _ws_config_edit "$file" $op "$var" "$val"
}

# copy the skel hook script to the workspace
# arguments:
#   workspace directory
_ws_copy_skel () {
    _ws_debug 7 args "$@"
    if [ ! -d "$1/.ws" ]; then
        _ws_debug 3 "no $1/.ws directory"
    elif [ -f "$WS_DIR/.ws/skel.sh" ]; then
        cp -p "$WS_DIR/.ws/skel.sh" "$1/.ws/hook.sh"
        _ws_debug 3 "copy .skel.sh to $1"
    else
        _ws_debug 4 "no skel.sh to copy"
    fi
}

# create an "empty" config file
# arguments:
#  filename
_ws_generate_config () {
    local file="$1"
    _ws_debug 7 args "$@"
    if [ x${file:+X} = xX -a -d "${file%/*}" ]; then
        cat > "$file" <<EOF
: assignment used in .ws/hook.sh
# place variable names in _wshook__variables to be unset when hook completes
_wshook__variables=""
EOF
    fi
}

# create an "empty" hook script
# arguments:
#   filename
_ws_generate_hook () {
    _ws_debug 7 args "$@"
    # Create an empty hook script in the workspace
    if [ -n "$1" ]; then
        _ws_debug 3 "create %1"
        cat > "$1" <<'EOF'
:
# this is sourced by `ws` (workspaces)
# commands could be run and the environment/shell could be modified.
# anything set by the enter operation should be wound back by leave;
# similarly, anything set by create should be removed by destroy.
_wshook__op=${1:-enter}
_wshook__workspace=$2
_wshook__configdir=$(dirname ${BASH_SOURCE[0]})
_wshook__variables=""

# load config variables, if present
[ -s "$_wshook__configdir/config.sh" ] && . "$_wshook__configdir/config.sh"

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
# unset the variables registered
for name in ${_wshook__variables}; do
    unset -v $name
done
unset name
unset _wshook__op _wshook__workspace _wshook__configdir _wshook__variables
EOF
    chmod +x "$1"
    fi
}

_ws_hook () {
    local dir="$1" op="$2" wsdir="$3"
    if [ -x $dir/.ws/hook.sh ]; then
        source "$dir/.ws/hook.sh" "$op" "$wsdir"; rc=$?
        _ws_debug 2 "called $dir/.ws/hook.sh $op $wsdir; rc=$rc"
        return $rc
    elif [ -f "$dir/.ws.sh" ]; then
        source "$dir/.ws.sh" "$op" "$wsdir"; rc=$?
        _ws_debug 2 "called $dir/.ws.sh $op $wsdir; rc=$rc"
        return $rc
    fi
}

_ws_hooks () {
    _ws_debug 7 args "$@"
    # run $WS_DIR/.ws/hook.sh script, passing "create", "destroy", "enter" or "leave"
    # run $WORKSPACE/.ws/hook.sh script, passing the same
    # calls to hook.sh are NOT sandboxed as they should affect the environment
    # the 'leave' should try to put back anything that was changed by 'enter'
    # similarly, 'destroy' should put back anything changed by 'create'
    local wsdir rc op="${1:-enter}" context=$2
    case ${op}:${2:+X} in
        # if no context ($2==""), then just return
        enter:|leave:) return ;;
    esac
    wsdir=$(_ws_getdir "$context") \
        && _ws_hook $WS_DIR $op $wsdir \
        && _ws_hook $wsdir $op $wsdir
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
    _ws_debug 7 args "$@"
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
    _ws_debug 7 args "$@"
    local oldws=${_ws__current} context oldIFS wsname wsdir
    if [ "x${_ws__current:+X}" = xX ]; then
        _ws_hooks leave $_ws__current
        local notvalid=true
        while $notvalid; do
            context=$(_ws_stack last)
            if [ $? -ne 0 ]; then
                _ws_debug 3 "stack empty"
                break
            else
                _ws_debug 4 "context=X${context}X"
                oldIFS="$IFS"
                IFS=":"
                set -- $context
                IFS="$oldIFS"
                case $1 in
                    ""|/*) wsname=""; wsdir="$1";;
                    *) wsname="$1"; wsdir="$(_ws_getdir "$wsname")";;
                esac
                if [ -d "$wsdir" ]; then
                    _ws_debug 2 "leaving $oldws ${wsname:+to $wsname}"
                    notvalid=false
                else
                    _ws_debug 1 "$context ignored, pop stack again"
                fi
                _ws_stack pop
            fi
        done
        if [ $notvalid = false ]; then
            _ws__current="$wsname"
            export WORKSPACE="$wsdir"
            _ws_debug 2 "WORKSPACE=$wsdir _ws__current="$wsname""
        else
            _ws_debug 2 "WORKSPACE= _ws__current="
            unset WORKSPACE
            _ws__current=""
        fi
        if [ -n "$2" -a -d "$2" ]; then
            cd "$2"  # return to old directory
        fi
        if [ -n "$_ws__current" ]; then
            _ws_hooks enter $_ws__current
        fi
        _ws_debug 2 "left $oldws"
    fi
}

# create a new workspace, entering workspace
# copy the skel hook, create config.sh and run 'create' hooks
# a "cfg" is either a filename with variable assignments
# or assignment strings from the command-line
# these are added to {wsdir}/.ws/config.sh to be
# loaded on calls to {wsdir}/.ws/hooks.sh
# arguments:
#  workspace name
#  cfg ... (optional)
# result code:
#   1 if no workspace name given, or
#     if workspace already exists
_ws_create () {
    _ws_debug 7 args "$@"
    local wsdir wsname=${1:-""} configfile=${2:-""}
    wsdir="$(_ws_getdir "$wsname")"
    if [ -z "$wsname" ]; then
        echo "No name given" >&2
        _ws_debug 2 "no name"
        return 1
    else
        mkdir "$wsdir"
        if [ $? -eq 0 ]; then
            shift  # pop wsname from the arg list
            local i tmpfile="${TMPDIR:-/tmp}/ws.cfg.$$.${wsname}"
            local sedscr1 sedscr2
            sedscr1='s/\t/ /g;s/^ *//;s/ *$//;/_WS_/d;/_ws_/d;/_wshook_/d;/^[^= ]*=/p'
            sedscr2="/=\"/{;s//=/;s/\".*//;b;};/='/{;s//=/;s/'.*//;b;};s/\(=[^ ]*\).*/\1/"
            # process the config (files or assignments) passed on the command-line
            for i in "$@"; do
                case $i in
                    *=*) echo "$i" | sed -ne "$sedscr1" >> $tmpfile;;
                    *) sed -ne "$sedscr1" $i | sed -e "$sedscr2" >> $tmpfile;;
                esac
            done
            mkdir -p "$wsdir/.ws"
            _ws_copy_skel "$wsdir"
            _ws_generate_config "$wsdir/.sh/config.sh"
            # add assignments from cli
            if [ -s "$tmpfile" ]; then
                # split the incoming file ($tmpfile) by '='
                local lhs rhs oldIFS="$IFS"; IFS=$'='
                while read lhs rhs; do
                    _ws_config_edit $wsdir/.ws/config.sh set "$lhs" "$rhs"
                done < $tmpfile
                IFS="$oldIFS"
                _ws_debug 0 "Applied vars to $wsdir/.ws/config.sh"
            fi
            _ws_hooks create $wsname
            _ws_debug 1 "$wsdir created"
            rm -f $tmpfile
        elif [ -d "$wsdir" ]; then
            echo "Workspace already exists" >&2
            _ws_debug 2 "workspace exists"
            return 1
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
    _ws_debug 7 args "$@"
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
    _ws_debug 7 args "$@"
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
    _ws_debug 7 args "$@"
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
    _ws_debug 7 args "$@"
    if [ x${_ws__current:+X} = xX ]; then
        local context oldIFS i=$(_ws_stack size)
        echo "${_ws__current}*"
        while [ $i -gt 0 ]; do
            let i--
            context=${_ws__stack[$i]}
            oldIFS="$IFS"; IFS=":"
            set -- ${context}
            IFS="$oldIFS"
            case $1 in
                ""|/*) echo "($2)";;
                *) echo $1;;
            esac
        done
    else
        echo "($PWD)"
    fi
}

_ws_help () {
    _ws_debug 7 args "$@"
    \cat <<'EOF'
ws [<cmd>] [<name>]
  enter [<name>]             - show the current workspace or enter one
  leave                      - leave current workspace
  create <name> [<cfg*>]...  - create a new workspace
  destroy name|-             - destroy a workspace ('-' alias for current)
  current                    - show current workspace (same as 'ws enter')
  relink [<name>]            - reset ~/workspace symlink
  list                       - show available workspaces
  stack                      - show workspaces on the stack
  initialize                 - create the workspaces structure
  config <op> <wsname> ...   - modify config variables
  help|-h|--help             - this message
  version                    - display version number
  [<name>]                   - same as 'ws enter [<name>]'
* <cfg> is either a filename ('=' not allowed) with configuration assignments
  or variable assignments in the form VAR=VALUE
  these are added to the config.sh file before the 'create' hook is called.
EOF
}

ws () {
    _ws_debug 7 args "$@"
    if [ "x$1" = x--help -o "x$1" = x-h ]; then
        set -- help
    fi
    cmd="$1"
    shift
    case $cmd in
        help)
            _ws_help
            ;;
        enter)
            _ws_enter "$1"
            ;;
        leave)
            _ws_leave
            ;;
        create)
            # create can take an optional filename of the
            # configuration files
            # pop off the command from the arg list
            # the now first argument is the name
            # the rest are cfg files or variable assignments
            _ws_create "$@"
            _ws_enter "$1"
            ;;
        destroy)
            local wsname
            # allow "-" to be used as an alias for the current workspace
            # but it must be explicitly entered, not in bash completion
            if [ "x$1" = x- ]; then
                wsname=$_ws__current
            else
                wsname=$1
            fi
            _ws_destroy "$wsname"
            ;;
        current)
            _ws_enter ""
            ;;
        relink)
            _ws_relink "$1"
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
        config)
            _ws_config "$@"
            ;;
        state)
            echo "root=$WS_DIR" "ws='$_ws__current'"
            _ws_stack state
            _ws_list | tr '\n' ' '; echo
            ;;
        reload)
            local wsfile
            if [ -n "$1" -a -f "$1" ]; then
                wsfile="$1"
            else
                wsfile=${_WS_SOURCE:-${HOME}/.bash/ws.sh}
            fi
            _ws_debug 1 "loading $wsfile"
            source "$wsfile"
            ;;
        validate)
            _ws_validate
            ;;
        debug)
            _ws_debug config "$1"
            ;;
        initialize)
            mkdir -p $WS_DIR/.ws
            _ws_generate_hook "${WS_DIR}/.ws/hook.sh"
            _ws_generate_hook "${WS_DIR}/.ws/skel.sh"
            _ws_generate_config "${WS_DIR}/.ws/config.sh"
            # we don't want to delete it
            _ws_create default
            _ws_link set $(_ws_getdir default)
            ;;
        *)
            _ws_enter "$cmd"
            ;;
    esac
}

if echo $- | fgrep -q i; then  # only for interactive
    _ws_complete () {
        # handle bash completion
        local cur curop prev options commands names
        COMPREPLY=()
        cur="${COMP_WORDS[COMP_CWORD]}"
        if [ $COMP_CWORD -gt 1 ]; then
            curop="${COMP_WORDS[1]}"
        else
            curop=""
        fi
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        options="-h --help"
        operators="config create current destroy enter help initialize leave list relink stack version"
        names=$(ws list | tr -d '*@' | tr '\n' ' ')
        if [ $COMP_CWORD -eq 1 ]; then
            COMPREPLY=( $(compgen -W "$operators $options $names" -- ${cur}) )
            return 0
        elif [ $COMP_CWORD -eq 2 ]; then
            case $curop in
                enter|destroy|relink)
                    COMPREPLY=($(compgen -W "$names" -- $cur))
                    return 0
                    ;;
                debug)
                    COMPREPLY=( $(compgen -W "reset 0 1 2 3 4 5 6 7 8 9" -f -- ${cur}) )
                    return 0
                    ;;
                config)
                    COMPREPLY=( $(compgen -W "del get help list set" -- ${cur}) )
                    return 0
                    ;;
            esac
        elif [ $COMP_CWORD -ge 3 -a ${curop} = create ]; then
            COMPREPLY=( $(compgen -f -v -- ${cur}) )
            return 0
        elif [ $COMP_CWORD -eq 3 -a ${curop} = config ]; then
            # "-" is the same as the current workspace
            COMPREPLY=( $(compgen -W "- --global $names" -- $cur) )
            return 0
        elif [ $COMP_CWORD -eq 4 -a ${curop} = config ]; then
            case ${COMP_WORDS[2]} in
                del|get|set)
                    COMPREPLY=( $(compgen -W "$(ws config list ${COMP_WORDS[3]})" -- ${cur}) )
                    return 0
                    ;;
                list)
                    COMPREPLY=( $(compgen -W "-v --verbose" -- ${cur}) )
                    return 0
                    ;;
            esac
        fi
    }

    # activate bash completion
    complete -F _ws_complete ws
fi

