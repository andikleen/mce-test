# Copyright (C) 2014, Intel Corp.
# This file is released under the GPLv2.
#
#
export ROOT=`(cd ../../../; pwd)`

. $ROOT/lib/functions.sh
setup_path
. $ROOT/lib/mce.sh

APEI_IF=""
eMCA_REC="DIMM location:"
LOG_DIR=$ROOT/cases/function/emca-inj/log
LOG=$LOG_DIR/$(date +%Y-%m-%d.%H.%M.%S)-`uname -r`.log

check_err_type()
{
	local type=`printf 0x%08x $1`

	cat $APEI_IF/available_error_type 2>/dev/null | cut -f1 | grep -q $type
	[ $? -eq 0 ] ||
	{
		echo "The error type \"$1\" is not supported on this platform"
		return 1
	}
}

# On some machines the trigger will be happend after 15 ~ 20 seconds, so
# when no proper log is read out, just executing wait-retry loop until
# timeout.
check_result()
{
	local timeout=25
	local sleep=5
	local time=0

	echo -e "<<< kernel version is as below >>>\n" >> $LOG
	uname -a >> $LOG
	cat /etc/issue >> $LOG
	echo -e "\n<<< dmesg is as below >>>\n" >> $LOG
	dmesg -c >> $LOG 2>&1
	while [ $time -lt $timeout ]
	do
		grep -q "$eMCA_REC" $LOG
		if [ $? -eq 0 ]
		then
			echo -e "\neMCA record is OK\n" |tee -a $LOG
			echo 0 > $TMP_DIR/emca.$$
			return
		fi
		sleep $sleep
		time=`expr $time + $sleep`
	done
	echo -e "\neMCA record is not expected\n" |tee -a $LOG
	echo 1 > $TMP_DIR/emca.$$
}

clean_up_eMCA()
{
	rmmod acpi_extlog &> /dev/null
	rmmod einj &> /dev/null
}

main()
{
	local ret
	#error type
	local type=$1

	echo 0 > $TMP_DIR/emca.$$
	mkdir -p $LOG_DIR
	dmesg -c > /dev/null

	check_debugfs
	APEI_IF=`cat /proc/mounts | grep debugfs | cut -d ' ' -f2 | head -1`/apei/einj
	if [ ! -d $APEI_IF ]; then
		modprobe einj param_extension=1
		if [ $? -ne 0 ];then
			clean_up_eMCA
			die "module einj isn't supported or EINJ Table doesn't exist?"
		fi
	fi
	check_eMCA_config
	check_err_type $type
	[ $? -ne 0 ] && return 1
	sleep 2
	echo $type > $APEI_IF/error_type
	killall simple_process &> /dev/null
	simple_process > /dev/null &
	page-types -p `pidof simple_process` -LN -b ano > $TMP_DIR/pagelist.$$

	ADDR=`awk '$2 != "offset" {print "0x"$2"000"}' $TMP_DIR/pagelist.$$ | sed -n -e '1p'`
	if [ -f $APEI_IF/param1 ]
	then
		echo $ADDR > $APEI_IF/param1
		echo 0xfffffffffffff000 > $APEI_IF/param2
		echo 1 > $APEI_IF/notrigger
	else
		clean_up_eMCA
		die "$APEI_IF/param'1-2' are missed! Ensure your BIOS supporting it and enabled."
	fi

	echo 1 > $APEI_IF/error_inject
	if [ $? -ne 0 ]; then
		cat <<-EOF
		Error injection fails. It may happens because of bogus BIOS. For detail
		information please refer to following file:
		$LOG

		EOF
		clean_up_eMCA
		return 1
	fi

	sleep 1
	check_result
	grep -q "0" $TMP_DIR/emca.$$
	ret=$?
	clean_up_eMCA
	if [ $ret -ne 0 ]
	then
		echo -e "\nTest FAILED\n"
	else
		echo -e "\nTest PASSED\n"
	fi
	return $ret
}

usage()
{
	cat <<-EOF
	usage: ${0##*/} [ available_error_type ]
	example: ${0##*/} [ only support 0x8 injection ]

	EOF

	exit 0
}

[ $# -eq 0 ] && usage

main $1
