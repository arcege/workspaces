:
# this will help create test harness software
# expectations
#  1. tests are to be in a single function, running as a unit
#  2. tests output and standard err will be controlled by the harness
#  3. aggregate the test results at the end
#  4. ability to propragate errors up

if [ x${ROOTDIR:+X} != xX ]; then
    echo "ROOTDIR required by harness library, but not set"
    exit 9
elif [ x${HOME} != x${ROOTDIR}/home ]; then
    echo "HOME required by harness library, but not set appropriately"
    exit 9
fi

LOGDIR=$ROOTDIR/logs
mkdir -p $LOGDIR

if [ -t 0 ]; then
    _reset=$'\e[0m'
    _red=$'\e[31m'
    _green=$'\e[32m'
else
    _reset=''
    _red=''
    _green=''
fi

format_name () {
    local ten seventy
    ten="          "
    seventy="${ten}${ten}${ten}${ten}${ten}${ten}${ten}"
    echo "${1:0:70}${seventy:0:$((70 - ${#1}))}"
}

show_ok () {
    local name
    name=$(format_name "$1")
    echo -e "${SHELL##*/}.${name}      ${_green}[OK]${_reset}"
}

show_fail () {
    local name
    name=$(format_name "$1")
    echo -e "${SHELL##*/}.${name}    ${_red}[FAIL]${_reset}"
}

get_module () {
    local filename
    case $SHELL in
        */bash) filename=${BASH_SOURCE[2]};;
        */zsh)  filename=
    esac
    basename "$filename" .sh
}

run_test () {
    local fullname module name
    name=$1
    module=$(get_module)
    if [ -n "$module" ]; then
        fullname="$module.$name"
    else
        fullname="$name"
    fi
    if [ ! -d $LOGDIR/$name ]; then
        shift
        mkdir -p $LOGDIR/$name
        "$@" > $LOGDIR/$name/log 2> $LOGDIR/$name/err
        rc=$?
        echo rc=$rc > $LOGDIR/$name/rc
        if [ $rc -eq 0 ]; then
            show_ok "${fullname}"
        else
            show_fail "${fullname}"
        fi
    fi
}

aggregate_tests () {
    local arc=0 dir name rc
    #ls -lAR $LOGDIR
    for dir in $LOGDIR/*; do
        name=${dir##*/}
        source $dir/rc
        if [ $rc -ne 0 ]; then
            arc=$rc
            echo "==${name}=="
            echo "rc=$rc"
            echo "--stdout--"
            cat $dir/log
            echo "--stderr--"
            cat $dir/err
            echo "==========="
        fi
    done
    return $arc
}

reset_home () {
    ws release -y
    ws initialize
}
