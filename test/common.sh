:
# Copyright @ 2017-2018 Michael P. Reilly. All rights reserved.
# A small functional test suite

versionstr=SNAPSHOT

if [ -z "$progdir" -o ! -d "$progdir" ]; then
    echo "Expecting this to be called from another script."
    exit 1
fi

cdir=$PWD

testlib=$progdir/lib
rundir=$progdir/runs

source $testlib/system.sh
source $testlib/redirect.sh
source $testlib/path.sh
source $testlib/functions.sh
source $testlib/testdir.sh
source $testlib/homedir.sh
source $testlib/harness.sh
source $testlib/setup.sh

# each is a separate set of tests, calling run_test which will get
# aggregated at the end.  each test function should return 0 of success
# or non-zero for failure (numbers can be significate for the test cases)
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

aggregate_tests; rc=$?

case $rc in
    0) echo "${SHELL##*/} tests complete.";;
    *) echo "${SHELL##*/} tests failed.";;
esac
return $rc
