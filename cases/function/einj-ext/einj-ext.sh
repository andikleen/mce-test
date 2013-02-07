#!/bin/bash

# Copyright (C) 2012, Intel Corp.
# This file is released under the GPLv2.

cat <<-EOF
###########################################################################
###   Section 1: Regular error injection with Correctable Memory Error  ###
###   Section 2: Vendor Extension Specific Error Injection              ###
###########################################################################

EOF

export ROOT=`(cd ../../../; pwd)`

. $ROOT/lib/functions.sh
setup_path
. $ROOT/lib/mce.sh


APEI_IF=""
GHES_REC="Hardware error from APEI Generic Hardware Error Source"
LOG_DIR=$ROOT/cases/function/einj-ext/log
LOG=$LOG_DIR/$(date +%Y-%m-%d.%H.%M.%S)-`uname -r`.log

mkdir -p $LOG_DIR
echo 0 > $TMP_DIR/error.$$

check_support()
{
	check_debugfs
	#if einj is a module, it is ensured to have been loaded
	modinfo einj &> /dev/null
	if [ $? -eq 0 ]; then
		modprobe einj
		[ $? -eq 0 ] ||
			die "module einj isn't supported or EINJ Table doesn't exist?"
	fi
	#APEI_IF should be defined after debugfs is mounted
	APEI_IF=`cat /proc/mounts | grep debugfs | cut -d ' ' -f2 | head -1`/apei/einj
	[ -d $APEI_IF ] ||
		die "einj isn't supported in the kernel or EINJ Table doesn't exist."

	[ -f $APEI_IF/vendor ] ||
		die "Does ACPI5.0 is enabled? Please check your BIOS settings!"
}

check_err_type()
{
	local type=`printf 0x%08x $1`

	cat $APEI_IF/available_error_type 2>/dev/null | cut -f1 | grep -q $type
	[ $? -eq 0 ] ||
	{
		echo "The error type \"$type\" is not supported on this platform" |tee -a $LOG
		return 1
	}
}

# On some machines the trigger will happen after 15 ~ 20 seconds, so
# when no proper log is read out, just execute wait-retry loop until
# timeout.
check_result()
{
	local timeout=25
	local sleep=5
	local time=0

	echo -e "Current OS/kernel version as follows:\n" >> $LOG
	uname -a >> $LOG
	cat /etc/issue >> $LOG
	echo -e "\ndmesg information as follows:\n" >> $LOG
	dmesg  -c &>> $LOG
	echo -e "\nmcelog information as follows:\n" >> $LOG
	mcelog &>> $LOG
	while [ $time -lt $timeout ]
	do
		grep -q "$GHES_REC" $LOG
		[ $? -eq 0 ] && return 0
		time=`expr $time + $sleep`
	done
	return 1
}

einj_inj()
{
	echo -e "====== Section 1: Regular EINJ Injection with Memory Correctable Error =====\n" |tee -a $LOG

	dmesg -c > /dev/null
	#inject error type
	local type=0x8
	check_err_type $type
	[ $? -ne 0 ] && return 1
	mcelog &> /dev/null
	echo $type > $APEI_IF/error_type
	killall simple_process > /dev/null 2>&1
	#killall simple_process &> /dev/null
	simple_process > /dev/null &

	page-types -p `pidof simple_process` -LN -b ano > $TMP_DIR/pagelist.$$

	ADDR=`awk '$2 != "offset" {print "0x"$2"000"}' $TMP_DIR/pagelist.$$ | sed -n -e '1p'`
	if [ -f $APEI_IF/param1 ]
	then
		echo $ADDR > $APEI_IF/param1
		echo 0xfffffffffffff000 > $APEI_IF/param2
	fi

	echo "1" > $APEI_IF/error_inject
	[ $? -ne 0 ] &&
	{
		cat <<-EOF

		***************************************************************************
		Error injection fails. It is possible to happen on bogus BIOS. For example,
		some iomem region can't be acquired when requesting some resources.
		For detail log information please refer to the following file:
		$LOG
		***************************************************************************

		EOF
	} && echo 1 > $TMP_DIR/error.$$
	sleep 1

	check_result
	if [ $? -eq 0 ]
	then
		echo -e "\nEINJ Injection: GHES record is OK" |tee -a $LOG
		echo 0 >> $TMP_DIR/error.$$
		return
	else
		echo -e "\nEINJ Injection: GHES record is not expected" |tee -a $LOG
		echo 1 > $TMP_DIR/error.$$
		return 1
	fi
}

vendor_inj()
{
	echo -e "\n====== Section 2: Vendor Extension Specific Error Injection ==============\n" |tee -a $LOG
	echo -e "Vendor Information as follows:\n" >> $LOG
	cat $APEI_IF/vendor >> $LOG
	if [ $? -ne 0 ]
	then
		cat <<-EOF

		Your platform supports ACPI5.0 extension for EINJ but your BIOS
		is bogus so that EINJ test fails. Please refer to output
		information above. For detail information please see following file:
		$LOG

		EOF
	else
		echo "Vendor Extension: Vendor information check is OK" |tee -a $LOG
	fi
	echo -e "\nThis test is not available by now. Just skip it.\n" |tee -a $LOG
}

main()
{
	check_support
	einj_inj
	vendor_inj
	grep -q "1" $TMP_DIR/error.$$
	if [ $? -eq 0 ]
	then
		echo -e "\nTest FAILED\n"
		exit 1
	else
		echo -e "\nTest PASSED\n"
		exit 0
	fi
}
main
