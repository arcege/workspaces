#!/bin/bash
# Copyright @ 2017 Michael P. Reilly. All rights reserved.

if [ ${DEBUG:-0} = 1 ]; then
    cp () { echo "cp $*"; }
    rm () { echo "rm $*"; }
    mv () { echo "mv $*"; }
    ed () { echo "ed $*"; }
    ln () { echo "ln $*"; }
    mkdir () { echo "mkdir $*"; }
    chmod () { echo "chmod $*"; }
    touch () { echo "touch $*"; }
    cat () { echo "cat $*"; }
    tar () { echo "tar $*"; }
fi

srcdir=$(dirname "${BASH_SOURCE[0]}")

installation () {
    if [ -d $HOME/.bash ]; then
        BASHDIR=$HOME/.bash
    else
        BASHDIR=$HOME/.bash.d
    fi
    mkdir -p $BASHDIR
    cp -p $srcdir/ws.sh $BASHDIR/ws.sh
    # put the plugins into a tarball for ws+initialize to use
    tar cjf $HOME/.ws_plugins.tbz2 plugins
}

oldmd5s_hook_sh="\
2a6e92cd0efd80c65753d5f169450696
50e88ec3fe9fbea07dc019dc4966b601
5434fb008efae18f9478ecd8840c61c6
c57af9e435988bcaed1dad4ca3c942fe
bbaf9610a8a1d6fcb59f07db76244ebc
ce3e735d54ea9e54d26360b03f2fe57f
"

case $(uname) in
    Linux)
        md5sum () { command md5sum ${1:-"$@"} | awk '{print NF}'; }
        ;;
    Darwin)
        md5sum () { command md5 ${1:-"$@"} | awk '{print $NF}'; }
        ;;
esac

replace_plugin_hardlink () {
    local plugin="$1" wsdir="$2"
    local instfile="$WS_DIR/.ws/plugins/$plugin"
    local wsfile="$wsdir/.ws/plugins/$plugin"
    if [ -h "$wsfile" -a -f "$instfile" ]; then
        _ws_rm "$wsfile"
        _ws_ln "$instfile" "$wsfile"
    fi
}

update_workspace_plugin_hardlinks () {
    local wsname="$1" wsdir
    wsdir=$(_ws_getdir $wsname)
    if [ $? -eq 0 ]; then
        _ws_cmd_plugin list $wsname -q | while read plugin; do
            replace_plugin_hardlink "$plugin" "$wsdir"
        done
    fi
}

update_plugins_hardlinks () {
    local wsname
    _ws_cmd_list -q | while read wsname; do
        update_workspace_plugin_hardlinks "$wsname"
    done
}

update_hook () {
    local oldchk chksum state=none tmphook=$1 wsdir=$2 oldname=$3 newname=$4
    local oldfile=$wsdir/$oldname newfile=$wsdir/.ws/$newname
    if [ -f $oldfile ]; then
        chksum=$(md5sum < $oldfile)
        local found=false
        for oldchk in $oldmd5s_hook_sh; do
            if [ "$chksum" = "$oldchk  -" ]; then
                found=true
            fi
        done
        # $oldname is not one of the release versions, it was changed
        # so we want to keep it
        if [ $found = false ]; then
            mv $oldfile $newfile
            state=moved
        fi
    fi
    if [ -f $newfile ]; then
        cmp $tmphook $newfile >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            chksum=$(md5sum < $newfile)
            # if the old hook never changed, overwrite it
            for oldchk in $oldmd5s_hook_sh; do
                if [ "$chksum" = "$oldchk  -" ]; then
                    cp $tmphook $newfile
                    chmod +x $newfile
                    state=overwritten
                fi
            done
            if [ $state = moved ]; then
                cp $tmphook $newfile
                state=adjust
            elif [ $state != overwritten ]; then
                if fgrep -q wshook__op= $newfile; then
                    cp $tmpdir $newfile.new
                    local sedscr1 sedscr2 sedscr3
                    sedscr1='/_wshook__op=/,/\[ -s "$_wshook__configdir\/config\.sh"/d'
                    sedscr2='/^# unset the variables registered/,/^unset _wshook__op/d'
                    sedscr3='s/_wshook__/wshook__/g'
                    mv $newfile $newfile.old
                    sed -e "$sedscr1" -e "$sedscr2" -e "$sedscr3" $newfile.old > $newfile
                    state=modified
                else
                    cp $tmphook $newfile.new
                    state=update
                fi
            fi
        fi
    else
        _ws_generate_hook $newfile
        if [ -f $oldfile ]; then
            state=replace
        else
            state=new
        fi
    fi
    if [ -f $newfile -a ! -x $newfile ]; then
        chmod +x $newfile
    fi
    if [ -f $newfile.new -a ! -x $newfile.new ]; then
        chmod +x $newfile.new
    fi
    # emit a msg
    if [ $state = new ]; then
        echo "New hook $newfile"
    elif [ $state = replace ]; then
        echo "Replaced $oldname with new $newname"
    elif [ $state = overwritten ]; then
        echo "Overwritten $newfile"
    elif [ $state = modified ]; then
        echo "Modified $newfile; old in $newname.old; new in $newname.new"
    elif [ $state = moved ]; then
        echo "Movied $oldfile to $newfile"
    elif [ $state = adjust ]; then
        echo "Moved $oldfile to $newfile; update with $newfile.new"
    elif [ $state = update ]; then
        echo "Update $newfile with $newfile.new"
    elif [ $state = none ]; then
        :
    else
        echo "[Unknown state: $state]"
    fi
}

