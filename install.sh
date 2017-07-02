#!/bin/bash

do_workspace=ignore
case $1 in
    -h|--help|help)
        cat <<EOF
$0 [opts] [directive]
  -h|--help  display this message
  help       display this message
  replace    use ~/workspace as 'default' workspace
  erase      delete ~/workspace directory
  ignore     ignore the ~/workspace directory
EOF
        exit 0
        ;;
    replace) do_workspace=replace;;
    erase) do_workspace=erase;;
    ignore) do_workspace=ignore;;
    *) echo "unknown directive: $1" >&2; exit 1;;
esac

mkdir -p $HOME/.bash

cp -p ./ws.sh $HOME/.bash/ws.sh

case $do_workspace in
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
esac

source ./ws.sh
ws initialize

case $do_workspace in
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

