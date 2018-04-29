#!/bin/bash

repodir=$1

testdir=$(cd $(dirname ${BASH_SOURCE[0]}); pwd)

$testdir/bash.sh
#$testdir/zsh.sh

$testdir/upgrade.sh bash 0.3 $repodir

$testdir/upgrade.sh bash 0.4.1 $repodir

$testdir/upgrade.sh bash 0.5.0.2 $repodir
#$testdir/upgrade.sh zsh 0.5.0.2 $repodir
