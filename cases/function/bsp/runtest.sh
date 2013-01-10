#!/bin/bash

cat <<-EOF

*************************************************************************
Pay attention:

This is basic BSP test, including onlining/offlining CPU0 and other
regular CPUs for 10 times by default and checking if operations for S3/S4
as expected whenever CPU0 is onlined or offlined.
*************************************************************************

*************************************************************************
execution sequence is as follows:

1. execute per cpu (CPU0,...CPUx) offline & online operation in sequence.
2. execute cpu offline & online operation in group mode.
3. execute S3/S4 test along with CPU0 onlined and offlined, respectively.

In addition, in order to avoid losing ssh connection once S3/S4 test is
not as expected accidentally, use screen tool to keep the session always
connected.

Note: "DO NOT do any operation when S3/S4 test is running."
*************************************************************************

*************************************************************************
log checking:

For detail log information please refer to following files:

mce-test/cases/function/bsp/log/*.output
mce-test/cases/function/bsp/log/*.bsplog
*************************************************************************

EOF

#export ROOT=`(cd ../../../; pwd)`
export ROOT=`pwd`

. $ROOT/lib/functions.sh

export NUM_CPU=`ls -d /sys/devices/system/cpu/cpu[0-9]* | wc -l`
export MAX_CPU=`expr $NUM_CPU - 1`
export BSP_LOG_DIR=$ROOT/cases/function/bsp/log
export BSP_LOG=$BSP_LOG_DIR/$(date +%Y-%m-%d.%H.%M.%S)-`uname -r`.bsplog
export OUTPUT_LOG=$BSP_LOG_DIR/$(date +%Y-%m-%d.%H.%M.%S)-`uname -r`.output
export FAILST=$TMP_DIR/fail.list

NUM_FAIL_CPU=`grep "CPU" $FAILST |wc -l`
NUM_PASS_CPU=`expr $NUM_CPU - $NUM_FAIL_CPU`

mkdir -p $BSP_LOG_DIR
touch $FAILST

pushd `dirname $0` > /dev/null
#check if installed screen tool
which screen &> /dev/null
if [ $? -ne 0 ]
then
	echo "Sorry, Please install screen first. Exiting..."
	exit 1
else
	#check bsp support
	if [ -f /sys/devices/system/cpu/cpu0/online ]
	then
		echo "BSP is supported by current kernel!"
	else
		echo "BSP is not supported by current kernel, please rebuild kernel \
and test again. Exiting..."
		exit 1
	fi

	screen ./bsp-test.sh

	echo "Total CPU Test: $NUM_CPU"
	echo "Total CPU Pass: $NUM_PASS_CPU"
	echo "Total CPU Fail: $NUM_FAIL_CPU"
	cat $FAILST
	cat $OUTPUT_LOG |grep  -q "FAILED"
	if [ $? -ne 0 ]
	then
		echo -e "\nTEST PASSES"
		exit 0
	else
		echo -e "\nTEST FAILS"
		exit 1
	fi
fi

popd > /dev/null
