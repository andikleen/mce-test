#!/bin/sh
#
# Software injection based test cases: test cases are triggered via
# the mce-inject tool.
#
# Copyright (C) 2008, Intel Corp.
#   Author: Huang Ying <ying.huang@intel.com>
#
# This file is released under the GPLv2.
#

. $ROOT/lib/functions.sh
. $ROOT/lib/dirs.sh
. $ROOT/lib/mce.sh
. $ROOT/lib/soft-inject.sh

enumerate()
{
    soft_inject_enumerate
}

trigger()
{
    local tolerant_saved
    case "$bcase" in
	kill|kill_ripv|corrected_kill|kill_kill)
	    tolerant_saved=$(get_tolerant)
	    set_tolerant 2
	    ;;
    esac

    soft_inject_trigger

    case "$bcase" in
	kill|kill_ripv|corrected_kill|kill_kill)
	    set_tolerant $tolerant_saved
	    ;;
	*)
	    if [ $ret -ne 0 ]; then
		echo "  Failed: Failed to trigger"
	    fi
    esac
}

get_result()
{
    soft_inject_get_klog
    get_gcov arch/x86/kernel/cpu/mcheck/mce.c

    case "$bcase" in
	kill|kill_ripv|corrected_kill|kill_kill)
	    get_mcelog_from_dev $mcelog_result
	    ;;
	*)
	    echo '!!! Unknown case: $this_case !!!'
    esac
}

verify()
{
    local removes="TSC"
    case "$bcase" in
	kill|kill_ripv|corrected_kill|kill_kill)
	    soft_inject_verify_mcelog
	    verify_klog $klog
	    soft_inject_verify_return_val
	    ;;
	*)
	    echo "!!! Unknown case: $this_case !!!"
    esac
}

soft_inject_main "$@"
