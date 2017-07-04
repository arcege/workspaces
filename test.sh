#!/bin/bash
# A small functional test suite

exec 3>/dev/null

cdir=$PWD

TMPDIR=/tmp/ws.test.$$
trap "rm -rf $TMPDIR" 0 1 2 3 15
trap 'rc=$?; echo failed; exit $rc' ERR

unset WORKSPACE
export HOME=$TMPDIR

source $cdir/ws.sh

fail () { echo "failure: $*"; exit 1; }

#set -x

# check the existence of the main routine ('ws') and subroutines
command -v ws >&3 || fail cmd ws
command -v _ws_enter >&3 || fail rout _ws_enter
command -v _ws_leave >&3 || fail routine _ws_leave
command -v _ws_create >&3 || fail routine _ws_create
command -v _ws_destroy >&3 || fail routine _ws_destroy
command -v _ws_relink >&3 || fail routine _ws_relink
command -v _ws_list >&3 || fail routine _ws_list
command -v _ws_validate >&3 || fail routine _ws_validate
command -v _ws_stack >&3 || fail routine _ws_stack
command -v _ws_getdir >&3 || fail routine _ws_getdir
command -v _ws_getlink >&3 || fail routine _ws_getlink
command -v _ws_resetlink >&3 || fail routine _ws_resetlink
command -v _ws_copy_skel >&3 || fail routine _ws_copy_skel
command -v _ws_generate_hook >&3 || fail routine _ws_generate_hook
command -v _ws_hooks >&3 || fail routine _ws_hooks

# check the global variables
test "$(declare -p WS_DIR)" = "declare -r WS_DIR=\"$HOME/workspaces\"" || fail declare WS_DIR
test "$(declare -p _ws__current)" = 'declare -- _ws__current=""' || fail declare _ws__current
test "$(declare -p _ws__stack)" = "declare -a _ws__stack='()'" || fail declare _ws__stack
test "$(declare -p _ws__stkpos)" = 'declare -i _ws__stkpos="0"' || fail declare _ws__stkpos

#set +ex
ws initialize
#set -ex

test -d "$WS_DIR"   || fail dir WS_DIR
test -f "$WS_DIR/.ws.sh" || fail file WS_DIR/.ws.sh
test -f "$WS_DIR/.skel.sh" || fail file WS_DIR/.skel.sh
test -d "$WS_DIR/default" || fail dir WS_DIR/default/
test -f "$WS_DIR/default/.ws.sh" || fail file WS_DIR/default/.ws.sh
test "$(readlink $HOME/workspace)" = "$WS_DIR/default" || fail link
test "$(_ws_getdir default)" = "$WS_DIR/default" || fail routine getdir

test "$(ws list)" = "default@" || fail init cmd ws+list

ws enter default
test "${_ws__current}" = "default" || fail enter str _ws__current
test "$(ws)" = "default" || fail enter cmd ws
test "$(ws enter)" = "default" || fail enter cmd ws+enter
test "$(ws list)" = "default@*" || fail enter cmd ws+list

ws leave
test "${_ws__current}" = "" || fail leave _ws__current
test "${_ws__stkpos}" = "0" || fail leave stkpos
test "${_ws__stack[*]}" = "" || fail leave stack

ws create foobar
test -d "$WS_DIR/foobar" || fail dir WS_DIR/foobar
test -f "$WS_DIR/foobar/.ws.sh" || fail file WS_DIR/foobar/.wh.sh
test "$_ws__current" = "foobar" || fail str _ws__current

ws enter default
test -d "$WS_DIR/default" || fail dir WS_DIR/default
test "${_ws__stack[*]}" = ":$cdir foobar:$WS_DIR/foobar" || fail stack
test "${_ws__stkpos}" = "2" || fail int _ws__stkpos
test "${_ws__current}" = "default" || fail str _ws__current

ws leave
test "${_ws__current}" = "foobar" || fail leave str _ws__current
test "$(_ws_getdir)" = "$WS_DIR/foobar" || fail routine _ws_getdir
test "${_ws__stkpos}" = "1" || fail int _ws__stkpos
test "${_ws__stack[*]}" = ":$cdir" || fail stack

ws relink foobar
test $(readlink $HOME/workspace) = "$WS_DIR/foobar" || fail relink link
test "$(ws list)" = "$(echo 'default'; echo 'foobar@*')" || fail relink ws+list

ws destroy foobar >/dev/null
test "${_ws__current}" = "" || fail destroy _ws__current
test ! -d "$WS_DIR/foobar" || fail destroy WS_DIR/foobar
test ! -h "$HOME/workspace" || fail destroy link
test "$(ws list)" = 'default' || fail destroy ws+list
