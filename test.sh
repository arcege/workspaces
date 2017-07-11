#!/bin/bash
# Copyright @ 2017 Michael P. Reilly. All rights reserved.
# A small functional test suite

exec 3>/dev/null

versionstr="0.2.0"

cdir=$PWD

TMPDIR=/tmp/ws.test.$$
trap "rm -rf $TMPDIR" 0 1 2 3 15
#trap 'rc=$?; echo test failed; exit $rc' ERR
mkdir $TMPDIR

unset WORKSPACE
export HOME=$TMPDIR

_WS_DEBUGFILE=$PWD/test.log
WS_DEBUG=2
rm -f $_WS_DEBUGFILE

source $cdir/ws.sh

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
command -v _ws_hooks >&3 || fail routine _ws_hooks
command -v _ws_hook >&3 || fail routine _ws_hook

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
test -f "$WS_DIR/.ws/config.sh" || fail init dir WS_DIR/.ws/config.sh
test -x "$WS_DIR/.ws/hook.sh" || fail init file WS_DIR/.ws/hook.sh
test -x "$WS_DIR/.ws/skel.sh" || fail init file WS_DIR/.ws/skel.sh
test -d "$WS_DIR/default" || fail init dir WS_DIR/default/
test -d "$WS_DIR/default/.ws" || fail init dir WS_DIR/default/.ws/
test -x "$WS_DIR/default/.ws/hook.sh" || fail init file WS_DIR/default/.ws/hook.sh
test "$(readlink $HOME/workspace)" = "$WS_DIR/default" || fail init link
test "$(_ws_getdir default)" = "$WS_DIR/default" || fail routine getdir

test "$(ws list)" = "default@" || fail init cmd ws+list
test "$(ws stack)" = "" || fail init cmd ws+stack

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
test "$(ws stack)" = "" || fail leave ws+stack

ws create foobar
test -d "$WS_DIR/foobar" || fail create dir WS_DIR/foobar
test -d "$WS_DIR/foobar/.ws" || fail create dir WS_DIR/foobar/.ws/
test -x "$WS_DIR/foobar/.ws/hook.sh" || fail create file WS_DIR/foobar/.ws/hook.sh
#test -f "$WS_DIR/foobar/.ws/config.sh" || fail create file WS_DIR/foobar/.ws/config.sh
test "$_ws__current" = "foobar" || fail str _ws__current

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

echo "tests complete."
