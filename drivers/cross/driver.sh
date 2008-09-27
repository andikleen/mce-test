#!/bin/sh -xe
#
# Cross test driver: two machine are used for testing, one is host,
# the other is target. Testing runs in target machine, results are
# collected via running command remotely on target machine or serial
# port link between host and target for kernel log.
#
# Copyright (C) 2008, Intel Corp.
#   Author: Huang Ying <ying.huang@intel.com>
#
# This file is released under the GPLv2.
#

sd=$(dirname "$0")
export ROOT=`(cd $sd/../..; pwd)`

. $ROOT/lib/functions.sh
setup_path
. $ROOT/lib/dirs.sh

export driver=cross

setup_remote()
{
    ssh -n -T $RMUSR@$RMHOST rm -rf $RMDIR || die
    scp -rp $ROOT $RMUSR@$RMHOST:$RMDIR > /dev/null || die
}

setup()
{
    setup_remote
    tty_log_setup
    RSDIR=$(relative_path $ROOT $SDIR)
}

# tty log functions

tty_log_setup()
{
    TTY_LOG="$WDIR/tty_log"
    TTY_RESULT="$WDIR/tty_result"
    set +e
    killall attylog > /dev/null 2>&1
    set -e
}

tty_log_start()
{
    attylog < $SERIAL_PORT > $TTY_LOG &
}

tty_log_stop()
{
    kill %+
}

tty_log_begin()
{
    stat -c '%s' $TTY_LOG
}

tty_log_end()
{
    local sz_before=$1
    local sz_after sz_result
    sz_after=$(stat -c '%s' $TTY_LOG)
    sz_result=$(expr $sz_after - $sz_before)
    dd if=$TTY_LOG of=$TTY_RESULT bs=1 count=$sz_result \
	seek=$sz_before status=noxfer > /dev/null 2>&1
    echo $TTY_RESULT
}

wait_for_reboot()
{
    while ping -c 1 $RMHOST > /dev/null 2>&1; do
	sleep 1
    done
    while ! ping -c 1 $RMHOST > /dev/null 2>&1; do
	sleep 1
    done
    while ! ssh -q -n -T $RMUSR@$RMHOST ls ">/dev/null"; do
	sleep 1
    done
}

rexec_nowait()
{
    ssh -n -T $RMUSR@$RMHOST $RMDIR/$RSDIR/rexec.sh "$@" \
	"</dev/null > /dev/null 2>&1 &" || die
}

rexec_wait()
{
    ssh -n -T $RMUSR@$RMHOST "$@" || die
}

rtest()
{
    tty_log_start
    local before=$(tty_log_begin)
    rexec_nowait "this_case=$this_case" \
	$RMDIR/$RCDIR/$case_sh trigger
    sleep 5
    result=$(tty_log_end $before)
    tty_log_stop
    wait_for_reboot

    mkdir -p $RDIR/$this_case
    klog=$RDIR/$this_case/klog
    cp $result $klog
    export klog

    export reboot=1
    $CDIR/$case_sh get_result

    echo -n "$this_case: " | tee -a $RDIR/result
    $CDIR/$case_sh verify | tee -a $RDIR/result
}

rtest_all()
{
    for case_sh in $CASES; do
	for this_case in $($CDIR/$case_sh enumerate); do
	    export this_case
	    rtest
	done
    done
}

if [ $# -lt 1 ]; then
    die "Usage: $0 <config>"
fi

conf=$(basename $1)

. $CONF_DIR/$conf

driver_prepare

if [ -z "$RMUSR" -o -z "$RMHOST" -o -z "$RMDIR" -o -z "$SERIAL_PORT" ]; then
    die "Invalid config file, please make sure following are set: RMUSR, RMHOST, RMDIR, SERIAL_PORT"
fi

setup

rtest_all
