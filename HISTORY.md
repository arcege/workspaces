= Workspaces

== 0.2.8.4
* Fix completion issue on Darwin (macos)

== 0.2.8.3
* Fixes for vagrant plugin
* The install.py script will convert workspace plugins from symlinks to hard
  links.

== 0.2.8.2

* Issue #2 - remove sed clause that truncates based on whitespace.
* Add 'upgrade' command to update the software to the current released
  version, if necessary.
* Add 'vagrant' plugin to destroy and possible bring up/down VM(s).
* Allow install.sh to be call from any directory.
* Workspace plugins now hardlinks instead of formerly symlinks, helps with NFS.
* Handle downgrading.

== 0.2.8.1

* Add \_ws\_error function to handle error messages better.
* Compatibility for MacOS utilty pathname differences.

== 0.2.8

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
