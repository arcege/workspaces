= Workspaces

== 0.2.8

* Add 'convert' command and \_ws\_convert\_ws function to add a .ws structure
  with hooks, plugins and config db
    * The convert command will move the directory under WS\_DIR, also used by
      install+replace for moving ~/workspace/.
* Change utilties to use internal functions which in turn use absolute paths.
    * Needs testing on MacOS.
* Fix bug calling `_ws_link set`.
* Test suite clears out $PATH to ensure less possible corruption of the
  environment.
