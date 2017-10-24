#!/bin/bash
# Copyright @ 2017 Michael P. Reilly. All rights reserved.
# A small functional test suite

# handle internal redirection
exec 2>test.err 3>&2 4>/dev/null

# clear the path, use explicit pathnames in the test script, this
# will ensure that aliases and functions cannot corrupt
PATH=

case $OSTYPE in
    darwin*) is_linux=false;;
    linux*) is_linux=true;;
    *)
        if [ -x /bin/uname ]; then
            ws_uname=/bin/uname
        elif [ -x /usr/bin/uname ]; then
            ws_uname=/usr/bin/uname
        else
            echo 'unable to find "uname" in /bin /or /usr/bin' >&2
            exit 1
        fi
        case $($ws_uname -s) in
            Darwin) is_linux=false;;
            Linux) is_linux=true;;
            *)
                echo "Unsupported system type"
                exit 1
                ;;
        esac
        ;;
esac

versionstr=0.2.8.2

cdir=$PWD

# we define the basic commands as function since we clear out $PATH
# and use explicit paths
function awk { /usr/bin/awk "$@"; }
function basename { /usr/bin/basename ${1:+"$@"}; }
function cat { /bin/cat ${1:+"$@"}; }
function cd { command cd ${1:+"$@"}; }
function chmod { /bin/chmod "$@"; }
function cp { /bin/cp "$@"; }
function date { /bin/date ${1:+"$@"}; }
function dirname { /usr/bin/dirname ${1:+"$@"}; }
function echo { command echo "$@"; }
function grep { /bin/grep "$@"; }
function ln { /bin/ln "$@"; }
function ls { /bin/ls ${1:+"$@"}; }
function mkdir { /bin/mkdir "$@"; }
function mktemp { /bin/mktemp ${1:+"$@"}; }
function mv { /bin/mv "$@"; }
function readlink { /bin/readlink "$@"; }
function rm { /bin/rm "$@"; }
function rmdir { /bin/rmdir "$@"; }
function sed { /bin/sed "$@"; }
function sort { /usr/bin/sort ${1:+"$@"}; }
function tar { PATH=/bin:/usr/bin command /bin/tar "$@"; }
function touch { /bin/touch "$@"; }
function tr { /usr/bin/tr "$@"; }
function tty { /usr/bin/tty; }
# these are not in the same directory as linux
if ! $is_linux; then
    function grep { /usr/bin/grep "$@"; }
    function mktemp { /usr/bin/mktemp ${1:+"$@"}; }
    function readlink { /usr/bin/readlink "$@"; }
    function sed { /usr/bin/sed "$@"; }
    function tar { PATH=/bin:/usr/bin /usr/bin/tar "$@"; }
    function touch { /usr/bin/touch "$@"; }
    function tr { /usr/bin/tr "$@"; }
    function tty { /usr/bin/tty; }
fi

TMPDIR=/tmp/ws.test.$$
trap "/bin/rm -rf $TMPDIR" 0 1 2 3 15
mkdir $TMPDIR
#trap 'rc=$?; echo test failed; exit $rc' ERR

# these are for capturing the output while still running within the shell
# we are NOT using subshells for testing as variable assignments do not
# carry through
cmdout=${TMPDIR}/lastcmd.out
cmderr=${TMPDIR}/lastcmd.err

unset WORKSPACE
export HOME=$TMPDIR

_WS_DEBUGFILE=$PWD/test.log
WS_DEBUG=4
rm -f $_WS_DEBUGFILE

mkdir -p $HOME  # relative to TMPDIR

# generate the plugins tarball that the install.sh script would
PATH=/bin:/usr/bin tar cjfC $HOME/.ws_plugins.tbz2 $cdir plugins

cp -p $cdir/ws.sh $HOME/ws.sh
source $HOME/ws.sh  # deleted during the ws+release testing

if $is_linux; then
    function md5sum { /usr/bin/md5sum ${1:+"$@"}; }
