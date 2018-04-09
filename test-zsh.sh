#!/usr/bin/zsh
# Copyright @ 2017-2018 Michael P. Reilly. All rights reserved.
# Start the functional tests using the zsh shell

export SHELL=/usr/bin/zsh

prog=${(%):-%x}
progdir=$(cd $(dirname $prog); pwd)

source $progdir/test-common.sh
exit $?

