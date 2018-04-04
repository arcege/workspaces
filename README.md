# Workspaces #

Allow independent workspaces to be configured within the same
shell session.

The `WORKSPACE` environment variable is set to the workspace
directory.  The current directory is changed to the workspace,
or a subdirectory using the cdpath plugin.  Code repositories can be
checked out and automatically updated.

This implementation is for Bash only, with zsh support coming soon.

The shell variable `WS_DIR` is set to `$HOME/workspaces` and
is the root of the workspaces and hook scripts.

Documentation is available on the
[wiki](https://bitbucket.org/Arcege/workspaces/wiki/Home).

## Installation ##

Download or checkout the code and run the `./install.sh` program.  The
installation directory is ~/.ws/.

A link to the script will be placed in ~/.bash.d/ for bash, and ensure
that the profile scripts source it, making a `ws` function available.
Tab completion works for subcommand, workspace names, configuration
variables and plugin names.

A data structure, ~/workspaces/, and a workspace named 'default' will
be created.

### What to do with the existing ~/workspace ###

If the ~/workspace exists as a directory, the question becomes, what to
do about it.  By default, it is ignored.  But its contents could become
the "default" workspace using the "replace" argument.  Or it could be
erased altogether using "erase."

The install script takes four possible arguments.  For the 'ignore',
'erase' and 'replace' modes, `ws initialize` is run after installing
the software.  For 'upgrade', initialization is not performed.

* ignore  -- default on new install
* upgrade -- default on existing software; `ws initialize` is not run
* erase  -- delete ~/workspace/ and its contents before initializing
* replace -- use ~/workspace/ as the 'defualt' workspace, updating it
  with hooks for `ws`

####### Copyright @ 2017-2018 Michael P. Reilly. All rights reserved. #######
