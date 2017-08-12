#!/bin/bash
# Copyright @ 2017 Michael P. Reilly. All rights reserved.
# A shell program to handle workspaces in parallel with virtualenv.
# Environment variables are set to the desired workspace.

# process arguments and options
# operations
#   enter [name]                - set envvars and change to workspace directory, if no
#                                 name given, then show current workspace
#   leave                       - leave workspace, resetting envvars and directory
#   create [-p <plugin>...] <name> [<cfg*>]...
#                               - create a new workspace
#   destroy <name>|-            - delete an existing workspace ('-' is alias for current workspace)
#   current                     - show the current workspace (same as enter command with no name)
#   relink                      - (re)create ~/workspace symbolic link
#   list                        - show workspaces, '@' shows which is linked with
#                                 with ~/workspace, '*' shows the current workspace
#   stack                       - show workspaces on the stack, '*' shows current workspace
#   initialize[{wsdir}]         - (re)create the environment
#   config <op> <wsname> ...    - modify config variables
#   plugin <op> ...             - manage plugins
#   help|-h|--help              - display help information
#   version                     - display version number
#   [name]                      - same as enter command
#
# * cfg is either a filename containing variable assignments or variable assignments on the command-line
#   these are added to the .ws/config.sh script read during hooks
# 
# for example:
#    $ cat def.cfg
#    java_dir=/opt/jdk1.8.0_1
#    $ ws create -p github myproduct github_repos="MyApi MyCore MyUi" def.cfg
# getting:
#    $ cat ~/workspaces/myproduct/.ws/config.sh
#    : assignment used in .ws/hook.sh
#    github_repos="MyApi MyCore MyUI"
#    java_dir="/opt/jdk1.8.0_1"
#    $ ls ~/workspaces/myproduct/.ws/plugins
#    github
#
# if a workspace has a '.ws/hook.sh' script at the top, it will get source'd
# with the arguments 'enter', 'create', 'destroy', or 'leave' when those
# operations are performed this is useful for setting and unsetting
# environment variables or running commands specific to a workspace
# plugins added to a workspace will be called in the same fashion and
# context as the hook scripts, immediately after.  Plugins installed
#
# config structure
# workspaces/.ws/
#       config.sh  - file with shell variable assignments
#       hook.sh    - executed for each workspace by _ws_run_hooks
#       plugins/   - directory containing available plugin hook scripts
#       skel.sh    - copied to workspace config directory as hook.sh
#    <wsname>/
#       .ws/
#           config.sh  - file with shell variable assignments
#           hook.sh  - executed by _ws_run_hooks
#           plugins/   - directory containing symlinks to active plugin hooks
#
# the config.sh is called on every operation, commands should not be executed
# variables should be assigned

_ws_dir="$(cd $(dirname ${BASH_SOURCE[0]}); pwd)"
_WS_SOURCE="$_ws_dir/${BASH_SOURCE[0]##*/}"  # used by ws+reload later
unset _ws_dir

case $BASH_VERSION in
    "")
        echo "This requires running in a bash shell. Exiting." >&2
        return 1
        ;;
esac

# global constants, per shell
# unfortunately, bash 3 (macos) does not support declaring global vars
WS_VERSION=0.2.7

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
                if [ "x${_WS_DEBUGFILE}" = x- ]; then # stdout
                    echo "${when}${proc}${func}[$lvl] $*"
                else
                    echo "${when}${proc}${func}[$lvl] $*" >> ${_WS_DEBUGFILE}
                fi
            fi
            ;;
        *)
            echo "Error: unknown argument: $1" >&2
            return 1
            ;;
    esac
}

