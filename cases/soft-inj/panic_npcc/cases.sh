#!/bin/sh
#
# Software injection based test cases: test cases are triggered via
# bin/inject tool.
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
    soft_inject_trigger

    case "$bcase" in
	fatal_severity|uncorrected*|uc_no_mcip*|unknown)
	    ;;
	*)
	    if [ "$ret" -ne 0 ]; then
		echo "  Failed: Failed to trigger"
	    fi
	    ;;
    esac
}

get_result()
{
    soft_inject_get_klog
    get_gcov arch/x86/kernel/cpu/mcheck/mce.c

    case "$bcase" in
	fatal_severity|uncorrected*|unknown|uc_no_mcip*)
	    soft_inject_get_mcelog
	    ;;
	*)
	    echo "!!! Unknown case: $this_case !!!"
    esac
}

verify()
{
    local mce_panic
    local removes="TSC TIME PROCESSOR"
    local pcc_exp="Processor context corrupt"
    local knoripv_exp="In kernel and no restart IP"
    local no_mcip_exp="MCIP not set in MCA handler"
    local fatal_panic=": Fatal machine check"
    local general_panic=": Machine check"
    local unknown_src_panic=": Machine check from unknown source"
    case "$bcase" in
	fatal_severity)
	    removes="$removes RIP"
	    soft_inject_verify_mcelog
	    verify_klog $klog
	    soft_inject_verify_panic "$fatal_panic"
	    soft_inject_verify_exp "$pcc_exp"
	    ;;
	uncorrected)
	    soft_inject_verify_mcelog
	    verify_klog $klog
	    soft_inject_verify_panic "$fatal_panic"
	    soft_inject_verify_exp "$knoripv_exp"
	    ;;
	uncorrected_timeout*)
	    soft_inject_verify_mcelog
	    verify_klog $klog
	    soft_inject_verify_panic "$general_panic"
	    soft_inject_verify_timeout
	    soft_inject_verify_exp "$knoripv_exp"
	    ;;
	uc_no_mcip)
	    removes="$removes RIP"
	    soft_inject_verify_mcelog
	    verify_klog $klog
	    soft_inject_verify_panic "$fatal_panic"
	    soft_inject_verify_exp "$no_mcip_exp"
	    ;;
	uc_no_mcip_timeout)
	    removes="$removes RIP"
	    soft_inject_verify_mcelog
	    verify_klog $klog
	    soft_inject_verify_panic "$general_panic"
	    soft_inject_verify_exp "$no_mcip_exp"
	    soft_inject_verify_timeout
	    ;;
	unknown)
	    verify_klog $klog
	    soft_inject_verify_panic "$unk_panic"
	    ;;
	*)
	    echo "!!! Unknown case: $this_case !!!"
    esac
}

soft_inject_main "$@"
