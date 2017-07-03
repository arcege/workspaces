# Workspaces #

Allow independent workspaces to be configured within the same
shell session.

The `WORKSPACE` environment variable is set to the workspace
directory.

This implementation is for Bash only.

The readonly shell variable `WS_DIR` is set to `$HOME/workspaces` and
is the root of the workspaces and configuration scripts.

## Installation ##

Run `./install.sh`.

This will place the ws.sh script in ~/.bash/ and ensure that the profile
scripts source it, making a `ws` function available.

It will also install a default configuration script in ~/workspaces/.ws.sh
and a skeleton script in ~/workspaces/.skel.sh.

### What to do with ~/workspace ###

If the ~/workspace exists as a directory, the question becomes, what to
do about it.  By default, it is ignored.  But its contents could become
the "default" workspace using the "replace" argument.  Or it could be
erased altogether using "erase."

## The `ws` command ##

The function ws can be called from the shell prompt.

When used by itself, it is called as `ws enter`.  If the command is not
known, then it is also called as `ws enter <name>`.  For example, running
`ws default` would be the same as `ws enter default`.

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

When an argument is given, the `enter` operation will set the WORKSPACE
environment variable to the workspace directory and change the shell's
working directory there.

As a pre-operation, the configuration files are run with the 'leave'
argument. And as a post-operation, the configuration files are run with the
'enter' argument.

If no argument is given, then the function is the same as the `current`
operation, showing the current workspace name.

Entering a workspace, places the previous context on a stack, this context
includes the workspace and the current working directory.  These are used
when leaving a workspace.

#### leave operation ####

Leave the current workspace, if entered.  Unset the WORKSPACE and return
to the directory before the `enter` operation was called.

As a pre-operation, the configuration scripts are run with the 'leave'
argument.  And as a post-operation, the configuration files are run with the
'enter' argument.

As mentioned with the `enter` operation, the previous context is popped off
of a stack, that includes the workspace and the previous working directory.

#### create operation ####

The `create` operation is very simple, the workspace directory is created,
a default (empty) configuration script named ".ws.sh" is placed there, and
the workspace is entered (as with the `enter` operation).

As a post-operation, the configuration scripts are run with the 'create'
argument.  This is performed before the `enter` operation.

#### destroy operation ####

When a workspace is no longer needed, it can be destroyed.  This involved
deleting the workspace directory and if the ~/workspace link points there,
removing it as well.

If the current workspace is being destroyed, then a `leave` operation is
performed as well.

As a post-operation, the configuration scripts are run with the 'destroy'
argument.  This is performed after the `leave` operation, if performed.

#### current operation ####

The workspace name is displayed; this is the same as the `enter` operation
with no arguments.

#### relink operation ####

The ~/workspace symbolic link points to one of the workspace directories.
This operation can change to the current workspace, if not argument is given,
or to the specified workspace.

#### list operation ####

Display a list of the workspace names.  The workspace to which ~/workspace
is pointing will be indicated with an asterisk ("\*").

#### initialize operation ###

Create the ~/workspaces/ directory. Create a 'default' workspace.  Relink
~/workspace symlink to the 'default'.  Update the global configuration
script ~/.ws.sh.   This operation is performed by the install script.

## Configuration ##

There are two configuration scripts that could be run.

* ~/.ws.sh  -- globally called
* ~/workspace/*wsname*/.ws.sh  -- specific to the workspace

Arguments are given depending on the operation: 'create', 'destroy', 'enter'
and 'leave'.

Conventionally, the 'enter' argument would set environment variables or
run commands ('nvm use' for example) for the current shell.

The 'leave' argument would unset environment variables and roll back
any command settings when "entered" (e.g. 'nvm use system').

### skel file ###

The `$WS_DIR/.skel.sh` file is copied into the workspace as .ws.sh.  This allows
a similar configuration file to be applied to all workspaces.