_ws_upgrade_warning () {
    if [ x$_ws__seen_upgrade_warning != xtrue ]; then
        \cat <<'EOF' >&2
It appears that the install program did not run. While hooks will still be
called for backward compatibility, some aspects (e.g. config mgmt) may not
work properly.
Please run ./install.sh from the distribution which will upgrade the
data structures for the new release of workspaces.
EOF
        _ws__seen_upgrade_warning=true
    fi
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
    # there are conditions where the items in the stack seem to become missing
    # blank points to the last blank item
    local blank size=${#_ws__stack[*]} startmoving=false
    for (( index = 0; index <= size; index++ )); do
        if $startmoving; then
            ${_ws__stack[$blank]}=${_ws__stack[$index]}
            ${_ws__stack[$index}=""
            blank=$index
        elif [ -z "${_ws__stack[$index]} " ]; then
            startmoving=true
            blank=$index
        fi
    done
    if [ x${_ws__current:+X} = x -a $(_ws_stack size) -gt 0 ]; then
        _ws_debug 0 "Current workspace lost; leaving to last workspace."
        _ws__current=ws-noworkspace-ws  # a sentinal
        _ws_leave
    elif [ x${_ws__current:+X} = x ]; then
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
    if [ ! -d ${file%/*} ]; then
        _ws_debug 2 "Workspaces need upgrade; $file"
        _ws_upgrade_warning
        return 1
    elif [ ! -f $file -a $op != set ]; then
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

# ws+config subcommand
_ws_cmd_config () {
    _ws_debug 7 args "$@"
    local wsdir op="$1" wsname="$2" var="$3" val="$4"
    case $op in
        help)
            echo "ws config op args ..."
            echo "  list <wsname>       - show variables in workspace's config"
            echo "  del <wsname> <var>  - remove variable from config"
            echo "  get <wsname> <var>  - return value of variable from config"
            echo "  set <wsname> <var> <val> - set value of variable in config"
            echo "  search <re> ...     - search workspaces for variables"
            echo "wsname could be --global for the global configs"
            return 0
            ;;
        list)
            shift
            _ws_show_config_vars "$@"
            return 0
            ;;
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
        search)
            local text maxlen workspaces=$(_ws_cmd_list --workspace -q)
            maxlen=$(echo "$workspaces" | awk '{if (length>max) {max=length}} END{print max}')
            shift  # move over op
            for var in "$@"; do
                _ws_cmd_config list --global -q | grep -e "$var" | while read val; do
                    text=$(_ws_cmd_config get --global $val)
                    printf '%*s: '"$val=$text"'\n' $maxlen "--global"
                done
                for wsname in $(_ws_cmd_list -q); do
                    _ws_cmd_config list -w -q $wsname | grep -e "$var" | while read val; do
                        text=$(_ws_cmd_config get $wsname $val)
                        printf '%*s: '"$val=$text"'\n' $maxlen "$wsname"
                    done
                done
            done
            return 0
            ;;
        "")
            echo "config: expecting 'del', 'get', 'help', 'list' or 'set'" >&2
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

_ws_process_configvars () {
    # split the incoming file ($cfgfile) by '='
    local wsdir="$1" cfgfile="$2" lhs rhs oldIFS="$IFS" IFS=$'='
    while read lhs rhs; do
        _ws_config_edit "$wsdir/.ws/config.sh" set "$lhs" "$rhs"
    done < $cfgfile
    IFS="$oldIFS"
    _ws_debug 0 "Applied vars to $wsdir/.ws/config.sh"
}

_ws_parse_configvars () {
    local i cfgfile="$1"
    local sedscr1 sedscr2
    sedscr1='s/\\t/ /g;s/^ *//;s/ *$//;/_WS_/d;/_ws_/d;/_wshook_/d;/^[^= ]*=/p'
    sedscr2="/=\"/{;s//=/;s/\".*//;b;};/='/{;s//=/;s/'.*//;b;};s/\(=[^ ]*\).*/\1/"
    shift
    for i in "$@"; do
        case $i in
            *=*) echo "$i" | sed -ne "$sedscr1" >> $cfgfile;;
            *)
                sed -ne "$sedscr1" "$i" | sed -e "$sedscr2" >> $cfgfile;;
        esac
    done
}

_ws_show_config_vars () {
    local sdir wsdir sedscr wsname
    local wantgl=true wantws=true mode=normal modechr
    sedscr=';s/=.*//'
    while true; do
        case $1 in
            -) wsname=$_ws_current; break;;
            -h|--help) echo "ws config list [-q|-v] [-b|-q|-w] [wsname|-]"; return;;
            -g|--global) wantgl=true; wantws=false;;
            -b|--both) wantgl=true; wantws=true;;
            -w|--workspace) wantgl=false; wantws=true;;
            -q|--quiet) mode=quiet;;
            -v|--verbose) mode=verbose;;
            -*|--*) echo "Error: invalid option" >&2; return 1;;
            *) wsname=$1; break;;
        esac
        shift
    done
    if [ $mode = verbose ]; then
        sedscr=''
    fi
    wsdir=$(_ws_getdir ${wsname})
    (
        if [ $wantgl = true -a -f "$WS_DIR/.ws/config.sh" ]; then
            [ $mode = quiet ] && modechr='' || modechr='%'
            sed -ne "/^[A-Za-z0-9_]*=/{${sedscr};s/^/${modechr}/;p}" "$WS_DIR/.ws/config.sh"
        fi
        if [ $wantws = true -a -n "$wsdir" -a -f "$wsdir/.ws/config.sh" ]; then
            [ $mode = quiet ] && modechr='' || modechr='*'
            sed -ne "/^[A-Za-z0-9_]*=/{${sedscr};s/^/${modechr}/;p}" "$wsdir/.ws/config.sh"
        fi
    ) | sort
}

