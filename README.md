# Workspaces #

Allow independent workspaces to be configured within the same
shell session.

The WORKSPACE environment variable is set to the workspace
directory.

This implementation is for Bash only.

## Installation ##
Run `./install.sh`

This will place the ws.sh script in ~/.bash/ and ensure that the profile
scripts source it, making a `ws` function available.

## The `ws` command ##

The function ws can be called from the shell prompt.
### Operations ###

* enter [*name*]  -- enter a workspace
* leave  -- leave the current workspace
* create *name*
* destroy *name*
* current  -- show current workspace, same as `enter` with no argument
* relink  -- reset the ~/workspace symlink
* list  -- show existing workspaces
* initialize  -- create the structure
* [*name*]  -- same as `enter [*name*]`

#### enter operation ####

#### leave operation ####

#### create operation ####

#### destroy operation ####

#### current operation ####

#### list operation ####

#### initialie operation ###

## Configuration ##

There are two configuration files that could be run.
* ~/.ws.sh  -- globally called
* ~/workspace/*wsname*/.ws.sh  -- specific to the workspace

