#!/bin/bash
# Copyright @ 2017-2018 Michael P. Reilly. All rights reserved.

PATH=

if [ ${DEBUG:-0} = 1 ]; then
    awk () { /usr/bin/awk "$@"; }
    cat () { echo "cat $*"; }
    chmod () { echo "chmod $*"; }
    cp () { echo "cp $*"; }
    dirname () { echo "${1%/*}"; }
    grep () { /bin/grep "$@"; }
    ln () { echo "ln $*"; }
    mkdir () { echo "mkdir $*"; }
    mv () { echo "mv $*"; }
    rm () { echo "rm $*"; }
    sed () { echo "sed $*"; }
    tar () { echo "tar $*"; }
    touch () { echo "touch $*"; }
    uname () { /bin/uname ${1:+"$@"}; }

elif [ $OSTYPE = linux-gnu ]; then
    awk () { /usr/bin/awk "$@"; }
    cat () { /bin/cat ${1:+"$@"}; }
    chmod () { /bin/chmod "$@"; }
    cp () { /bin/cp "$@"; }
    dirname () { /usr/bin/dirname "$@"; }
    grep () { /bin/grep "$@"; }
    ln () { /bin/ln "$@"; }
    mkdir () { /bin/mkdir "$@"; }
    md5sum () { /usr/bin/md5sum ${1:+"$@"}; }
    mv () { /bin/mv "$@"; }
    rm () { /bin/rm "$@"; }
    sed () { /bin/sed "$@"; }
    tar () { PATH=/bin:/usr/bin /bin/tar "$@"; }
    touch () { /bin/touch "$@"; }
    uname () { /bin/uname ${1:+"$@"}; }

else  # Darwin (MacOs)
    awk () { /usr/bin/awk "$@"; }
    cat () { /bin/cat ${1:+"$@"}; }
    chmod () { /bin/chmod "$@"; }
    cp () { /bin/cp "$@"; }
    dirname () { /usr/bin/dirname "$@"; }
    grep () { /usr/bin/grep "$@"; }
    ln () { /bin/ln "$@"; }
    mkdir () { /bin/mkdir "$@"; }
    md5sum () { /sbin/md5 ${1:+"$@"} | sed 's/.* = //;s/$/  -/'; }
    mv () { /bin/mv "$@"; }
    rm () { /bin/rm "$@"; }
    sed () { /usr/bin/sed "$@"; }
    tar () { PATH=/bin:/usr/bin /usr/bin/tar "$@"; }
    touch () { /usr/bin/touch "$@"; }
    uname () { /bin/uname ${1:+"$@"}; }
fi

case $SHELL in
    */bash)
        _ws_envshell=bash
        ;;
    */zsh)
        if [ $OSTYPE != "linux-gnu" ]; then
            echo "Fatal: zsh unsupported on macos"
            exit 2
        else
            _ws_envshell=zsh
        fi
        ;;
    *)
        echo "Unsupported shell"
        exit 2
        ;;
esac

srcdir=$(dirname "${BASH_SOURCE[0]}")

if [ -d $srcdir -a -f $srcdir/ws.sh -a -d $srcdir/plugins ]; then
    : # we have what we need, it appears
else
    echo "Unable to determine distribution directory."
    exit 2
fi

# find the ~/.bash.d or ~/.bash, if there is one
_BASHDIR=
if [ $_ws_envshell = bash ]; then
    if [ -d $HOME/.bash.d ]; then
        _BASHDIR=$HOME/.bash.d
    elif [ -d $HOME/.bash ]; then
        _BASHDIR=$HOME/.bash
    else
        _BASHDIR=$HOME/.bash.d
    fi
fi

installation () {
    mkdir -p $HOME/.ws
    cp -p $srcdir/ws.sh $HOME/.ws/ws.sh
    # put the plugins into a tarball for ws+initialize to use
    tar cjfC $HOME/.ws/plugins.tbz2 ${srcdir} plugins
    install_wsh
}

