#!/bin/bash
#
# run_hugepage.sh:
#     Test program for memory error handling for hugepages
# Author: Naoya Horiguchi

pushd `dirname $0` > /dev/null

. ./helpers.sh

mount_hugetlbfs

load_hwpoison_inject

# make sure we have no hwpoisoned hugepage before starting this test.
free_resources > /dev/null

exec_testcase() {
	echo "-------------------------------------"
	echo "TestCase $@"
	local hpage_size=2
	local hpage_target=1
	local hpage_target_offset=
	local process_type=
	local file_type=
	local share_type=
	executed_testcase=$[executed_testcase+1]

	case "$1" in
		head) hpage_target_offset=0 ;;
		tail) hpage_target_offset=1 ;;
		*) echo "Invalid argument" >&2 && exit 1 ;;
	esac
	hpage_target=$((hpage_target * 512 + hpage_target_offset))

	case "$2" in
		early) process_type="-e" ;;
		late_touch) process_type="" ;;
		late_avoid) process_type="-a" ;;
		*) echo "Invalid argument" >&2 && exit 1 ;;
	esac

	case "$3" in
		anonymous) file_type="-A" ;;
		file) file_type="-f $executed_testcase" ;;
		shm) file_type="-S" ;;
		*) echo "Invalid argument" >&2 && exit 1 ;;
	esac

	case "$4" in
		fork_shared) share_type="-F" ;;
		fork_private_nocow) share_type="-Fp" ;;
		fork_private_cow) share_type="-Fpc" ;;
		*) echo "Invalid argument" >&2 && exit 1 ;;
	esac

	local command="./thugetlb -x -m $hpage_size -o $hpage_target $process_type $file_type $share_type $HT"
	echo $command
	eval $command
	if [ $? -ne 0 ] ; then
		echo "thugetlb was killed."
		if [ "$5" = killed ] ; then
			echo "PASS"
		else
			echo "FAIL"
			failed_testcase=$[failed_testcase+1]
		fi
	else
		echo "thugetlb exited normally."
		if [ "$5" = killed ] ; then
			echo "FAIL"
			failed_testcase=$[failed_testcase+1]
		else
			echo "PASS"
		fi
	fi

	return 0
}

cat <<-EOF

***************************************************************************
Pay attention:

This is the functional test for huge page support of HWPoison.
***************************************************************************


EOF

exec_testcase head early file fork_shared killed
exec_testcase head early file fork_private_nocow killed
exec_testcase head early file fork_private_cow killed
exec_testcase head early shm fork_shared killed
exec_testcase head early anonymous fork_shared killed
exec_testcase head early anonymous fork_private_nocow killed
exec_testcase head early anonymous fork_private_cow killed

exec_testcase head late_touch file fork_shared killed
exec_testcase head late_touch file fork_private_nocow killed
exec_testcase head late_touch file fork_private_cow killed
exec_testcase head late_touch shm fork_shared killed
exec_testcase head late_touch anonymous fork_shared killed
exec_testcase head late_touch anonymous fork_private_nocow killed
exec_testcase head late_touch anonymous fork_private_cow killed

exec_testcase head late_avoid file fork_shared notkilled
exec_testcase head late_avoid file fork_private_nocow notkilled
exec_testcase head late_avoid file fork_private_cow notkilled
exec_testcase head late_avoid shm fork_shared notkilled
exec_testcase head late_avoid anonymous fork_shared notkilled
exec_testcase head late_avoid anonymous fork_private_nocow notkilled
exec_testcase head late_avoid anonymous fork_private_cow notkilled

exec_testcase tail early file fork_shared killed
exec_testcase tail early file fork_private_nocow killed
exec_testcase tail early file fork_private_cow killed
exec_testcase tail early shm fork_shared killed
exec_testcase tail early anonymous fork_shared killed
exec_testcase tail early anonymous fork_private_nocow killed
exec_testcase tail early anonymous fork_private_cow killed

exec_testcase tail late_touch file fork_shared killed
exec_testcase tail late_touch file fork_private_nocow killed
exec_testcase tail late_touch file fork_private_cow killed
exec_testcase tail late_touch shm fork_shared killed
exec_testcase tail late_touch anonymous fork_shared killed
exec_testcase tail late_touch anonymous fork_private_nocow killed
exec_testcase tail late_touch anonymous fork_private_cow killed

exec_testcase tail late_avoid file fork_shared notkilled
exec_testcase tail late_avoid file fork_private_nocow notkilled
exec_testcase tail late_avoid file fork_private_cow notkilled
exec_testcase tail late_avoid shm fork_shared notkilled
exec_testcase tail late_avoid anonymous fork_shared notkilled
exec_testcase tail late_avoid anonymous fork_private_nocow notkilled
exec_testcase tail late_avoid anonymous fork_private_cow notkilled

unmount_hugetlbfs

free_resources

show_summary

popd > /dev/null

exit $failed_testcase
