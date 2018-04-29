:
# set the home directory
# side-effects
# * set HOME to $TMPDIR/home
if [ x${TMPDIR:+X} != xX ]; then
    echo "TMPDIR required by homedir library, but not set"
    exit 9
fi
export HOME=$TMPDIR
