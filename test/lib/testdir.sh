:
# set up the test directory
# side-effects
# * set TMPDIR to root of test directory
# * set trap to delete test directory

ROOTDIR=/tmp/ws.test.$$
TMPDIR=$ROOTDIR/tmp
trap "/bin/rm -rf $ROOTDIR" 0 1 2 3 15
mkdir $ROOTDIR $TMPDIR

#trap 'rc=$?; echo test failed; exit $rc' ERR

