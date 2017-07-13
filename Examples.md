# Hook Examples #

### Clone repositories ###

As an example, cloning this repositories by default in a new workspace,
that can be done by changing the skel.sh and a variable in config.sh.

config.sh:

    Repositories=https://bitbucket.org/Arcege/workspaces
    _wshook__variables=Repositories

skel.sh:

    create)
        for repourl in Repositories; do
            hg clone $repourl $_wshook_workspace/${repourl##*/}
        done
        ;;
    destroy)
        : repositories will be removed with the workspace directory
        ;;

### Setup VirtualEnv ###

skel.sh:

    create) virtualenv $_wshook__workspace/.venv;;
    enter)
        [ -d $_wshook__workspace/.venv ] && . $_wshook__workspace/.venv/bin/activate
        ;;
    leave)
        [ -d $_wshook__workspace/.venv ] && deactivate
        ;;

### Select/install NodeJS ###

config.sh:

    NODEJS_VERSION=0.12
    _wshook__variables=NODEJS_VERSION

skel.sh:

    create) nvm install ${NODEJS_VERSION};;
    enter) nvm use ${NODEJS_VERSION};;
    leave) nvm use system;;

