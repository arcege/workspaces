:
# define functions with absolute pathnames to the real program
# if we clear out the $PATH, then we can assume that we are not getting corrupted
# by the user's environment

# we define the basic commands as function since we clear out $PATH
# and use explicit paths

function awk { /usr/bin/awk "$@"; }
function basename { /usr/bin/basename ${1:+"$@"}; }
function cat { /bin/cat ${1:+"$@"}; }
function cd { builtin cd ${1:+"$@"}; }
function chmod { /bin/chmod "$@"; }
function cmp { /usr/bin/cmp "$@"; }
function cp { /bin/cp "$@"; }
function curl { /usr/bin/curl "$@"; }
function date { /bin/date ${1:+"$@"}; }
function dirname { /usr/bin/dirname ${1:+"$@"}; }
function echo { builtin echo "$@"; }
function hg { /usr/bin/hg "$@"; }
function grep { /bin/grep "$@"; }
function gzip { /bin/gzip "$@"; }
function ln { /bin/ln "$@"; }
function ls { /bin/ls ${1:+"$@"}; }
function mkdir { /bin/mkdir "$@"; }
function mktemp { /bin/mktemp ${1:+"$@"}; }
function mv { /bin/mv "$@"; }
function readlink { /bin/readlink "$@"; }
function rm { /bin/rm "$@"; }
function rmdir { /bin/rmdir "$@"; }
function sed { /bin/sed "$@"; }
function sort { /usr/bin/sort ${1:+"$@"}; }
function tar { PATH=/bin:/usr/bin command /bin/tar "$@"; }
function touch { /bin/touch "$@"; }
function tr { /usr/bin/tr "$@"; }
function tty { /usr/bin/tty; }

# these are not in the same directory as linux
if ! $is_linux; then
    function grep { /usr/bin/grep "$@"; }
    function mktemp { /usr/bin/mktemp ${1:+"$@"}; }
    function readlink { /usr/bin/readlink "$@"; }
    function sed { /usr/bin/sed "$@"; }
    function tar { PATH=/bin:/usr/bin /usr/bin/tar "$@"; }
    function touch { /usr/bin/touch "$@"; }
    function tr { /usr/bin/tr "$@"; }
    function tty { /usr/bin/tty; }
fi

# macos has a different program and output
if $is_linux; then
    function md5sum { /usr/bin/md5sum ${1:+"$@"}; }
else
    function md5sum { /sbin/md5 ${1:+"$@"} | sed 's/.* = //;s/$/  -/'; }
fi
