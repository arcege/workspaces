#!/bin/bash
# Copyright @ 2017-2018 Michael P. Reilly. All rights reserved.
# Start the functional tests using the bash shell

export SHELL=/bin/bash

prog=${BASH_SOURCE[0]}
progdir=$(cd $(dirname $prog); pwd)

source $progdir/test-common.sh
exit $?
