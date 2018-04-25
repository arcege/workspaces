# Workspaces

## 0.5.0.1
* Fix function name in \_ws\_log.
* Add test for ws+initialize return code.
* Properly parse the bitbucket\_repos and github\_repos in zsh (and bash) using a temporary
  array.
* [Internal] Reorg the test scripts to all be under test/.

## 0.5
* Add beta zsh support
  * Functional, but not passing test suite
* Add "versions" command, which will show the available versions and can invalidate
  the cache.
* Change "debug" to "logging"; keeping debug for backward compatibility.
* [Internal] Reorg the ws.sh script for better maintenance.

## 0.4.5
* Use version file instead of static version strings.
* Fix hardlinking of plugins on upgrade.
* Better determination of upgrading vs downgrading.

## 0.4.4
* Fix where scripts are not executable (which is still valid).
* Fix \_ws\_get\_versions.
* Better compatibility between macos and linux.
* Fix grep calls.

## 0.4.3
* Remove test output files before packaging, test.log and test.err.
* Add the 'wsh.sh' file to the distribution.
* Refactor the test script, moving functionality to scripts under test/.

## 0.4.2
* Issue#4 Update bitbucket and github plugins to use reference on clone.
* Issue#3 Add subcommand ws+stack+del to remove workspaces from the stack; if the top, then run the
  leave operation.

## 0.4.1
* Add ws+hook+load and ws+hook+save commands to import and export a hook script without entering
  the editor.

## 0.4
* Create installation directory, ~/.ws/ and move files into it (prep work for zsh support).

## 0.3
* Add a wsh script that can start a new shell or a process within a workspace.

## 0.2.9
* Add ws+hook+run command to call leave hooks followed by enter hooks.
* Add ws+hook+copy command to copy hook from one workspace to another.
* Fix ws+upgrade
* Clean test files

## 0.2.8.5
* Add pythonpath plugin (request from collegue); using PYPATH config variable

## 0.2.8.4
* Fix completion issue on Darwin (macos)

## 0.2.8.3
* Fixes for vagrant plugin
* The install.py script will convert workspace plugins from symlinks to hard
  links.

## 0.2.8.2

* Issue #2 - remove sed clause that truncates based on whitespace.
* Add 'upgrade' command to update the software to the current released
  version, if necessary.
* Add 'vagrant' plugin to destroy and possible bring up/down VM(s).
* Allow install.sh to be call from any directory.
* Workspace plugins now hardlinks instead of formerly symlinks, helps with NFS.
* Handle downgrading.

## 0.2.8.1

* Add \_ws\_error function to handle error messages better.
* Compatibility for MacOS utilty pathname differences.

## 0.2.8

* Add 'convert' command and \_ws\_convert\_ws function to add a .ws structure
  with hooks, plugins and config db
    * The convert command will move the directory under WS\_DIR, also used by
      install+replace for moving ~/workspace/.
* Change utilties to use internal functions which in turn use absolute paths.
    * Needs testing on MacOS.
* Fix bug calling `_ws_link set.
* Fix bug where cdpath\_startdir will override cd from ws+leave
* Add WS_INITIALIZE env var to allow initialization when $WS_DIR exists.
* Test suite clears out $PATH to ensure less possible corruption of the
  environment.
