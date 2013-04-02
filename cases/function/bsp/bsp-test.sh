#!/bin/bash

#This script is for basic BSP CPU online/offline testing.

cat <<-EOF

#########################################################################
###        Test Mode 1/3:PER-CPU ONLINE/OFFLINE                       ###
###        Test Mode 2/3:GROUP-CPU ONLINE/OFFLINE                     ###
###        Test Mode 3/3:S3/S4 TEST WITH CPU0 ONLINED/OFFLINED        ###
#########################################################################

EOF

export ROOT=`(cd ../../../; pwd)`

. $ROOT/lib/functions.sh

#default cycle to run
ROUND=10

CPU=""
FIRST_CPU=0

WAKEUP_REC="ACPI: Waking up from system sleep state $1"
WAKEUP_REC2="Restarting tasks ... done."

online_cpu()
{
	echo 1 > /sys/devices/system/cpu/cpu$1/online
	sleep 1
	cat /proc/cpuinfo |grep ^processor |grep -w $1 1> /dev/null
	if [ $? -eq 0 ]
	then
		echo -e -n "CPU-$1/$MAX_CPU  online is OK\r" |tee -a $OUTPUT_LOG
	else
		echo "CPU$1 online is FAILED" |tee -a $OUTPUT_LOG
		grep -q -o "CPU$1" $FAILST || echo "CPU$1" >> $FAILST
	fi
}

offline_cpu()
{
	echo 0 > /sys/devices/system/cpu/cpu$1/online
	sleep 1
	cat /proc/cpuinfo |grep ^processor |grep -w $1  1> /dev/null
	if [ $? -ne 0 ]
	then
		echo -e -n "CPU-$1/$MAX_CPU offline is OK\r" |tee -a $OUTPUT_LOG
	else
		echo "CPU$1 offline is FAILED" |tee -a $OUTPUT_LOG
		grep -q -o "CPU$1" $FAILST || echo "CPU$1" >> $FAILST
	fi
}

per_cpu_test()
{
	echo -e "######################## PER-CPU ONLINE/OFFLINE #########################" | tee -a $BSP_LOG $OUTPUT_LOG
	echo -e "Execute per cpu (CPU0,...CPUx) offline/online operation in sequence\n" |tee -a $OUTPUT_LOG
	echo `date +%Y-%m-%d-%H.%M.%S` | tee -a $OUTPUT_LOG
	j=1
	while [ $j -le $ROUND ];do
		echo "------------------- round: $j/$ROUND --------------------" | tee -a $BSP_LOG $OUTPUT_LOG
		for CPU in `seq $FIRST_CPU $MAX_CPU`;do
			offline_cpu $CPU
			online_cpu $CPU
		done
		echo "						DONE" |tee -a $OUTPUT_LOG
		dmesg -c >> $BSP_LOG
		j=`expr $j + 1`
	done
}

group_cpu_test()
{
	echo -e "\n####################### GROUP-CPU ONLINE/OFFLINE ########################" | tee -a $BSP_LOG $OUTPUT_LOG
	echo -e "Execute cpu offline/online operation in group with one random cpu onlined\n" | tee -a $OUTPUT_LOG
	echo `date +%Y-%m-%d-%H.%M.%S` |tee -a $OUTPUT_LOG
	j=1
	while [ $j -le $ROUND ];do
		echo "------------------- round: $j/$ROUND --------------------" | tee -a $BSP_LOG $OUTPUT_LOG
		cpu_ran=`expr $RANDOM % $MAX_CPU + 1`
		#check whether CPU $cpu_ran is onlined
		online_cpu "$cpu_ran" 2>/dev/null && echo -e "random CPU$cpu_ran is onlined\n" | tee -a $OUTPUT_LOG
		for CPU in `seq $FIRST_CPU $MAX_CPU`;do
			if [ $CPU != $cpu_ran ];then
				offline_cpu $CPU
			fi
		done
		for CPU in `seq $FIRST_CPU $MAX_CPU`;do
			if [ $CPU != $cpu_ran ];then
				online_cpu $CPU
			fi
		done
		echo "						DONE" | tee -a $OUTPUT_LOG
		dmesg -c >> $BSP_LOG
		j=`expr $j + 1`
	done
}

