#!/usr/bin/zsh
# Copyright @ 2017-2018 Michael P. Reilly. All rights reserved.
# Start the functional tests using the zsh shell

export SHELL=$(type -p zsh | awk '{print $NF}')

prog=${(%):-%x}
progdir=$(cd $(dirname $prog); pwd)

unset _WS_SOURCE
source $progdir/common.sh
exit $?