_ws_show_plugin_vars () {
    local file name quiet=0
    if [ $# -gt 0 -a "x$1" = x-q ]; then
        quiet=1
    fi
    local awkscr='BEGIN{i=0; max=0; '"quiet=$quiet"'}
    /# uses /{sub(/^# uses /, ""); f[i] = FILENAME; l=length(FILENAME); if (l > max) {max=l}; e[i] = $0; i++}
    END {for (c=0;c<i;c++) {if (quiet) {sub(/ .*/, "", e[c]); print e[c]} else {printf("%*s: %s\n", max, f[c], e[c])}}}'
    if [ -d "$WS_DIR/.ws/plugins" ]; then
        (cd $WS_DIR/.ws/plugins; awk "$awkscr" *)
    fi
    return 0
}


_ws_cmd_plugin () {
    _ws_debug 7 args "$@"
    local wsdir op="$1" wsname="$2"
    local plugin plugindir=$WS_DIR/.ws/plugins
    shift
    case $op in
        help)
            echo "ws plugin op args ..."
            echo "  available                        - show installed plugins"
            echo "  install [-f] [-n <name>] <file>  - install plugin"
            echo "  uninstall <name>                 - uninstall plugin"
            echo "  list <wsname>|--all              - list plugins added to workpace hooks"
            echo "  add <wsname> <plugin> ...        - add plugin to workspace hooks"
            echo "  remove <wsname> <plugin> ...     - remove plugin from workspace hooks"
            echo "  show [-q]                        - show config vars in available plugins"
            return 0
            ;;
        available)
            if [ -d $plugindir ]; then
                for plugin in $plugindir/*; do
                    if [ "$plugin" = "$plugindir/*" ]; then
                        break
                    fi
                    echo ${plugin##$plugindir/}
                done
            fi
            return 0
            ;;
        install)
            local name="" file="" force=false
            while [ $# -gt 0 ]; do
                case $1 in
                    -f) force=true;;
                    -n) shift; name="$1";;
                    *) file="$1"; shift; break;;
                esac
                shift
            done
            if [ $# -gt 0 ]; then
                echo "Not expecting additional arguments" >&2
                return 1
            elif [ -z "$file" ]; then
                echo "Expecting filename" >&2
                return 1
            fi
            if [ -z "$name" ]; then
                name=${file##*/}
            fi
            if [ x$name = xALL ]; then
                echo "Error: ALL is a reserved word for plugins" >&2
                return 1
            fi
            mkdir -p "${plugindir}"
            if [ -x $plugindir/$name -a $force = false ]; then
                echo "Plugin $name exists" >&2
                return 1
            elif [ ! -r $file ]; then
                echo "Plugin file ($file) not readable" >&2
                return 1
            fi
            cp -p $file $plugindir/$name
            chmod u+x $plugindir/$name
            _ws_debug 2 "Installed $plugindir/$name"
            return 0
            ;;
        uninstall)
            local dir wsdir name="$1"
            for dir in $WS_DIR/*/.ws; do
                wsdir=${dir%/.ws}
                wsname=${wsdir##*/}
                _ws_cmd_plugin remove "$wsname" "$name"
            done
            if [ -x "$plugindir/$name" ]; then
                rm "$plugindir/$name"
                _ws_debug 2 "Uninstalled $plugindir/$name"
            else
                echo "Plugin $name is not installed." >&2
                return 1
            fi
            return 0
            ;;
        list)
            local dir name wsdir wsname="$1"
            if [ -z "$wsname" ]; then
                echo "Expecting workspace name" >&2
                return 1
            elif [ "x${wsname}" = x- ]; then
                wsname="${_ws__current:--}"
            fi
            if [ "x$wsname" = x--all ]; then
                for dir in $WS_DIR/*/.ws; do
                    wsdir="${dir%/*}"
                    name="${wsdir##*/}"
                    echo "${name}:"
                    _ws_cmd_plugin list "${name}" | sed 's/^/    /'
                done
            else
                wsdir=$(_ws_getdir "$wsname")
                if [ $? -ne 0 ]; then
                    echo "No workspace exists for $wsname" >&2
                    return 1
                elif [ -d "${wsdir}/.ws/plugins" ]; then
                    for name in "${wsdir}/.ws/plugins"/*; do
                        if [ "$name" = "${wsdir}/.ws/plugins/*" ]; then
                            break
                        fi
                        echo "${name##*/}"
                    done
                fi
            fi
            return 0
            ;;
        add)
            local wsdir wsname="$1" plugin
            shift  # rest of the arguments will be plugin names
            if [ -z "$wsname" ]; then
                echo "Expecting workspace name" >&2
                return 1
            elif [ "x${wsname}" = x- ]; then
                wsname="${_ws__current:--}"
            fi
            wsdir=$(_ws_getdir $wsname)
            if [ $? -ne 0 ]; then
                echo "No workspace exist for $wsname" >&2
                return 1
            fi
            mkdir -p "${wsdir}/.ws/plugins"
            rc=0
            if [ "x$1" = xALL ]; then
                set -- $(ws plugin available)
            fi
            for plugin in "$@"; do
                if [ ! -x "${plugindir}/${plugin}" ]; then
                    echo "Plugin $plugin not installed" >&2
                    rc=1
                elif [ ! -h "${wsdir}/.ws/plugins/${plugin}" ]; then
                    ln -s "${plugindir}/${plugin}" "${wsdir}/.ws/plugins/${plugin}"
                    _ws_debug 2 "Added $plugin to $wsname"
                fi
            done
            return $rc
            ;;
        remove)
            local wsdir wsname="$1" plugin
            shift  # rest of the arguments will be plugin names
            if [ -z "$wsname" ]; then
                echo "Expecting workspace name" >&2
                return 1
            elif [ "x$wsname" = x- ]; then
                wsname="${_ws__current:--}"
            fi
            wsdir=$(_ws_getdir "$wsname")
            if [ $? -ne 0 ]; then
                echo "No workspace exist for $wsname" >&2
                return 1
            fi
            if [ "x$1" = xALL ]; then
                set -- $(ws plugin list $wsname)
            fi
            for plugin in "$@"; do
                if [ -h "${wsdir}/.ws/plugins/${plugin}" ]; then
                    rm -f "${wsdir}/.ws/plugins/${plugin}"
                    _ws_debug 2 "Removed $plugin from $wsname"
                fi
            done
            return 0
            ;;
        show)
            _ws_show_plugin_vars "$@"
            ;;
    esac
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
EOF
    fi
}

