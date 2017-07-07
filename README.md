# Workspaces #

Allow independent workspaces to be configured within the same
shell session.

The `WORKSPACE` environment variable is set to the workspace
directory.

This implementation is for Bash only.

The shell variable `WS_DIR` is set to `$HOME/workspaces` and
is the root of the workspaces and hook scripts.

## Installation ##

Run `./install.sh`.

This will place the ws.sh script in ~/.bash/ and ensure that the profile
scripts source it, making a `ws` function available.

It will also install a default hook script in ~/workspaces/.ws.sh
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
* create *name*  -- create and enter a new workspace
* destroy *name*  -- leave (if current) and remove a workspace and its contents
* current  -- show current workspace, same as `enter` with no argument
* relink [*name*]  -- reset the ~/workspace symlink
* list  -- show existing workspaces
* stack -- show workspaces on the stack
* initialize  -- create the structure
* help|-h|--help -- display help information
* version  -- display version number
* [*name*]  -- same as `enter [*name*]`

#### enter operation ####

When an argument is given, the `enter` operation will set the WORKSPACE
environment variable to the workspace directory and change the shell's
working directory there.

As a pre-operation, the hook files are run with the 'leave' argument. And
as a post-operation, the hook files are run with the 'enter' argument.

If no argument is given, then the function is the same as the `current`
operation, showing the current workspace name.

Entering a workspace, places the previous context on a stack, this context
includes the workspace and the current working directory.  These are used
when leaving a workspace.

#### leave operation ####

Leave the current workspace, if entered.  Unset the WORKSPACE and return
to the directory before the `enter` operation was called.

As a pre-operation, the hook scripts are run with the 'leave' argument.
And as a post-operation, the hook files are run with the 'enter' argument.

As mentioned with the `enter` operation, the previous context is popped off
of a stack, that includes the workspace and the previous working directory.

#### create operation ####

The `create` operation is very simple, the workspace directory is created,
a default (empty) hook script named ".ws.sh" is placed there, and the
workspace is entered (as with the `enter` operation).

As a post-operation, the hook scripts are run with the 'create' argument.
This is performed before the `enter` operation.

#### destroy operation ####

When a workspace is no longer needed, it can be destroyed.  This involved
deleting the workspace directory and if the ~/workspace link points there,
removing it as well.

If the current workspace is being destroyed, then a `leave` operation is
performed as well.

As a post-operation, the hook scripts are run with the 'destroy' argument.
This is performed after the `leave` operation, if performed.

#### current operation ####

The workspace name is displayed; this is the same as the `enter` operation
with no arguments.

#### relink operation ####

The ~/workspace symbolic link points to one of the workspace directories.
This operation can change to the current workspace, if not argument is given,
or to the specified workspace.

#### list operation ####

Display a list of the workspace names.  The workspace to which ~/workspace
is pointing will be indicated with a commat symbol ("@").  The current
workspace is indicated with an asterisk ("\*").

#### stack operation ####

Display the workspaces on the current stack, the current workspace is marked
with '\*', as with `ws list`.

#### initialize operation ####

Create the ~/workspaces/ directory. Create a 'default' workspace.  Relink
~/workspace symlink to the 'default'.  Update the global hook script ~/.ws.sh.
This operation is performed by the install script.

#### help operation ####

Display command usage.

#### version operation ####

Display current version of the app.

## Hooks ##

There are two hook scripts that could be run.

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
a similar hook file to be applied to all workspaces.


## Environment variables ##
There are some environment variables to help.

`WS_DEBUG` -- defaults to 0 (fatal), with increasing for more verbosity; log messages
are placed in $WS\_DIR/.log, indexed by date and (PID:tty) to distinguish shell's messages

`WS_DIR` -- defaults to ~/workspaces/ but root of the structure; should be left untouched

`WS_VERSION` -- version number (same as `ws version`); should be left untouched

## Hidden operations ##

There are some functions not available in the help.

#### debug operation ####

Change the debug messaging.  If no argument, show current debugging state.
If a pathname, starting with "/", change the output file.  If starting with a numeral,
change the debug level.  If "reset", then change back to original values.

Lower debug levels mean more verbosity.
To send output to terminal, use `ws debug /dev/tty`.

#### reload operation ####

After an upgrade, this will reload the shell with the latest version in ~/.bash/ws.sh.

The file used to load is preserved.  Subsequent runs of operation will use the preserved
filename by default.  The operation can take an optional filename to use.

#### state operation ####

Print the current state, including workspace, stack, etc.

#### validate operation ####

Correct inconsistencies in the environment.

* Update stack index, if necessary
* Remove ~/workspace if pointing nowhere
* Leaving current workspace if no longer exists

####### Copyright @ 2017 Michael P. Reilly. All rights reserved. #######
