#!/bin/bash

if [ ${DEBUG:-0} = 1 ]; then
    cp () { echo "cp $*"; }
    rm () { echo "rm $*"; }
    mv () { echo "mv $*"; }
    ed () { echo "ed $*"; }
    ln () { echo "ln $*"; }
    mkdir () { echo "mkdir $*"; }
    chmod () { echo "chmod $*"; }
    touch () { echo "touch $*"; }
fi

installation () {
    mkdir -p $HOME/.bash
    cp -p ./ws.sh $HOME/.bash/ws.sh
}

oldmd5s_hook_sh="\
2a6e92cd0efd80c65753d5f169450696
50e88ec3fe9fbea07dc019dc4966b601
5434fb008efae18f9478ecd8840c61c6
c57af9e435988bcaed1dad4ca3c942fe
"

update_hook () {
    local rc oldchk chksum state=none tmphook=$1 wsdir=$2 oldname=$3 newname=$4
    if [ -f $wsdir/$oldname ]; then
        mv $wsdir/$oldname $wsdir/.ws/$newname
        state=moved
    fi
    if [ -f $wsdir/.ws/$newname ]; then
        cmp $tmphook $wsdir/.ws/$newname >/dev/null 2>&1
        rc=$?
        if [ $rc -ne 0 ]; then
            chksum=$(md5sum < $wsdir/.ws/$newname)
            # if the old hook never changed, overwrite it
            for oldchk in $oldmd5s_hook_sh; do
                if [ "$chksum" = "$oldchk  -" ]; then
                    cp $tmphook $wsdir/.ws/${newname}
                    chmod +x $wsdir/.ws/${newname}
                    state=overwritten
                fi
            done
            if [ $state = moved ]; then
                cp $tmphook $wsdir/.ws/${newname}
                chmod +x $wsdir/.ws/${newname}
            elif [ $state != overwritten ]; then
                cp $tmphook $wsdir/.ws/${newname}.new
                chmod +x $wsdir/.ws/${newname}.new
            fi
            if [ $state = overwritten ]; then
                echo "Overwritten $wsdir/.ws/$newname"
            elif [ $state = moved ]; then
                echo "Moving $wsdir/$oldname to $wsdir/.ws/$newname; update with ${newname}.new"
            else
                echo "Update $wsdir/.ws/$newname with ${newname}.new"
            fi
        elif [ $state = moved ]; then
            echo "Moved $wsdir/$oldname to $wsdir/.ws/$newname"
        fi
    else
        _ws_generate_hook $wsdir/.ws/$newname
        echo "New hook $wsdir/.ws/$newname"
    fi
    if [ ! -x $wsdir/.ws/$newname ]; then
        chmod +x $wsdir/.ws/$newname
    fi
}

update_config () {
    local wsdir=$1 name=$2
    if [ ! -f $wsdir/.ws/$name -o ! -s $wsdir/.ws/$name ]; then
        _ws_generate_config $wsdir
        echo "New config $wsdir/.ws/$name"
    elif ! fgrep -q _wshook__variables $wsdir/.ws/$name; then
        # this gathers the variable names and add to the hook unset "registry" var
        vars=$(sed -ne '/=.*/{;s///;H;};${;g;s/\n/ /g;s/^ //;p}' $wsdir/.ws/$name)
        ed - $path/.ws/config.sh <<EOF
0a
# place variable names in _wshook__variables to be unset when hook completes
_wshook__variables="$vars"
.
w
EOF
        echo "Added config _wshook__variables to $wsdir/.ws/$name"
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
                echo "Source $HOME/.bash/ws.sh to get update."
            fi
            update_hook_scripts
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
    case $1 in
        replace)
            if [ $movingworkspace = true ]; then
                if [ ! -d $HOME/workspace.$$/.ws ]; then
                    mv $HOME/workspaces/default/.ws $HOME/workspace.$$/
                else
                    rm -rf $HOME/workspaces/default/.ws
                fi
                rmdir $HOME/workspaces/default
                mv $HOME/workspace.$$ $HOME/workspaces/default
            fi
            ;;
    esac
}

bash_processing () {
    case $1 in
        upgrade)
            ;;
        *)
            # check if .bash processing in one of the profile scripts
            found=false
            last=
            for file in $HOME/.profile $HOME/.bash_profile $HOME/.bashrc; do
                if [ -f $file ]; then
                    last=$file
                    if fgrep -w .bash $file >/dev/null 2>&1; then
                        found=true
                        break
                    fi
                fi
            done

            if [ $found = false ]; then
                test -z "$last" && last=${HOME}/.bashrc
                test ! -e $last && (echo 0a; echo :; echo .; echo w) | ed - "$last"

                #last=/dev/null  # for debugging
                ed - "$last" <<'EOF'
$a

if test -d ${HOME}/.bash
then
    for file in ${HOME}/.bash/*.sh
    do
        case $file in
            "${HOME}/.bash/*.sh") :;;  # not found
            *) . ${file} ;;
        esac
    done
    unset file
fi
EOF

            fi
            ;;
    esac
}

parse_args () {
    # if already installed, then we should want to upgrade more than
    # install
    if [ -f $HOME/.bash/ws.sh ]; then
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

    installation

    source ./ws.sh

    pre_initialization $operation

    initialization $operation

    post_initialization $operation

    bash_processing $operation
}

main "$@"

