#!/bin/bash

export ROOT=`(cd ../../../; pwd)`
. $ROOT/lib/functions.sh
setup_path

TMP="../../../work"
TMP_DIR=${TMP_DIR:-$TMP}
if [ ! -d $TMP_DIR ]; then
TMP_DIR=$TMP
fi
export TMP_DIR

executed_testcase=0
failed_testcase=0

sysctl -q vm.memory_failure_early_kill=0

run_test() {
	[ $# -ne 2 ] && echo "$FUNCNAME: Invalid argument" >&2 && exit 1
	local tp="$1"
	local expect="$2"
	local result=

	executed_testcase=$[executed_testcase+1]
	eval $tp
	[ $? -eq 0 ] && result=success || result=failure
	if [ "$result" = "$expect" ] ; then
		echo "PASS: $tp"
	else
		failed_testcase=$[failed_testcase+1]
		if [ "$result" = "failure" ] ; then
			echo "FAIL: $tp returned with failure."
		else
			echo "FAIL: $tp returned with unexpected success."
		fi
	fi
}

free_resources() {
	# free IPC semaphores used by thugetlb.c
	ipcs -s | grep $USER | cut -f2 -d' ' | xargs ipcrm sem > /dev/null 2>&1
	# remove remaining hugepages on shmem
	ipcs -m | sed -n '4,$p' | cut -f2 -d' ' | xargs ipcrm shm > /dev/null 2>&1

	echo "Unpoisoning."
	# unpoison hugepages first to avoid needless unpoisoning for tail pages.
	page-types -b hwpoison,huge,compound_head=hwpoison,huge,compound_head -x -N
	page-types -b hwpoison -x -Nl > tmp.hwpoisonlist
	if [ $(grep "^HardwareCorrupted:" /proc/meminfo | awk '{print $2}') -ne 0 ] ; then
		echo "WARNING: hwpoison page counter is broken."
		grep "^HardwareCorrupted:" /proc/meminfo
	fi
}

show_summary() {
	echo ""
	echo -n "	Num of Executed Test Case: $executed_testcase"
	echo -e "	Num of Failed Case: $failed_testcase"
	echo ""
}

mount_hugetlbfs() {
	HT=$TMP_DIR/hugepage
	mkdir -p $HT
	mount -t hugetlbfs none $HT
	sysctl -q vm.nr_hugepages=500
}

unmount_hugetlbfs() {
	sysctl -q vm.nr_hugepages=0
	for mountpoint in $(grep hugetlbfs /proc/mounts | cut -f2 -d' ') ; do
		rm -rf $mountpoint/*
	done
	umount $HT
}
