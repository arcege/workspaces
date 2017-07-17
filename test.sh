#!/bin/bash
# Copyright @ 2017 Michael P. Reilly. All rights reserved.
# A small functional test suite

exec 2>test.err 3>&2

versionstr=0.2.3

cdir=$PWD

TMPDIR=/tmp/ws.test.$$
trap "rm -rf $TMPDIR" 0 1 2 3 15
mkdir $TMPDIR
#trap 'rc=$?; echo test failed; exit $rc' ERR

unset WORKSPACE
export HOME=$TMPDIR

_WS_DEBUGFILE=$PWD/test.log
WS_DEBUG=4
rm -f $_WS_DEBUGFILE

source $cdir/ws.sh

md5_config_sh='0810621e2e95715f23e31f0327ad8c79'
md5_hook_sh='50e88ec3fe9fbea07dc019dc4966b601'

fail () { echo "failure: $*"; exit 1; }

# check the existence of the main routine ('ws') and subroutines
command -v ws >&3 || fail cmd ws
command -v _ws_help >&3 || fail routine _ws_help
command -v _ws_enter >&3 || fail routine _ws_enter
command -v _ws_leave >&3 || fail routine _ws_leave
command -v _ws_create >&3 || fail routine _ws_create
command -v _ws_destroy >&3 || fail routine _ws_destroy
command -v _ws_relink >&3 || fail routine _ws_relink
command -v _ws_list >&3 || fail routine _ws_list
command -v _ws_validate >&3 || fail routine _ws_validate
command -v _ws_stack >&3 || fail routine _ws_stack
command -v _ws_getdir >&3 || fail routine _ws_getdir
command -v _ws_link >&3 || fail routine _ws_link
command -v _ws_copy_skel >&3 || fail routine _ws_copy_skel
command -v _ws_generate_hook >&3 || fail routine _ws_generate_hook
command -v _ws_generate_config >&3 || fail routine _ws_generate_config
command -v _ws_hooks >&3 || fail routine _ws_hooks
command -v _ws_hook >&3 || fail routine _ws_hook
command -v _ws_config >&3 || fail routine _ws_config
command -v _ws_config_edit >&3 || fail routine _ws_config_edit
command -v _ws_config_vars_edit >&3 || fail routine _ws_config_vars_edit

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
test $rc -eq 1 -a "$result" = "Error: invalid workspace" || fail unit "_ws_link+set" none
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
test "$(readlink $HOME/workspace)" = "$WS_DIR/default" || fail init link
test "$(_ws_getdir default)" = "$WS_DIR/default" || fail routine getdir

test "$(ws list)" = "default@" || fail init cmd ws+list
test "$(ws stack)" = "($PWD)" || fail init cmd ws+stack

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
  echo '_wshook__variables=("TEST_VALUE_2")'
) >> $TMPDIR/workspaces/.ws/config.sh
_ws_hook "$WS_DIR" enter "$WS_DIR" || fail hook+call
test x${TEST_VALUE_1:+X} = xX || fail hook+config "value_1 set"
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

ws create foobar
test -d "$WS_DIR/foobar" || fail create dir WS_DIR/foobar
test -d "$WS_DIR/foobar/.ws" || fail create dir WS_DIR/foobar/.ws/
test -s "$WS_DIR/.ws/hook.sh" -a -x "$WS_DIR/foobar/.ws/hook.sh" || fail create file WS_DIR/foobar/.ws/hook.sh
test -s "$WS_DIR/.ws/config.sh" || fail create file WS_DIR/foobar/.ws/config.sh
test "$_ws__current" = "foobar" || fail str _ws__current

# more intensive testing of the hooks
\cat > "$WS_DIR/foobar/.ws/hook.sh" <<'EOF'
:
# this is sourced by `ws` (workspaces)
# commands could be run and the environment/shell could be modified.
# anything set by the enter operation should be wound back by leave;
# similarly, anything set by create should be removed by destroy.
_wshook__op=${1:-enter}
_wshook__workspace=$2
_wshook__configdir=$(dirname ${BASH_SOURCE[0]})
_wshook__variables=""

