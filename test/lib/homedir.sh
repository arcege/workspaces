:
# set the home directory
# side-effects
# * set HOME to $TMPDIR/home

if [ x${ROOTDIR:+X} != xX ]; then
    echo "ROOTDIR required by homedir library, but not set"
    exit 9
fi
export HOME=$ROOTDIR/home
mkdir -p $HOME