else
    function md5sum { /sbin/md5 ${1:+"$@"} | sed 's/.* = //;s/$/  -/'; }
fi

md5_config_sh='fcf0781bba73612cdc4ed6e26fcea8fc'
md5_hook_sh='ce3e735d54ea9e54d26360b03f2fe57f'

fail () { rc=$?; echo "failure: $*"; exit $rc; }

# check the existence of the main routine ('ws') and subroutines
command -v ws >&4 || fail cmd ws
command -v _ws_cmd_help >&4 || fail routine _ws_cmd_help
command -v _ws_cmd_enter >&4 || fail routine _ws_cmd_enter
command -v _ws_cmd_leave >&4 || fail routine _ws_cmd_leave
command -v _ws_cmd_create >&4 || fail routine _ws_cmd_create
command -v _ws_cmd_destroy >&4 || fail routine _ws_cmd_destroy
command -v _ws_cmd_relink >&4 || fail routine _ws_cmd_relink
command -v _ws_cmd_list >&4 || fail routine _ws_cmd_list
command -v _ws_validate >&4 || fail routine _ws_validate
command -v _ws_cmd_show_stack >&4 || fail routine _ws_cmd_show_stack
command -v _ws_stack >&4 || fail routine _ws_stack
command -v _ws_getdir >&4 || fail routine _ws_getdir
command -v _ws_link >&4 || fail routine _ws_link
command -v _ws_cmd_initialize >&4 || fail routine _ws_cmd_initialize
command -v _ws_cmd_upgrade >&4 || fail routine _ws_cmd_upgrade
command -v _ws_copy_skel >&4 || fail routine _ws_copy_skel
command -v _ws_generate_hook >&4 || fail routine _ws_generate_hook
command -v _ws_generate_config >&4 || fail routine _ws_generate_config
command -v _ws_cmd_hook >&4 || fail routine _ws_cmd_hook
command -v _ws_run_hooks >&4 || fail routine _ws_run_hooks
command -v _ws_cmd_config >&4 || fail routine _ws_cmd_config
command -v _ws_config_edit >&4 || fail routine _ws_config_edit
command -v _ws_cmd_plugin >&4 || fail routine _ws_cmd_plugin
command -v _ws_parse_configvars >&4 || fail routine _ws_parse_configvars
command -v _ws_prompt_yesno >&4 || fail routine _ws_prompt_yesno
command -v _ws_convert_ws >&4 || fail routine _ws_convert_ws
command -v _ws_error >&4 || fail routine _ws_error

# check the global variables
test "$(declare -p WS_DIR)" = "declare -- WS_DIR=\"$HOME/workspaces\"" || fail declare WS_DIR
test "$(declare -p WS_VERSION)" = "declare -- WS_VERSION=\"${versionstr}\"" || fail declare WS_VERSION
test "$(declare -p _ws__current)" = 'declare -- _ws__current=""' || fail declare _ws__current
test "$(declare -p _ws__stack)" = "declare -a _ws__stack='()'" || fail declare _ws__stack

# a few unit tests
result=$(_ws_getdir)
rc=$?
test $rc -eq 1 -a "$result" = "" || fail unit "_ws_getdir" nows+nocur
result=$(_ws_link get)
rc=$?
test $rc -eq 1 -a "$result" = "" || fail unit "_ws_link+get" none
result=$(_ws_link set 2>&1)
rc=$?
test $rc -eq 1 -a "$result" = "Error: expecting directory" || fail unit "_ws_link+set" none
mkdir $HOME/workspace
result=$(_ws_link set /usr 2>&1)
rc=$?
test $rc -eq 1 -a "$result" = "Error: ~/workspace is not a symlink" || fail unit "_ws_link+set" dir
rmdir $HOME/workspace

# more unit tests to follow after initialization

# start of functional tests

ws initialize