update_config () {
    local wsdir=$1 name=$2 file
    file="$wsdir/.ws/$name"
    if [ ! -f $file -o ! -s $file ]; then
        _ws_generate_config $file
        echo "New config $file"
    elif fgrep -q _wshook__variables $file; then
        # this gathers the variable names and add to the hook unset "registry" var
        sed -i -e '/^_wshook__variables=/d;/^# .*_wshook__variables /d' $file
        echo "Removed config _wshook__variables from $file"
    fi
}

update_hook_scripts () {
    local path
    mkdir -p $WS_DIR/.ws
    tmphook=${TMPDIR:-/tmp}/wshook.$$
    _ws_generate_hook $tmphook  # generate the latest hook in a temp area
    update_hook $tmphook $WS_DIR .ws.sh hook.sh
    update_hook $tmphook $WS_DIR .skel.sh skel.sh
    update_config $WS_DIR config.sh
    for path in $WS_DIR/*; do
        if [ -d $path ]; then
            mkdir -p $path/.ws
            update_hook $tmphook $path .ws.sh hook.sh
            update_config $path config.sh
        fi
    done
    rm -f $tmphook
}

add_plugin_to_all_workspaces () {
    local wsname plugin=$1
    _ws_cmd_list -q | while read wsname; do
        _ws_cmd_plugin add $wsname $plugin
    done
}

update_plugins () {
    local file destdir=$WS_DIR/.ws/plugins
    for file in plugins/*; do
        if [ "$file" = "plugins/*" ]; then
            break
        elif [ ! -e "$destdir/${file##*/}" ]; then
            ws plugin install $file
            add_plugin_to_all_workspaces ${file##*/}
        elif [ $file -nt "$destdir/${file##*/}" ]; then
            ws plugin install -f $file
            add_plugin_to_all_workspaces ${file##*/}
        fi
    done
}

pre_initialization () {
    case $1 in
        ignore)
            if [ -d $HOME/workspace ]; then
                echo ignoring ~/workspace
            fi
            ;;
        replace)
            # we'll replace the default workspace with
            # the ~/workspace if it is an existing directory
            if [ -d $HOME/workspace -a ! -h $HOME/workspace ]; then
                movingworkspace=true
                mv $HOME/workspace $HOME/workspace.$$
            else
                movingworkspace=false
            fi
            ;;
        erase)
            rm -rf $HOME/workspace
            ;;
        upgrade)
            echo "Software updated"
            if type ws 2>/dev/null | fgrep -qw reload >/dev/null; then
                echo "Run 'ws reload' to get update."
            else
                echo "Source $BASHDIR/ws.sh to get update."
            fi
            update_hook_scripts
            update_plugins_hardlinks
            ;;
    esac
}

initialization () {
    case $1 in
        upgrade)  # we don't need to reinitialize
            ;;
        *)
            ws initialize
            ;;
    esac
}

post_initialization () {
    update_plugins

    case $1 in
        replace)
            if [ $movingworkspace = true ]; then
                rm -rf $HOME/workspaces/default
                _ws_cmd_convert default $HOME/workspace.$$ ALL /dev/null
            fi
            ;;
        upgrade)
            add_vagrant_plugin
            ;;
    esac
}

bash_processing () {
    case $1 in
        upgrade)
            ;;
        *)
            # check if .bash{,.d} processing in one of the profile scripts
            found=false
            last=
            for file in $HOME/.profile $HOME/.bash_profile $HOME/.bashrc; do
                if [ -f $file ]; then
                    last=$file
                    if fgrep -w ${BASHDIR##*/} $file >/dev/null 2>&1; then
                        found=true
                        break
                    fi
                fi
            done

            if [ $found = false ]; then
                test -z "$last" && last=${HOME}/.bashrc
                test ! -e $last && (echo 0a; echo :; echo .; echo w) | ed - "$last"

                #last=/dev/null  # for debugging
                ed - "$last" <<EOF
\$a

if test -d \${HOME}/${BASHDIR##*/}
then
    for file in \${HOME}/${BASHDIR##*/}/*.sh
    do
        case \$file in
            "\${HOME}/${BASHDIR##*/}/*.sh") :;;  # not found
            *) . \${file} ;;
        esac
    done
    unset file
fi
.
w
EOF

            fi
            ;;
    esac
}

parse_args () {
    # if already installed, then we should want to upgrade more than
    # install
    if [ \( -f $HOME/.bash.d/ws.sh -o -f $HOME/.bash/ws.sh \) -a -d $HOME/workspaces ]; then
        operation=upgrade
    else
        operation=ignore
    fi
    case $1 in
        -h|--help|help)
            cat <<EOF
$0 [opts] [directive]
  -h|--help  display this message
  help       display this message
  replace    use ~/workspace as 'default' workspace
  erase      delete ~/workspace directory
  ignore     ignore the ~/workspace directory
  upgrade    update the software
Default directive is "${operation}"
EOF
            exit 0
            ;;
        "") :;;
        ignore) operation=ignore;;
        replace) operation=replace;;
        erase) operation=erase;;
        upgrade) operation=upgrade;;
        *) echo "unknown directive: $1" >&2; exit 1;;
    esac
}

main () {
    parse_args "$@"

    unset _WS_SOURCE WS_DIR  # in case of leak from calling shell

    installation

    source $srcdir/ws.sh

    # for just in this script, we'll ignore the upgrade warnings
    # (or we'll get false messages).
    _ws_upgrade_warning () { true; }

    pre_initialization $operation

    initialization $operation

    post_initialization $operation

    bash_processing $operation
}

main "$@"