check_cpu_onlined()
{
	cat /proc/cpuinfo |grep ^processor |grep -w $1  1> /dev/null
	if [ $? -eq 0 ]
	then
		echo -e "CPU$1 is onlined\n" | tee -a $OUTPUT_LOG
	else
		echo 1 > /sys/devices/system/cpu/cpu$1/online
		sleep 1
		cat /sys/devices/system/cpu/cpu$1/online |grep -w "1"  1> /dev/null
		if [ $? -eq 0 ];then
			echo -e "CPU$1 is onlined\n" | tee -a $OUTPUT_LOG
		else
			echo -e "CPU$1 can't be onlined\n" | tee -a $OUTPUT_LOG
			return 1
		fi
	fi
}

check_cpu_offlined()
{
	cat /proc/cpuinfo |grep ^processor |grep -w $1  1> /dev/null
	if [ $? -ne 0 ]
	then
		echo -e "CPU$1 is offlined\n" | tee -a $OUTPUT_LOG
	else
		echo 0 > /sys/devices/system/cpu/cpu0/online
		sleep 1
		cat /sys/devices/system/cpu/cpu$1/online |grep -w "0"  1> /dev/null
		if [ $? -eq 0 ];then
			echo -e "CPU$1 is offlined\n" | tee -a $OUTPUT_LOG
		else
			echo -e "CPU$1 can't be offlined\n" | tee -a $OUTPUT_LOG
			return 1
		fi
	fi
}

s3_s4_support_check()
{
	if [ Y$1 = Y"S3" ];then
		state=mem
	elif [ Y$1 = Y"S4" ];then
		state=disk
	fi
	grep -q -o $state /sys/power/state
	if [ $? -eq 0 ]
	then
		echo -e "\n$1 is supported by current kernel\n" | tee -a $OUTPUT_LOG
	else
		echo -e "\n$1 is not supported by current kernel\n" | tee -a $OUTPUT_LOG
		return 1
	fi
}

auto_wakeup_set()
{
	time=30
	pgrep rtcwake | xargs kill -9 &> /dev/null
	# Set wake up time after 30 second.
	rtcwake -s $time -m on &>/dev/null &
	# Give rtcwake some time to make its stuff
	sleep 5
}

s3_s4_test_onlined()
{
	echo ">>>>>>>>>>>>>>>>> Start $1 test with CPU0 ONLINED <<<<<<<<<<<<<<<<<<<<" | tee -a $BSP_LOG $OUTPUT_LOG
	#check whether CPU0 is onlined
	check_cpu_onlined "0"
	[ $? -eq 0 ] || return
	echo "System prepares to enter $1 right now..." | tee -a $OUTPUT_LOG
	# 1 second delay to let user see what will happen
	sleep 1
	#set time for auto resume from S3/S4
	auto_wakeup_set
	pm-$2
	if [ $? -eq 0 ];then
		echo "$1 action has completed" | tee -a $OUTPUT_LOG
		dmesg | grep -q "$WAKEUP_REC" || dmesg |grep -q "$WAKEUP_REC2"
		if [ $? -eq 0 ];then
			echo "system has resumed from $1 successfully" | tee -a $OUTPUT_LOG
			echo -e "<<<<<<<<<<<<<<<<< $1 test is PASSED with CPU0 ONLINED >>>>>>>>>>>>>>>>>>>\n" | tee -a $OUTPUT_LOG
		else
			echo "system has not resumed from $1 as expected" | tee -a $OUTPUT_LOG
			echo -e "<<<<<<<<<<<<<<<<<<<<<<<<<< $s test is FAILED >>>>>>>>>>>>>>>>>>>>>>>>>>>\n" | tee -a $OUTPUT_LOG
			return
		fi
	else
		echo "$1 action has not completed" | tee -a $OUTPUT_LOG
		echo -e "<<<<<<<<<<<<<<<<< $1 test is FAILED with CPU0 ONLINED >>>>>>>>>>>>>>>>>>\n" | tee -a $OUTPUT_LOG
		return
	fi
	dmesg -c >> $BSP_LOG
}