test -d "$WS_DIR" || fail init dir WS_DIR/
test -d "$WS_DIR/.ws" || fail init dir WS_DIR/.ws/
test -s "$WS_DIR/.ws/config.sh" || fail init dir WS_DIR/.ws/config.sh
test -s "$WS_DIR/.ws/hook.sh" -a -x "$WS_DIR/.ws/hook.sh" || fail init file WS_DIR/.ws/hook.sh
test -s "$WS_DIR/.ws/hook.sh" -a -x "$WS_DIR/.ws/skel.sh" || fail init file WS_DIR/.ws/skel.sh
test -d "$WS_DIR/default" || fail init dir WS_DIR/default/
test -d "$WS_DIR/default/.ws" || fail init dir WS_DIR/default/.ws/
test -s "$WS_DIR/.ws/config.sh" || fail init dir WS_DIR/.ws/config.sh
test -s "$WS_DIR/.ws/hook.sh" -a -x "$WS_DIR/default/.ws/hook.sh" || fail init file WS_DIR/default/.ws/hook.sh
test "$(md5sum < $WS_DIR/.ws/hook.sh)" = "$md5_hook_sh  -" || fail init md5 hook.sh
test "$(md5sum < $WS_DIR/.ws/config.sh)" = "$md5_config_sh  -" || fail init md5 config.sh
test "$(/bin/readlink $HOME/workspace)" = "$WS_DIR/default" || fail init link
test "$(_ws_getdir default)" = "$WS_DIR/default" || fail routine getdir

test "$(ws list)" = "default@" || fail init cmd ws+list
test "$(ws stack)" = "($PWD)" || fail init cmd ws+stack

# test plugins extracted properly
test -d $WS_DIR/.ws/plugins || fail init dir plugins
test -f $WS_DIR/.ws/plugins/cdpath -a -f $WS_DIR/.ws/plugins/github || fail init file plugins

result=$(_ws_getdir default)
test $? -eq 0 -a "$result" = "$WS_DIR/default" || fail unit _ws_getdir ws
result=$(_ws_getdir foobar)
test $? -eq 1 -a "$result" = "$WS_DIR/foobar" || fail unit _ws_getdir nodir
result=$(_ws_link get)
test $? -eq 0 -a "$result" = "$WS_DIR/default" || fail unit _ws_link ws
result=$(_ws_link set $WS_DIR/default)
test $? -eq 0 -a "$result" = "" -a $(readlink $HOME/workspace) = "$WS_DIR/default" || fail unit _ws_link ws

# checking the hook system
( echo 'TEST_VALUE_1=hi'
  echo 'TEST_VALUE_2=bye'
) >> $TMPDIR/workspaces/.ws/config.sh
_ws_run_hooks enter default || fail hook+call
test x${TEST_VALUE_1:+X} = x || fail hook+config "value_1 unset"
test x${TEST_VALUE_2:+X} = x || fail hook+config "value_2 unset"

ws enter default
test "${_ws__current}" = "default" || fail enter1 str _ws__current
test "$(ws)" = "default" || fail enter1 cmd ws
test "$(ws enter)" = "default" || fail enter1 cmd ws+enter
test "$(ws list)" = "default@*" || fail enter1 cmd ws+list
test "$(ws stack | tr '\n' ' ')" = "default* (${cdir}) " || fail enter1 cmd ws+stack

ws leave
test "${_ws__current}" = "" || fail leave _ws__current
test "${_ws__stack[*]}" = "" || fail leave stack
test "$(ws stack)" = "($PWD)" || fail leave ws+stack

mkdir -p $WS_DIR/foobar1
cat > $TMPDIR/config_vars <<EOF
doset=false
dontset=true
EOF
_ws_convert_ws foobar1 'cdpath java' $TMPDIR/config_vars
test -d $WS_DIR/foobar1/.ws || fail convert_ws dir .ws
test -s "$WS_DIR/foobar1/.ws/hook.sh" -a -x "$WS_DIR/foobar1/.ws/hook.sh" ||
    fail convert_ws hook.sh