# create an "empty" hook script
# arguments:
#   filename
_ws_generate_hook () {
    _ws_debug 7 args "$@"
    # Create an empty hook script in the workspace
    if [ -d "$(dirname $1)" -a -n "$1" ]; then
        _ws_debug 3 "create $1"
        cat > "$1" <<'EOF'
:
# this is sourced by `ws` (workspaces)
# commands could be run and the environment/shell could be modified.
# anything set by the enter operation should be wound back by leave;
# similarly, anything set by create should be removed by destroy.
#
# wshook__op         - hook operation: 'create', 'destroy', etc.
# wshook__workspace  - location of the workspace
# wshook__configdir  - location of the .ws in the workspace
# wshook__variables  - variable to unset when finished

case ${wshook__op} in
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
EOF
    chmod +x "$1"
    fi
}

_ws_run_hooks () {
    _ws_debug 7 args "$@"
    # run $WS_DIR/.ws/hook.sh and $WS_DIR/wsname/.ws.hook.sh scripts,
    # passing "create", "destroy", "enter" or "leave"
    # run $WORKSPACE/.ws/hook.sh script, passing the same
    # calls to hook.sh are NOT sandboxed as they should affect the environment
    # the 'leave' should try to put back anything that was changed by 'enter'
    # similarly, 'destroy' should put back anything changed by 'create'
    # the config.sh variables in $WS_DIR/.ws and $WS_DIR/$context/.ws are
    # assigned and unset at the end of the script
    # for backward compatibility, the .ws.sh script would be called if
    # .ws/hook.sh is not found
    local hookfile sdir wsdir rc=0 op="${1:-enter}" context=$2
    local var tmpfile="${TMPDIR:-/tmp}/ws.hook.cfg.$$.${RANDOM}.sh"
    local wshook__op wshook__workspace wshook__configdir wshook__variables
    wshook__op=${op}

    case ${op}:${2:+X} in
        # if no context ($2==""), then just return
        enter:|leave:) return ;;
    esac
    wsdir=$(_ws_getdir $context)
    if [ $? -ne 0 ]; then
        _ws_debug 2 "no workspace directory found for $context"
        return 1
    fi
    wshook__workspace="${wsdir}"
    > $tmpfile
    # gather the variables from $WS_DIR/.ws/config.sh and $wsdir/.ws/config.sh
    for sdir in $WS_DIR/.ws $wsdir/.ws; do
        if [ ! -d $sdir ]; then
            _ws_debug 2 "Workspace needs upgrade"
            _ws_upgrade_warning
        fi
        # get just the variable assignments
        if [ -r $sdir/config.sh ]; then
            grep '^[^=]*=' $sdir/config.sh >> $tmpfile
        fi
    done
    # register the variables for later unset
    wshook__variables=$(sed -n '/=.*/s///p' $tmpfile | tr '\n' ' ')
    # load the gathered variables
    [ -s $tmpfile ] && source $tmpfile
    for sdir in $WS_DIR $wsdir; do
        wshook__configdir="$sdir/.ws"
        if [ -x $sdir/.ws/hook.sh ]; then
            hookfile=$sdir/.ws/hook.sh
        elif [ -f $sdir/.ws.sh ]; then  # backward compatibility
            hookfile=$sdir/.ws.sh
        fi
        source $hookfile
        local irc=$?
        if [ $irc -ne 0 ]; then
            rc=$irc
        fi
        _ws_debug 2 "called $hookfile $op $wsdir; rc=$rc"
    done
    for plugin in "$wsdir/.ws/plugins"/*; do
        if [ "$plugin" = "$wsdir/.ws/plugins/*" ]; then
            break
        fi
        source $plugin
        local irc=$?
        if [ $irc -ne 0 ]; then
            rc=$irc
        fi
        _ws_debug 2 "called $plugin $op $wsdir; rc=$rc"
    done
    rm -f $tmpfile
    _ws_debug 4 "will unset ${wshook__variables:-<none>}"
    for var in ${wshook__variables}; do
        unset -v $var
    done
    return $rc
}

_ws_cmd_hook () {
    local hookfile="" editor=${VISUAL:-${EDITOR:-vi}}
    case $1 in
        edit)
            if [ "x$2" = x--global ]; then
                hookfile=$WS_DIR/.ws/hook.sh
            elif [ "x$2" = x--skel ]; then
                hookfile=$WS_DIR/.ws/skel.sh
            elif [ "x$2" = x- -a -n "$_ws__current" ]; then
                hookfile=$(_ws_getdir)/.ws/hook.sh
            elif [ "x$2" = x- ]; then
                echo "No workspace" >&2
                return 1
            elif [ -n "$2" ] && _ws_getdir "$2" >/dev/null 2>&1; then
                hookfile="$(_ws_getdir "$2")/.ws/hook.sh"
            else
                echo "No workspace exists for $2" >&2
                return 1
            fi
            "${editor}" "${hookfile}"
            ;;
        help)
            echo "ws hook edit -|--global|--skel|wsname"
            ;;
    esac
}

# enter a workspace, or show the current workspace
# the WORKSPACE envvar is set to the workspace
# directory and change to that directory
# the current working directory and the workspace
# are pushed onto a stack
# arguments:
#   workspace name (optional)
# return code:
#   1 if workspace directory does not exist
_ws_cmd_enter () {
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
        _ws_run_hooks leave $_ws__current
        if [ -n "$_ws__current" ]; then
            _ws_stack push "$_ws__current:$PWD"
        else
            _ws_stack push "$WORKSPACE:$PWD"
        fi
        _ws__current="$wsname"
        export WORKSPACE="$wsdir"
        cd "$wsdir"
        _ws_run_hooks enter $_ws__current
        _ws_debug 2 "entered $wsname $wsdir"
    fi
}

# leave a workspace, popping the previous context
# off the stack, changing to the old working directory
# and if present, reentering the old workspace
# arguments: none
# result code: 0
_ws_cmd_leave () {
    _ws_debug 7 args "$@"
    local oldws=${_ws__current} context oldIFS wsname wsdir
    if [ "x${_ws__current:+X}" = xX ]; then
        _ws_run_hooks leave $_ws__current
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
                if [ -z "$1" -a -z "$2" ]; then
                    wsname=""; wsdir=""
                    _ws_stack pop
                    break
                elif [ -d "$wsdir" ]; then
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
            _ws_run_hooks enter $_ws__current
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
#  plugins    - list of plugins to add
#  cfgfile    - file containing var=val pairs
# result code:
#   1 if no workspace name given, or
#     if workspace already exists
_ws_cmd_create () {
    _ws_debug 7 args "$@"
    local plugin wsdir wsname=${1:-""} plugins="$2" cfgfile="$3"
    wsname="${1:-""}"
    wsdir="$(_ws_getdir "$wsname")"
    if [ -z "$wsname" ]; then
        echo "No name given" >&2
        _ws_debug 2 "no name"
        return 1
    else
        local result
        result=$(mkdir "$wsdir" 2>&1)
        if [ $? -eq 0 ]; then
            shift  # pop wsname from the arg list
            mkdir -p "$wsdir/.ws"
            _ws_copy_skel "$wsdir"
            _ws_generate_config "$wsdir/.ws/config.sh"
            # add assignments from cli
            if [ -s "$cfgfile" ]; then
                _ws_process_configvars "$wsdir" "$cfgfile"
            fi
            for plugin in $plugins; do
                _ws_cmd_plugin add $wsname $plugin
            done
            _ws_run_hooks create $wsname
            _ws_debug 1 "$wsdir created"
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
_ws_cmd_destroy () {
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
            _ws_cmd_leave
        fi
        _ws_run_hooks destroy $wsname
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
_ws_cmd_relink () {
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
_ws_cmd_list () {
    _ws_debug 7 args "$@"
    local link sedscript="" quiet=false
    if [ "x$1" = x-q ]; then
        quiet=true
    fi
    link=$(_ws_link get)
    if [ $? -eq 0 -a $quiet = false ]; then
        sedscript="${sedscript};/^$(basename $link)\$/s/\$/@/"
    fi
    if [ x${_ws__current:+X} = xX -a $quiet = false ]; then
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
_ws_cmd_show_stack () {
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

# generate the initial structure with an empty default workspace
_ws_cmd_initialize () {
    if [ $# -gt 0 ]; then
        # change WS_DIR
        WS_DIR="$1"
    fi
    if [ -d $WS_DIR ]; then
        echo "Already initialized, aborting..."
        return 1
    fi
    mkdir -p $WS_DIR/.ws/plugins
    # extract the plugins
    if [ -f $HOME/.ws_plugins.tbz2 ]; then
        tar xjfC $HOME/.ws_plugins.tbz2 $WS_DIR/.ws plugins
        chmod +x $WS_DIR/.ws/plugins/*
    fi
    _ws_generate_hook "${WS_DIR}/.ws/hook.sh"
    _ws_generate_hook "${WS_DIR}/.ws/skel.sh"
    _ws_generate_config "${WS_DIR}/.ws/config.sh"
    _ws_cmd_create default ALL
    _ws_link set $(_ws_getdir default)
}

# remove the workspaces structure, and optionally the application
_ws_cmd_release () {
    local to_move full=false force=false
    while [ $# -gt 0 ]; do
        case $1 in
            -h|--help)
                echo "ws release [--help|--full] [-y|--yes] [{wsname}]"
                ceho "  --help    - this message"
                echo "  --full    - uninstall the code and workspace"
                echo "  -y|--yes  - force the operation (when no tty)"
                echo "  {wsname}  - optionall restore workspace to ~/workspace"
                return 0
                ;;
            --full)
                full=true
                ;;
            -y|--yes)
                force=true
                ;;
            *)
                to_move="$(_ws_getdir $1)"
                if [ $? -ne 0 ]; then
                    echo "Not a valid workspace, aborting..." >&2
                    return 1
                fi
                ;;
        esac
        shift
    done
    # ensure that we really want to destroy the whole thing
    if $force || _ws_prompt_yesno "Do you really wish to release ${WS_DIR}?"; then
        _ws_debug config -
        _ws_debug 3 "releasing ${WS_DIR}..."
        _ws_link del  # unlink ~/workspace@
        if [ -n "$to_move" -a ! -d "$to_move" ]; then
            echo "Invalid workspace to restore, aborting..." >&2
            return 1
        elif [ -n "$to_move" ]; then
            mv "$to_move" "$HOME/workspace"
            _ws_debug 1 "moved $to_move $HOME/workspace"
            rm -rf $HOME/workspace/.ws  # delete the workspace's .ws structure
        fi
        rm -rf $WS_DIR  # remove the workspaces and ~/workspaces/
        _ws_debug 1 "removed workspace structure"
        if $full; then
            local name variables
            _ws_debug 3 "removing code."
            rm -f $_WS_SOURCE  # remove the application file
            rm -f $HOME/.ws_plugins.tbz2
            variables=$(set | sed -ne '/^_ws_[a-zA-Z0-9_]*/s/ ()//p')
            for name in $variables; do
                unset $name
            done
            unset ws
            unset W_DIR _ws__stack unset _ws__current
            unset WS_DEBUG _WS_DEBUGFILE _WS_SOURCE
            unset _ws__seen_upgrade_warning
            return 0
        else
            WS_DIR=$HOME/workspaces
            _ws__stack=()
            _ws__current=""
            return 0
        fi
    else
        return 1
    fi
}

