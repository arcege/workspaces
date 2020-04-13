#!/bin/bash
# run a full suite of tests.  The functional tests for both bash and zsh (if not mac).
# and an upgrade test against a number of releases
# unfortunately, earlier releases used 'ed', which causes a problem with the docker images
# used by bitbucket-pipline.
# using the --full would run backward compatibility tests
# without --full, only the functional tests and upgrade tests against later versions
# would be allowed

full=false

while [ $# -gt 0 ]; do
    case $1 in
        --help|-h)
            echo "$0 [--help|-h] [--full|-f] [repodir]"
            exit 0
            ;;
        --full|-f) full=true;;
        -*) echo "unexpected option"; exit 1;;
        *) repodir=$1;;
    esac
    shift
done

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

if [ $(uname) = "Linux" ]; then
    shells=( bash zsh )
elif [ $(uname) = "Darwin" ]; then
    echo "note: zsh unsupported on Darwin (macos)"
    shells=( bash )
fi

if $full; then
    versions=( 0.5.0.3 0.5.4 )
else
    versions=( 0.5.4 )
fi

for shell in ${shells[@]}; do  # zsh
    run $testdir/${shell}.sh
done

for version in ${versions[@]}; do
    for shell in ${shells[@]}; do  # zsh
        run $testdir/upgrade.sh $shell $version $repodir
    done
done

exit $rc