test -s "$WS_DIR/foobar1/.ws/config.sh" || fail convert_ws config.sh
result=$(ws config get foobar1 doset)
test $? -eq 0 -a "$result" = "false" || fail convert_ws config value \"doset\"
result=$(ws config get foobar1 dontset) || fail convert_ws config value \"dontset\"
rm -rf $WS_DIR/foobar1

ws create foobar
test -d "$WS_DIR/foobar" || fail create dir WS_DIR/foobar
test -d "$WS_DIR/foobar/.ws" || fail create dir WS_DIR/foobar/.ws/
test -s "$WS_DIR/foobar/.ws/hook.sh" -a -x "$WS_DIR/foobar/.ws/hook.sh" || fail create file WS_DIR/foobar/.ws/hook.sh
test -s "$WS_DIR/foobar/.ws/config.sh" || fail create file WS_DIR/foobar/.ws/config.sh
test "$_ws__current" = "foobar" || fail str _ws__current
test -d "$WS_DIR/foobar/.ws/plugins" || fail create dir WS_DIR/foobar/.ws/plugins
for plugin in $(ls -1 $WS_DIR/.ws/plugins); do
    test -h $WS_DIR/foobar/.ws/plugins/$plugin || fail create plugin+add $plugin
done

# more intensive testing of the hooks
cat > "$WS_DIR/foobar/.ws/hook.sh" <<'EOF'
:
# this is sourced by `ws` (workspaces)
# commands could be run and the environment/shell could be modified.
# anything set by the enter operation should be wound back by leave;
# similarly, anything set by create should be removed by destroy.

wsstate=$wshook__op

# any variables you use here should be unset at the end; local
# would not work as this is source'd
case ${wshook__op} in
    # the current context is NOT this workspace
    create)
        Which=$InConfig
        ;;

    # the current context is NOT this workspace
    destroy)
        IsDestroyed=ImDyingImDying
        ;;

    # the current context IS this workspace
    enter)
        HasEntered=yep
        ;;

    # the current context IS this workspace
    leave)
        HasLeft=Elvis
        ;;
esac
EOF

cat > "$WS_DIR/foobar/.ws/config.sh" <<'EOF'
InConfig=$wshook__workspace
EOF

unset wsstate IsDestroyed HasEntered HasLeft
_ws_run_hooks enter foobar; rc=$?
test $rc -eq 0 || tail hook+var failed
test x$wsstate = xenter || fail hook+var wsstate
test x$HasEntered = xyep || fail hook+var HasEntered
test x$HasLeft = x || fail hook+var unset
test x$InConfig = x || fail hook+unset InConfig
_ws_run_hooks leave foobar
test x$wsstate = xleave || fail hook+var wsstate
test x$HasLeft = xElvis || fail hook+var HasLeft
_ws_run_hooks create foobar
test x$Which = x$WS_DIR/foobar || fail hook+config passthru
test x${InConfig:+X} = x || fail hook+config unset

ws enter default
test -d "$WS_DIR/default" || fail enter2 dir WS_DIR/default
test "${_ws__stack[*]}" = ":$cdir foobar:$WS_DIR/foobar" || fail enter2 stack
test "${_ws__current}" = "default" || fail enter2 str _ws__current
test "$(ws stack | tr '\n' ' ')" = "default* foobar (${cdir}) " || fail enter2 cmd ws+stack

ws leave
test "${_ws__current}" = "foobar" || fail leave str _ws__current
test "${_ws__stack[*]}" = ":$cdir" || fail leave stack
test "$(_ws_getdir)" = "$WS_DIR/foobar" || fail routine _ws_getdir

ws relink foobar
test $(readlink $HOME/workspace) = "$WS_DIR/foobar" || fail relink link
test "$(ws list)" = "$(echo 'default'; echo 'foobar@*')" || fail relink ws+list

ws destroy foobar >/dev/null
test "${_ws__current}" = "" || fail destroy _ws__current
test ! -d "$WS_DIR/foobar" || fail destroy WS_DIR/foobar
test ! -h "$HOME/workspace" || fail destroy link
test "$(ws list)" = 'default' || fail destroy ws+list

