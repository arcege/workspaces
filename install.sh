#!/bin/sh

mkdir -p $HOME/.bash

cp -p ./ws.sh $HOME/.bash/ws.sh

source ./ws.sh
ws initialize

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

