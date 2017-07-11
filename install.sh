#!/bin/bash

installation () {
    mkdir -p $HOME/.bash
    cp -p ./ws.sh $HOME/.bash/ws.sh
}

move_script () {
    local dir=$1 sdir=$2 oldname=$3 newname=$4
    if [ -f $dir/$oldname ]; then
        mv $dir/$oldname $dir/$sdir/$newname
        echo "Moving $dir/$sdir/$newname"
    fi
    chmod +x $dir/$sdir/$newname
}

update_hook_scripts () {
    local path
    mkdir -p $WS_DIR/.ws
    move_script $WS_DIR .ws .ws.sh hook.sh
    move_script $WS_DIR .ws .skel.sh skel.sh
    for path in $WS_DIR/*; do
        if [ -d $path ]; then
            mkdir -p $path/.ws
            move_script $path .ws .ws.sh hook.sh
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
                test ! -f $last && echo : > "$last"

                #last=/dev/null  # for debugging
                cat <<'EOF' >> "$last"

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

