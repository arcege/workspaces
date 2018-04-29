#!/bin/bash

repodir=$1

testdir=$(cd $(dirname ${BASH_SOURCE[0]}); pwd)
rc=0

# run through the tests, not worrying about the exit status, let the test programs
# deal with their error conditions

# note: we are not ready for zsh yet

run () {
    local irc
    "$@"
    irc=$?; test $irc -ne 0 && rc=$irc
    return $irc
}

run $testdir/bash.sh

#run $testdir/zsh.sh

run $testdir/upgrade.sh bash 0.3 $repodir

run $testdir/upgrade.sh bash 0.4.1 $repodir

run $testdir/upgrade.sh bash 0.5.0.2 $repodir

#run $testdir/upgrade.sh zsh 0.5.0.2 $repodir

exit $rc
