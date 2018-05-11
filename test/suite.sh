#!/bin/bash

repodir=$1

testdir=$(cd $(dirname ${BASH_SOURCE[0]}); pwd)
rc=0

# run through the tests, not worrying about the exit status, let the test programs
# deal with their error conditions

# note: we are not ready for zsh yet

# side-effect, rc is set to the exit status if command fails
run () {
    local irc
    "$@"
    irc=$?; test $irc -ne 0 && rc=$irc
    return $irc
}

shells=( bash zsh )

versions=( 0.3 0.4.1 0.5.0.3 )

for shell in ${shells[@]}; do  # zsh
    run $testdir/${shell}.sh
done

for version in ${versions[@]}; do
    for shell in ${shells[@]}; do  # zsh
        run $testdir/upgrade.sh $shell $version $repodir
    done
done

exit $rc
