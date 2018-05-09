:
# set up the environment
# sideeffects
# * set $cmdout and $cmderr as filename to capture output, if desired
# * reset variables that we will be using, WORKSPACE, WS_DEBUG, WS_DEBUGFILE
# * delete the log file (from previous runs)
# * ensure that the installation directory exists
# * create the plugins tarball
# * copy the program script into the reassigned $HOME
# * set md5 values for current files to be used
# * functions to be used in test runs

# these are for capturing the output while still running within the shell
# we are NOT using subshells for testing as variable assignments do not
# carry through
cmdout=${TMPDIR}/lastcmd.out
cmderr=${TMPDIR}/lastcmd.err
clear_cmdout () { rm -f ${cmdout} ${cmderr}; }

unset WORKSPACE

_WS_LOGFILE=$PWD/test.log
WS_DEBUG=4
rm -f $_WS_DEBUGFILE

mkdir -p $HOME/.ws  # relative to TMPDIR

# generate the plugins tarball that the install.sh script would
PATH=/bin:/usr/bin tar cjfC $HOME/.ws/plugins.tbz2 $cdir plugins

cp -p $cdir/ws.sh $HOME/ws.sh
source $HOME/ws.sh  # deleted during the ws+release testing

md5_config_sh='fcf0781bba73612cdc4ed6e26fcea8fc'
md5_hook_sh='ce3e735d54ea9e54d26360b03f2fe57f'

# function to reset the state, clearing stack and current workspace
reset () { cd $cdir; _ws__stack=(); _ws__current=""; }
