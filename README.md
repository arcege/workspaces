# Workspaces #

Allow independent workspaces to be configured within the same
shell session.

The `WORKSPACE` environment variable is set to the workspace
directory.

This implementation is for Bash only.

The shell variable `WS_DIR` is set to `$HOME/workspaces` and
is the root of the workspaces and hook scripts.

Documentation is available on the
[wiki](https://bitbucket.org/Arcege/workspaces/wiki/Home).

## Installation ##

Download or checkout the code and run the `./install.sh` program.

This will place the ws.sh script in ~/.bash.d/ and ensure that the profile
scripts source it, making a `ws` function available.

It will create the data structure ~/workspaces, and a workspace named
'default'.

### What to do with ~/workspace ###

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

####### Copyright @ 2017 Michael P. Reilly. All rights reserved. #######
