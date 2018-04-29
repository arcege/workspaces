:
# set up the test directory
# side-effects
# * set TMPDIR to root of test directory
# * set trap to delete test directory

TMPDIR=/tmp/ws.test.$$
trap "/bin/rm -rf $TMPDIR" 0 1 2 3 15
mkdir $TMPDIR

#trap 'rc=$?; echo test failed; exit $rc' ERR