# test destruction of workspaces before leaving one
ws create foo1
ws create foo2
ws create foo3

test $(ws current) = foo3 || fail create+current
ws destroy foo2
test ! -d $WS_DIR/foo2 || fail destroy foo2
ws destroy foo3
test $(ws current) = foo1 || fail destroy foo3-foo1
ws create foo2
ws destroy foo1
test ! -d $WS_DIR/foo1 -a $(ws current) = foo2 || fail destroy foo1
ws destroy foo2
test "$(ws current)" = "" -a "${_ws__stack[*]}" = "" || fail destroy foo2-none

# for testing passing config variables to ws+create
configfile=$TMPDIR/config.test
cat > $configfile << EOF
hook_1=hello
hook_2=goodbye
EOF

ws create xyzzy $configfile hook_3=hola
configsh=$WS_DIR/xyzzy/.ws/config.sh
test "$(md5sum < $configsh)" != "$md5_config_sh  -" || fail create+config md5 config.sh
grep -q '^hook_1=' $configsh; rc1=$?
grep -q '^hook_2=' $configsh; rc2=$?
grep -q '^hook_3=' $configsh; rc3=$?
test $rc1 -eq 0 -a $rc2 -eq 0 -a $rc3 -eq 0 || fail create+config vars included

test "$(_ws_config_edit $configsh list)" = $'hook_1\nhook_2\nhook_3' || fail ws_config list
test "$(_ws_config_edit $configsh get hook_2)" = "goodbye" || fail ws_config_edit get
var="$(_ws_config_edit $configsh get hook_4)"
test $? -eq 1 -a "$var" = "" || fail ws_config_edit get novar
var="$(_ws_config_edit $configsh set hook_4 adios)"
test $? -eq 0 -a "$var" = "" || fail ws_config_edit set newvar
test "$(_ws_config_edit $configsh get hook_4)" = "adios" || fail ws_config_edit newvar value
var="$(_ws_config_edit $configsh set hook_4 caio)"
test "$(_ws_config_edit $configsh get hook_4)" = "caio" || fail ws_config_edit exstvar value
var="$(_ws_config_edit $configsh del hook_4)"
test $? -eq 0 -a "$var" = "" || fail ws_config_edit del op
grep -Fq hook_4 $configsh && fail ws_config_edit del check
var="$(_ws_config_edit $configsh del hook_4)"
test $? -eq 0 -a "$var" = "" || fail ws_config_edit del novar

test "$(_ws_cmd_config list -w -q xyzzy)" = $'hook_1\nhook_2\nhook_3' || fail ws+config list
test "$(_ws_cmd_config get xyzzy hook_1)" = "hello" || fail ws+config get
var="$(_ws_cmd_config set xyzzy hook_4 adios)"
test $? -eq 0 -a "$var" = "" || tail ws+config set new rc
test "$(_ws_cmd_config get xyzzy hook_4)" = "adios" || fail ws+config set new value
var="$(_ws_cmd_config del xyzzy hook_4 adios)"
test $? -eq 0 -a "$var" = "" || tail ws+config del
var="$(_ws_cmd_config get xyzzy hook_4)"
test $? -eq 1 -a "$var" = "" || tail ws+config get novar

var=$(_ws_cmd_config search .)
result=$'--global: TEST_VALUE_1=\n--global: TEST_VALUE_2=\n  xyzzy: hook_1=hello\n  xyzzy: hook_2=goodbye\n  xyzzy: hook_3=hola'
test $? -eq 0 -a "$var" = "$result" || fail ws+config search

# testing for plugin
pluginfile=$TMPDIR/plugin
cat > $pluginfile <<'EOF'
:

plugin_ext_value=plugin-run
case ${wshook__op} in
    create) echo creating;;
    destroy) echo destroying;;
    enter) echo entering;;
    leave) echo leaving;;
esac
EOF

