#!/bin/bash
# Copyright @ 2017-2018 Michael P. Reilly. All rights reserved.
# A small functional test suite

versionstr=0.4.3

cdir=$PWD

testlib=$cdir/test/lib
rundir=$cdir/test/runs

( echo X${cdir}X
  echo X${testlib}X
  echo X${rundir}X
) > /tmp/where.am.i.txt

# see files for side-effects from each
source $testlib/system.sh
source $testlib/functions.sh
source $testlib/testdir.sh
source $testlib/setup.sh

# should be no side-effects, all either pass through or call the 'fail' function
source $rundir/basics
# more unit tests to follow after initialization
source $rundir/initialize
# start of functional tests
source $rundir/operations
source $rundir/hooks
source $rundir/stack
source $rundir/config
source $rundir/plugin
source $rundir/alternate
source $rundir/release

echo "tests complete."