# load config variables, if present
[ -s "$_wshook__configdir/config.sh" ] && . "$_wshook__configdir/config.sh"

wsstate=$_wshook__op

# any variables you use here should be unset at the end; local
# would not work as this is source'd
case ${_wshook__op} in
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
# unset the variables registered
if [ -n "$_wshook__variables" ]; then
    # unset -n is not available in older bash, like on macos
    eval unset $_wshook__variables
fi
unset _wshook__op _wshook__workspace _wshook__configdir _wshook__variables
EOF

\cat > "$WS_DIR/foobar/.ws/config.sh" <<'EOF'
_wshook__variables=InConfig
InConfig=$_wshook__workspace
EOF

unset wsstate IsDestroyed HasEntered HasLeft
_ws_hook "$WS_DIR/foobar" enter "$WS_DIR/foobar"
test x$wsstate = xenter || fail hook+var wsstate
test x$HasEntered = xyep || fail hook+var HasEntered
test x$HasLeft = x || fail hook+var unset
test x$InConfig = x || fail hook+unset InConfig
_ws_hook "$WS_DIR/foobar" leave "$WS_DIR/foobr"
test x$wsstate = xleave || fail hook+var wsstate
test x$HasLeft = xElvis || fail hook+var HasLeft
_ws_hook "$WS_DIR/foobar" create "$WS_DIR/foobar"
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
\cat > $configfile << EOF
hook_1=hello
hook_2=goodbye
EOF

ws create xyzzy $configfile hook_3=hola
configsh=$WS_DIR/xyzzy/.ws/config.sh
test "$(md5sum < $configsh)" != "$md5_config_sh  -" || fail create+config md5 config.sh
fgrep -q '_wshook__variables=" hook_1 hook_2 hook_3"' "$configsh" || fail create+config registry
grep -q '^hook_1=' $configsh \
    && grep -q '^hook_2=' $configsh \
    && grep -q '^hook_3=' $configsh
test $? -eq 0 || fail create+config vars included

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
fgrep -q hook_4 $configsh && fail ws_config_edit del check
var="$(_ws_config_edit $configsh del hook_4)"
test $? -eq 0 -a "$var" = "" || fail ws_config_edit del novar

test "$(fgrep _wshook__variables= $configsh)" = '_wshook__variables=" hook_1 hook_2 hook_3"' || fail ws__variables assert
var="$(_ws_config_vars_edit $configsh add hook_4)"
test $? -eq 0 -a "$var" = "" || fail ws_config_vars add op
test "$(fgrep _wshook__variables= $configsh)" = '_wshook__variables=" hook_1 hook_2 hook_3 hook_4"' || fail ws_config_vars add var
var="$(_ws_config_vars_edit $configsh remove hook_4)"
test $? -eq 0 -a "$var" = "" || fail ws_config_vars remove op
test "$(fgrep _wshook__variables= $configsh)" = '_wshook__variables=" hook_1 hook_2 hook_3"' || fail ws_config_vars remove var

test "$(_ws_config list xyzzy)" = $'hook_1\nhook_2\nhook_3' || fail ws+config list
test "$(_ws_config get xyzzy hook_1)" = "hello" || fail ws+config get
var="$(_ws_config set xyzzy hook_4 adios)"
test $? -eq 0 -a "$var" = "" || tail ws+config set new rc
test "$(_ws_config get xyzzy hook_4)" = "adios" || fail ws+config set new value
var="$(_ws_config del xyzzy hook_4 adios)"
test $? -eq 0 -a "$var" = "" || tail ws+config del
var="$(_ws_config get xyzzy hook_4)"
test $? -eq 1 -a "$var" = "" || tail ws+config get novar

echo "tests complete."
