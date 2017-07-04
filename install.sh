#!/bin/bash

installation () {
    mkdir -p $HOME/.bash
    cp -p ./ws.sh $HOME/.bash/ws.sh
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
            ws reload 2>/dev/null
            if [ $? -eq 1 ]; then
                echo "Source $HOME/.bash/ws.sh to get update."
            else
                echo "Run 'ws reload' to get update."
            fi
            exit
            ;;
    esac
}

initialization () {
    source ./ws.sh
    ws initialize
}

post_initialization () {
    case $1 in
        replace)
            if [ $movingworkspace = true ]; then
                if [ ! -f $HOME/workspace.$$/.wh.sh ]; then
                    mv $HOME/workspaces/default/.ws.sh $HOME/workspace.$$/
                else
                    rm $HOME/workspaces/default/.ws.sh
                fi
                rmdir $HOME/workspaces/default
                mv $HOME/workspace.$$ $HOME/workspaces/default
            fi
            ;;
    esac
}

bash_processing () {
    # check if .bash processing in one of the profile scripts
    found=false
    last=
    for file in $HOME/.profile $HOME/.bash_profile $HOME/.bashrc; do
        if [ -f $file ]; then
            last=$file
            fgrep -w .bash $file >/dev/null 2>&1
            if [ $? -eq 0 ]; then
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
}

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
EOF
        exit 0
        ;;
    ""|ignore) operation=ignore;;
    replace) operation=replace;;
    erase) operation=erase;;
    upgrade) operation=upgrade;;
    *) echo "unknown directive: $1" >&2; exit 1;;
esac

installation

pre_initialization $operation

test $operation = update && exit

initialization $operation

post_initialization $operation

bash_processing $operation