packaged_plugins="\
bitbucket
cdpath
github
java
nvm
vagrant
virtualenv
virtualenvwrapper"
ws plugin available >$cmdout 2>$cmderr
test $? -eq 0 -a "$(cat $cmdout)" = "${packaged_plugins}" || fail ws+plugin available packaged
ws plugin install $TMPDIR/plugin
test $? -eq 0 -a -x $WS_DIR/.ws/plugins/plugin || fail ws+plugin install
ws plugin available >$cmdout 2>$cmderr
new_plugins=$(echo "${packaged_plugins}
plugin" | sort)
test $? -eq 0 -a "$(cat $cmdout)" = "${new_plugins}" || fail ws+plugin available non-empty
ws create --plugins plugin testplugin1 >$cmdout 2>$cmderr
test $? -eq 0 -a -h $WS_DIR/testplugin1/.ws/plugins/plugin || fail ws+create plugin
test "$(cat $cmdout)" = $'creating\nentering' || fail ws+create plugin running
test "x${plugin_ext_value}" = xplugin-run || fail ws+plugin add var carried
var=$(ws plugin list testplugin1)
test $? -eq 0 -a "x$var" = xplugin || fail ws+plugin list non-empty
ws plugin remove testplugin1 plugin >$cmdout 2>$cmderr
test $? -eq 0 -a ! -e $WS_DIR/testplugin1/.ws/plugins/plugin || fail ws+plugin remove
ws plugin add testplugin1 plugin
test $? -eq 0 -a -h $WS_DIR/testplugin1/.ws/plugins/plugin || fail ws+plugin add

ws plugin install $TMPDIR/plugin >$cmdout 2>$cmderr
test $? -eq 1 -a "$(cat $cmderr)" = "Plugin plugin exists" || fail ws+plugin reinstall
ws plugin install -f $TMPDIR/plugin >$cmdout 2>$cmderr
test $? -eq 0 -a "$(cat $cmdout)" = "" -a -x $WS_DIR/.ws/plugins/plugin || fail ws+plugin reinstall-force
test ! -e $WS_DIR/.ws/plugins/other || fail ws+plugin assert no-other
ws plugin install -n other $TMPDIR/plugin
test $? -eq 0 -a -x $WS_DIR/.ws/plugins/other || fail ws+plugin install-name
ws create --plugins "other" testplugin2 >$cmdout 2>$cmderr
test $? -eq 0 -a "$(ws plugin list testplugin2)" = "other" || fail ws+plugin create+other
test ! -e $WS_DIR/testplugin2/.ws/plugins/plugin -a -h $WS_DIR/testplugin2/.ws/plugins/other ||
    fail assert testplugin2 plugins
ws leave >$cmdout 2>$cmderr
ws plugin uninstall other >$cmdout 2>$cmderr
test $? -eq 0 -a ! -e $WS_DIR/.ws/plugins/other -a ! -e $WS_DIR/testplugin2/.ws/plugin/other ||
    fail ws+plugin uninstall

# Testing alternate structure

ws initialize $HOME/alternate

test $WS_DIR = $HOME/alternate || fail init alternate set
test -d $HOME/alternate || fail init alternate created

# Testing releasing the structure and uninstallation

touch "$HOME/alternate/default/foo.c"
ws release default <&4 >$cmdout 2>$cmderr
test $? -eq 1 -a -d $HOME/alternate || fail release no
ws release --yes default <&4 >$cmdout 2>$cmderr
test $? -eq 0 -a ! -d $HOME/alternate || fail release yes
test -d $HOME/workspace -a -f $HOME/workspace/foo.c -a ! -d $HOME/workspace/.ws || fail release keep

rm -rf $HOME/workspace
ws initialize $HOME/alternate >$cmdout 2>$cmderr

ws release -y <&4 >$cmdout 2>$cmderr
test $? -eq 0 -a ! -d $HOME/alternate -a ! -d $HOME/workspace || fail release clean

ws release -y --full <&4 >$cmdout 2>$cmderr
test $? -eq 0 -a ! -f $HOME/.bash.d/ws.sh -a ! -f $HOME/.ws_plugins.tbz2 || fail release full

echo "tests complete."