_ws_prompt_yesno () {
    local msg="$*"
    if [ -t 0 ]; then
        echo -n "$msg [y/N]  "
        while true; do
            read ANS
            case $ANS in
                y|Y|ye|YE|yes|YES)
                    return 0
                    ;;
                n|N|no|NO)
                    return 1
                    ;;
                *)
                    echo 'Expecting "y" or "n"... try again.'
                    ;;
            esac
        done
    else
        return 1
    fi
}

_ws_cmd_help () {
    _ws_debug 7 args "$@"
    local cmd
    if [ $# -gt 0 ]; then
        cmd=$1
        shift
        ws $cmd help "$@"
    else
        \cat <<'EOF'
ws [<cmd> [<args>]]
  enter [<name>]             - show the current workspace or enter one
  leave                      - leave current workspace
  create [-p <plugins>] <name> [<cfg*>]...
                             - create a new workspace
  destroy+ name              - destroy a workspace ('-' alias for current)
  current                    - show current workspace (same as 'ws enter')
  relink [<name>]            - reset ~/workspace symlink
  list                       - show available workspaces
  stack                      - show workspaces on the stack
  initialize [{wsdir}]       - create the workspaces structure
  release [--full] [--yes] [{wsname}]
                             - delete ~/workspaces, restoring workspace
  config+ <op> <wsname> ...  - modify config variables
  hook+ edit <wsname>        - edit hook scripts
  plugin+ <op> ...           - manage plugins (installable hooks)
  help|-h|--help             - this message
  version                    - display version number
  [<name>]                   - same as 'ws enter [<name>]'
* <cfg> is either a filename ('=' not allowed) with configuration assignments
  or variable assignments in the form VAR=VALUE
  these are added to the config.sh file before the 'create' hook is called.
+ some commands allow '-' as an alias for the current workspace.
EOF
    fi
}

ws () {
    _ws_debug 7 args "$@"
    _ws__seen_upgrade_warning=false
    if [ "x$1" = x--help -o "x$1" = x-h ]; then
        set -- help
    fi
    local cmd="$1"
    # let's emit what the current workspace and the stack at the beginning
    # of each execution
    _ws_debug 6 "$(declare -p _ws__current)"
    _ws_debug 6 "$(declare -p _ws__stack)"
    shift
    case $cmd in
        help)
            _ws_cmd_help "$@"
            ;;
        enter)
            _ws_cmd_enter "$1"
            ;;
        leave)
            _ws_cmd_leave
            ;;
        create)
            # create can take an optional filename of the
            # configuration files
            # pop off the command from the arg list
            # the now first argument is the name
            # the rest are cfg files or variable assignments
            local plugins plugin configfile wsname
            while [ $# -gt 0 ]; do
                case $1 in
                    -p|--plugins) plugins="$2"; shift;;
                    -*) echo "Invalid option: $1" >&2; return 1;;
                    *) break;;  # don't shift
                esac
                shift
            done
            if [ "x$plugins" = xALL ]; then
                plugins="$(_ws_cmd_plugin available)"
            fi
            wsname="$1"; shift
            configfile="${TMPDIR:-/tmp}/ws.cfg.$$.${wsname}"
            # process the config (files or assignments) passed on the command-line
            _ws_parse_configvars ${configfile} "$@"
            _ws_cmd_create "$wsname" "$plugins" $configfile
            rm -f ${configfile}
            _ws_cmd_enter "$wsname"
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
            _ws_cmd_destroy "$wsname"
            ;;
        current)
            _ws_cmd_enter ""
            ;;
        relink)
            _ws_cmd_relink "$1"
            ;;
        list)
            _ws_cmd_list "$@"
            ;;
        stack)
            _ws_cmd_show_stack
            ;;
        version)
            echo "$WS_VERSION"
            ;;
        config)
            _ws_cmd_config "$@"
            ;;
        plugin)
            _ws_cmd_plugin "$@"
            ;;
        hook)
            _ws_cmd_hook "$@"
            ;;
        state)
            echo "root=$WS_DIR" "ws='$_ws__current'"
            _ws_stack state
            _ws_cmd_list | tr '\n' ' '; echo
            ;;
        reload)
            local wsfile
            if [ -n "$1" -a -f "$1" ]; then
                wsfile="$1"
            elif [ -d $HOME/.bash.d ]; then
                wsfile=${_WS_SOURCE:-${HOME}/.bash.d/ws.sh}
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
            _ws_cmd_initialize "$@"
            ;;
        release)
            _ws_cmd_release "$@"
            ;;
        *)
            _ws_cmd_enter "$cmd"
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
        commands="config create current debug destroy enter help hook initialize leave list plugin"
        commands="$commands release relink reload stack state validate version"
        names=$(ws list | tr -d '*@' | tr '\n' ' ')
        if [ $COMP_CWORD -eq 1 ]; then
            COMPREPLY=( $(compgen -W "$commands $options $names" -- ${cur}) )
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
                    COMPREPLY=( $(compgen -W "del get help list search set" -- ${cur}) )
                    return 0
                    ;;
                plugin)
                    COMPREPLY=( $(compgen -W "add help install available list remove show uninstall" -- ${cur}) )
                    return 0
                    ;;
                reload)
                    COMPREPLY=( $(compgen -f -- ${cur}) )
                    return 0
                    ;;
                create)
                    COMPREPLY=( $(compgen -W "-p --plugins" -- ${cur}) )
                    return 0
                    ;;
                hook)
                    COMPREPLY=( $(compgen -W "edit help" -- ${cur}) )
                    return 0
                    ;;
                release)
                    COMPREPLY=( $(compgen -W "--full -h --help $names" -- ${cur}) )
                    return 0
                    ;;
            esac
        elif [ $COMP_CWORD -ge 3 -a ${curop} = create ]; then
            COMPREPLY=( $(compgen -f -v -- ${cur}) )
            return 0
        elif [ $COMP_CWORD -eq 3 -a ${curop} = release -a x${prev} = x--full ]; then
            COMPREPLY=( $(compgen -W "${names}" -- ${cur}) )
            return 0
        elif [ $COMP_CWORD -eq 3 -a ${curop} = config ]; then
            # "-" is the same as the current workspace
            case ${COMP_WORDS[2]} in
                search)
                    local configvars pluginvars
                    configvars=$(_ws_show_config_vars -b -q $(_ws_cmd_list -q))
                    pluginvars=$(_ws_cmd_plugin show -q)
                    COMPREPLY=( $(compgen -W "${configvars} ${pluginvars}" -- ${cur}) )
                    return 0
                    ;;
                *)
                    COMPREPLY=( $(compgen -W "- --global $names" -- $cur) )
                    return 0
            esac
        elif [ $COMP_CWORD -eq 4 -a ${curop} = config ]; then
            case ${COMP_WORDS[2]} in
                del|get|set)
                    local configvars pluginvars
                    configvars=$(_ws_show_config_vars -b -q $(_ws_cmd_list -q))
                    pluginvars=$(_ws_cmd_plugin show -q)
                    COMPREPLY=( $(compgen -W "${configvars} ${pluginvars}" -- ${cur}) )
                    return 0
                    ;;
                list)
                    COMPREPLY=( $(compgen -W "-v --verbose" -- ${cur}) )
                    return 0
                    ;;
            esac
        elif [ $COMP_CWORD -eq 3 -a ${curop} = hook ]; then
            COMPREPLY=( $(compgen -W "$names - --global --skel" -- ${cur}) )
            return 0
        elif [ $COMP_CWORD -eq 3 -a ${curop} = plugin ]; then
            case $prev in
                available)
                    COMPREPLY=( )
                    return 0
                    ;;
                install)
                    COMPREPLY=( $(compgen -f -W "-f --force -n --name" -- ${cur}) )
                    return 0
                    ;;
                uninstall)
                    COMPREPLY=( $(compgen -W "$(ws plugin available)" -- ${cur}) )
                    return 0
                    ;;
                list)
                    COMPREPLY=( $(compgen -W "- --all $names" -- ${cur}) )
                    return 0
                    ;;
                add|remove)
                    COMPREPLY=( $(compgen -W "- $names" -- ${cur}) )
                    return 0
                    ;;
            esac
        elif [ $COMP_CWORD -ge 4 -a ${curop} = plugin ]; then
            case ${COMP_WORDS[2]} in
                install)
                    if [ "x${prev}" = x-f ]; then
                        COMPREPLY=( $(compgen -f -W "-n" -- ${cur}) )
                        return 0
                    elif [ "x${prev}" = x-n ]; then
                        :  # no completion
                    else
                        COMPREPLY=( $(compgen -f -- ${cur}) )
                        return 0
                    fi
                    ;;
                add|remove)
                    COMPREPLY=( $(compgen -W "ALL $(ws plugin available)" -- ${cur}) )
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