s3_s4_test_offlined()
{
	echo ">>>>>>>>>>>>>>>>> Start $1 test with CPU0 OFFLINED <<<<<<<<<<<<<<<<<<<" | tee -a $BSP_LOG $OUTPUT_LOG
	#check whether CPU0 is offlined
	check_cpu_offlined "0"
	[ $? -eq 0 ] && echo "System prepares to enter $1 right now..." | tee -a $OUTPUT_LOG || return
	# 1 second delay to let user see what will happen
	sleep 1
	#set time for auto resume from S3/S4
	auto_wakeup_set
	pm-$2
	if [ $? -eq 0 ];then
		echo "$1 action has completed" | tee -a $OUTPUT_LOG
		dmesg | grep -q "$WAKEUP_REC" || dmesg |grep -q "$WAKEUP_REC2"
		if [ $? -eq 0 ];then
			echo "system has resumed from $1 successfully" | tee -a $OUTPUT_LOG
			echo -e "<<<<<<<<<<<<<<<<< $1 test is FAILED with CPU0 OFFLINED >>>>>>>>>>>>>>>>>>\n" | tee -a $OUTPUT_LOG
			return
		else
			echo "system can't suspend to $1 as CPU0 is offlined" | tee -a $OUTPUT_LOG
			echo -e "<<<<<<<<<<<<<<<<< $1 test is PASSED with CPU0 OFFLINED >>>>>>>>>>>>>>>>>>\n" | tee -a $OUTPUT_LOG
		fi
	else
		echo "$1 action has not completed" | tee -a $OUTPUT_LOG
		echo -e "<<<<<<<<<<<<<<<<<<<<<<<<<< $s test is FAILED >>>>>>>>>>>>>>>>>>>>>>>>>>>\n" | tee -a $OUTPUT_LOG
		return
	fi
	dmesg -c >> $BSP_LOG
}

s3_s4_test()
{
	echo -e "\n################# S3/S4 test with CPU0 ONLINED/OFFLINED #################" | tee -a $BSP_LOG $OUTPUT_LOG
	echo -e "2 or 3 minutes are needed, please wait...\n" | tee -a $OUTPUT_LOG
	echo `date +%Y-%m-%d-%H.%M.%S` |tee -a $OUTPUT_LOG
	echo "NOTE: If the time during S3/S4 is longer than 30s on your
	platform, please repeat this test mode manually......" | tee -a $OUTPUT_LOG
	for s in S3 S4; do
		if [ Y$s = Y"S3" ];then
			cmd=suspend
		elif [ Y$s = Y"S4" ];then
			cmd=hibernate
		fi
		#check if S3/S4 is supported
		s3_s4_support_check $s
		if [ $? -eq 0 ];then
			s3_s4_test_onlined $s $cmd
			s3_s4_test_offlined $s $cmd
		fi
	done
}

cleanup()
{
	str="Test Mode 3\/3"
	if [ -n "$str" ];then
		# here ^M is one character. Press CTRL + v, release v and press m
		# if ^M is two characters (^ + M), it must be inputed as \^M
		sed  -i 's//\n/g' $OUTPUT_LOG
	else
		sed  -i '1,/Test Mode 3\/3/s//\n/g' $OUTPUT_LOG
	fi
	exit
}

trap "cleanup" 0 2 9 15
main()
{
	per_cpu_test
	group_cpu_test
	s3_s4_test
}
main
