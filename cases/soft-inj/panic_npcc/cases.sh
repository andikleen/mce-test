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

    if [ $ret -ne 0 ]; then
	echo "  Failed: Failed to trigger"
    fi
}

get_result()
{
    soft_inject_get_klog
    get_gcov arch/x86/kernel/cpu/mcheck/mce_64.c

    case "$bcase" in
	fatal_severity|uncorrected*|unknown|general*)
	    soft_inject_get_mcelog
	    ;;
	*)
	    echo "!!! Unknown case: $this_case !!!"
    esac
}

verify()
{
    local mce_panic
    local removes="TSC"
    case "$bcase" in
	fatal_severity)
	    removes="TSC RIP"
	    mce_panic=": Fatal machine check"
	    soft_inject_verify_mcelog
	    verify_klog $klog
	    soft_inject_verify_panic "$mce_panic"
	    ;;
	uncorrected|uncorrected_ripv)
	    mce_panic=": Uncorrected machine check"
	    soft_inject_verify_mcelog
	    verify_klog $klog
	    soft_inject_verify_panic "$mce_panic"
	    ;;
	uncorrected_timeout*)
	    mce_panic=": Uncorrected machine check"
	    soft_inject_verify_mcelog
	    verify_klog $klog
	    soft_inject_verify_panic "$mce_panic"
	    soft_inject_verify_timeout
	    ;;
	general)
	    removes="TSC RIP"
	    mce_panic=": Machine check"
	    soft_inject_verify_mcelog
	    verify_klog $klog
	    soft_inject_verify_panic "$mce_panic"
	    ;;
	general_timeout)
	    removes="TSC RIP"
	    mce_panic=": Machine check"
	    soft_inject_verify_mcelog
	    verify_klog $klog
	    soft_inject_verify_panic "$mce_panic"
	    soft_inject_verify_timeout
	    ;;
	unknown)
	    mce_panic=": Machine check from unknown source"
	    verify_klog $klog
	    soft_inject_verify_panic "$mce_panic"
	    ;;
	*)
	    echo "!!! Unknown case: $this_case !!!"
    esac
}

soft_inject_main "$@"
