:
# set up the test directory
# side-effects
# * set TMPDIR to root of test directory
# * set HOME to $TMPDIR
# * set trap to delete test directory

TMPDIR=/tmp/ws.test.$$
trap "/bin/rm -rf $TMPDIR" 0 1 2 3 15
mkdir $TMPDIR
export HOME=$TMPDIR

#trap 'rc=$?; echo test failed; exit $rc' ERR

