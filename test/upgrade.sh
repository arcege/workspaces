#!/bin/bash
# Test upgrading the current release against a past release

shtype=$1
release=$2
repodir=$3

case $shtype in
    bash|zsh) : ;;
    *) echo "Invalid shell type to test."; exit 1;;
esac
case $release in
    [0-9].[0-9]*) : ;;
    *) echo "Invalid release."; exit 1;;
esac

msg () { echo "${shtype}:${release} $*"; }

testdir=$(cd $(dirname ${BASH_SOURCE[0]}); pwd)
progdir=$(dirname $testdir)

if [ -z "$repodir" ]; then
    repodir=$progdir
fi

if [ ! -d $repodir/.git ]; then
    msg "Unable to determine code repository."
    exit 1
fi

case $shtype in
    bash)
        _ws_envshell=bash
        ;;
    zsh)
        if [ $OSTYPE != "linux-gnu" ]; then
            echo "Fatal: zsh unsupported on macos"
            exit 2
        else
            _ws_envshell=zsh
        fi
        ;;
    *)
        echo "Unsupported shell"
        exit 2
        ;;
esac

source $testdir/lib/system.sh
source $testdir/lib/redirect.sh
source $testdir/lib/functions.sh
source $testdir/lib/testdir.sh

repo=$TMPDIR/workspaces
export HOME=$TMPDIR/home
mkdir $HOME

find_bash_dir () {
    # find the ~/.bash.d or ~/.bash, if there is one
    _BASHDIR=
    if [ $_ws_envshell = bash ]; then
        if [ -d $HOME/.bash.d ]; then
            _BASHDIR=.bash.d
        elif [ -d $HOME/.bash ]; then
            _BASHDIR=.bash
        else
            _BASHDIR=.bash.d
        fi
    fi
    return 0
}

populate_home_bash () {
    local homedir="$1"
    #echo "Copying /etc/skel to $homedir"
    if [ -d /etc/skel ]; then
        cp -a /etc/skel ${homedir}
    else
        touch ${homedir}/.bashrc
    fi
}

populate_home_zsh () {
    local homedir="$1"
    #echo "Copying skel to $homedir"
}

pull_release () {
    local release=$1 extractdir=$2 progdir=$3
    #echo "Pulling $release to $extractdir"
    git clone -s -b "${release}" "${progdir}" "${extractdir}" >&2
}

validate_release () {
    local name
    if [ -n "${_BASHDIR}" -a ! -h "$HOME/${_BASHDIR}/ws.sh" ]; then
        msg "upgrade failed, ${_BASHDIR}/ws.sh is not a symlink"
        return 2
    fi
    if ! cmp -s $progdir/ws.sh $HOME/.ws/ws.sh; then
        msg "upgrade failed, ws.sh not matching"
        return 1
    fi
    for pluginfile in $HOME/workspaces/.ws/plugins/*; do
        name=${pluginfile##*/}
        if ! cmp -s $pluginfile $progdir/plugins/$name; then
            diff -u $pluginfile $progdir/plugins/$name
            msg "upgrade failed: plugin $name"
            return 1
        fi
    done
}

if [ $shtype = bash ]; then
    populate_home_bash $HOME
    shprog=/bin/bash
elif [ $shtype = zsh ]; then
    populate_home_zsh $HOME
    shprog=/usr/bin/zsh
fi

if ! pull_release ${release} ${repo} ${repodir}; then
    msg "unable to download ${release}"
    exit 1
elif ! SHELL=$shprog $shprog --login -c "${repo}/install.sh" >&2; then
    msg "failed to install ${release}"
    exit 1
elif ! find_bash_dir; then
    :
elif ! SHELL=$shprog $shprog --login -c "${progdir}/install.sh upgrade" >&2; then
    msg "failed to upgrade to current release"
    exit 1
elif ! validate_release; then
    msg "validation of ${release} failed"
    exit 1
elif ! ${testdir}/${shtype}.sh >&2; then
    msg "test on upgrade from ${release} failed"
    exit 1
fi
msg "upgrade test successful"
