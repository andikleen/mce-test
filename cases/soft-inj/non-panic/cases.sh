#!/bin/sh
#
# Software injection based test cases - non-panic cases: test cases
# are triggered via bin/inject tool, and they will not trigger kernel
# panic.
#
# Copyright (C) 2008-2009, Intel Corp.
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
}

get_result()
{
    soft_inject_get_klog

    case "$bcase" in
	corrected|corrected_hold)
	    get_mcelog_from_dev $mcelog_result
	    ;;
	*)
	    echo '!!! Unknown case: $this_case !!!'
    esac
}

verify()
{
    removes="TSC"
    case "$bcase" in
	corrected|corrected_hold)
	    soft_inject_verify_mcelog
	    verify_klog $klog
	    ;;
	*)
	    echo "!!! Unknown case: $this_case !!!"
    esac
}

soft_inject_main "$@"
