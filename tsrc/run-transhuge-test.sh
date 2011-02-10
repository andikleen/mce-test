#
# run-transhuge-test.sh:
#     Script for hwpoison test of THP(Transparent Huge Page).
#
#!/bin/sh
#

THP_POISON_PRO_FILE_NAME="ttranshuge"
THP_POISON_PRO="./$THP_POISON_PRO_FILE_NAME"

THP_SYS_PATH="/sys/kernel/mm/transparent_hugepage"
THP_SYS_ENABLED_FILE="$THP_SYS_PATH/enabled"

executed_testcase=0
failed_testcase=0

error()
{
	echo "$1" && exit 1
}

env_check()
{
    if [ ! -f $THP_POISON_PRO_FILE_NAME ] ; then
	error "Please make sure there is file $THP_POISON_PRO_FILE_NAME."
    fi

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
echo "============= HWPoison Test of Transparent Huge Page ================="

exec_testcase "head" "early"

exec_testcase "head" "late_touch"

exec_testcase "head" "late_avoid"

exec_testcase "tail" "early"

exec_testcase "tail" "late_touch"

exec_testcase "tail" "late_avoid"

echo "======================================================================="
echo -n "    Num of Executed Test Case: $executed_testcase"
echo -e "    Num of Failed Case: $failed_testcase\n"
