#!/bin/bash
#
# run_thp.sh:
#     Script for hwpoison test of THP(Transparent Huge Page).
#
#

pushd `dirname $0` > /dev/null

. ./helpers.sh

load_hwpoison_inject

# make sure we have no hwpoisoned hugepage before starting this test.
free_resources > /dev/null

THP_POISON_PRO="ttranshuge"

THP_SYS_PATH="/sys/kernel/mm/transparent_hugepage"
THP_SYS_ENABLED_FILE="$THP_SYS_PATH/enabled"

error()
{
	echo "$1" && exit 1
}

env_check()
{
	which $THP_POISON_PRO > /dev/null 2>&1
	[ $? -ne 0 ] && error "Please make sure there is file $THP_POISON_PRO."

	if [ ! -d $THP_SYS_PATH ] ; then
		error "THP(Transparent Huge Page) may be not supported by kernel."
	fi

	thp_enabled="$(cat $THP_SYS_ENABLED_FILE | awk '{print $3}')"
	if [ "$thp_enabled" == "[never]" ] ; then
		error "THP(Transparent Huge Page) is disabled now."
	fi
}

result_check()
{
	if [ "$1" != "0" ] ; then
		failed_testcase=`expr $failed_testcase + 1`
	fi
}

exec_testcase()
{
	if [ "$1" = "head" ] ; then
		page_position_in_thp=0
	elif [ "$1" = "tail" ] ; then
		page_position_in_thp=1
	else
		error "Which page do you want to poison?"
	fi

	if [ "$2" = "early" ] ; then
		process_type="--early-kill"
	elif [ "$2" = "late_touch" ] ; then
		process_type=""
	elif [ "$2" = "late_avoid" ] ; then
		process_type="--avoid-touch"
	else
		error "No such process type."
	fi

	executed_testcase=`expr $executed_testcase + 1`

	echo "------------------ Case $executed_testcase --------------------"

	command="$THP_POISON_PRO $process_type --offset $page_position_in_thp"
	echo $command
	eval $command
	result_check $?

	echo -e "\n"
}

# Environment Check for Test.
env_check

# Execute Test Cases from Here.
cat <<-EOF

***************************************************************************
Pay attention:

This is the functional test for transparent huge page support of HWPoison.
***************************************************************************


EOF

echo "============= HWPoison Test of Transparent Huge Page ================="

exec_testcase "head" "early"

exec_testcase "head" "late_touch"

exec_testcase "head" "late_avoid"

exec_testcase "tail" "early"

exec_testcase "tail" "late_touch"

exec_testcase "tail" "late_avoid"

echo "======================================================================="

free_resources

show_summary

popd > /dev/null

exit $failed_testcase