pre_installation () {
    # clean up old installation locations
    if [ -n "${_BASHDIR}" -a ! -h $_BASHDIR/ws.sh ]; then
        rm -f ${_BASHDIR}/ws.sh
    fi
    rm -f $HOME/.ws_plugins.tbz2
    rm -f $HOME/.ws_versions.txt
}

post_installation () {
    # "register" the configuration script for bash
    if [ $_ws_envshell = bash -a ! -r ${_BASHDIR}/ws.sh ]; then
        mkdir -p ${_BASHDIR}
        ln -s ../.ws/ws.sh ${_BASHDIR}/ws.sh
    fi
}

install_wsh () {
    if [ ! -e $HOME/bin ]; then
        mkdir -p $HOME/bin
    elif [ ! -d $HOME/bin ]; then
        echo "Moving $HOME/bin aside, making $HOME/bin a directory."
        rm -rf $HOME/bin.old
        mv $HOME/bin $BINE/bin.old
    fi
    cp -p $srcdir/wsh.sh $HOME/bin/wsh
}

oldmd5s_hook_sh="\
2a6e92cd0efd80c65753d5f169450696
50e88ec3fe9fbea07dc019dc4966b601
5434fb008efae18f9478ecd8840c61c6
c57af9e435988bcaed1dad4ca3c942fe
bbaf9610a8a1d6fcb59f07db76244ebc
ce3e735d54ea9e54d26360b03f2fe57f
"

replace_plugin_hardlink () {
    local plugin="$1" wsdir="$2"
    local instfile="$WS_DIR/.ws/plugins/$plugin"
    local wsfile="$wsdir/.ws/plugins/$plugin"
    if [ -h "$wsfile" -a -f "$instfile" ]; then
        _ws_rm "$wsfile"
        _ws_ln -f "$instfile" "$wsfile"
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
                if grep -Fq wshook__op= $newfile; then
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
    elif grep -Fq _wshook__variables $file; then
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
    for file in $srcdir/plugins/*; do
        if [ "$file" = "plugins/*" ]; then
            break
        elif [ ! -e "$destdir/${file##*/}" ]; then
            ws plugin install $file
            add_plugin_to_all_workspaces ${file##*/}
        else
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
            if type ws 2>/dev/null | grep -Fqw reload >/dev/null; then
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
                    if grep -Fw ${_BASHDIR##*/} $file >/dev/null 2>&1; then
                        found=true
                        break
                    fi
                fi
            done

            if [ $found = false ]; then
                test -z "$last" && last=${HOME}/.bashrc
                if [ ! -e $last ]; then
                    echo : > $last
                fi
                #last=/dev/null  # for debugging
                cat <<EOF >> $last

if test -d \${HOME}/${_BASHDIR##*/}
then
    for file in \${HOME}/${_BASHDIR##*/}/*.sh
    do
        case \$file in
            "\${HOME}/${_BASHDIR##*/}/*.sh") :;;  # not found
            *) . \${file} ;;
        esac
    done
    unset file
fi
EOF

            fi
            ;;
    esac
}

zsh_processing () {
    if ! grep -Fsq .ws/ws.sh $HOME/.zshrc; then
        { echo
          echo "if [ -f $HOME/.ws/ws.sh ]; then"
          echo "    source $HOME/.ws/ws.sh"
          echo "fi"
          echo
        } >> $HOME/.zshrc
    fi
}

is_installed () {
    local wsdir=${WS_DIR:-$HOME/workspaces}
    test \( -f $HOME/.ws/ws.sh -o -f $HOME/.bash.d/ws.sh -o -f $HOME/.bash/ws.sh \) -a -d $wsdir
}

parse_args () {
    # if already installed, then we should want to upgrade more than
    # install
    if is_installed; then
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

    pre_installation

    installation

    post_installation

    source $srcdir/ws.sh

    # for just in this script, we'll ignore the upgrade warnings
    # (or we'll get false messages).
    _ws_upgrade_warning () { true; }

    pre_initialization $operation

    initialization $operation

    post_initialization $operation

    if [ $_ws_envshell = bash ]; then
        bash_processing $operation
    elif [ $_ws_envshell = zsh ]; then
        zsh_processing $operation
    fi
}

main "$@"
exit $?
