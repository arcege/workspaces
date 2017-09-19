
= 0.2.7.4

* Fix bug calling `_ws_link set`.
* Change utilties to use internal functions which in turn use absolute paths.
    * Needs testing on MacOS.
* Test suite clears out $PATH to ensure no corruption of the environment.
