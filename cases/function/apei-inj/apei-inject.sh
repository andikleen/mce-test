# Copyright (C) 2012, Intel Corp.
# This file is released under the GPLv2.
#
#
export ROOT=`(cd ../../../; pwd)`

. $ROOT/lib/functions.sh
setup_path
. $ROOT/lib/mce.sh

APEI_IF=""
GHES_REC="Hardware error from APEI Generic Hardware Error Source"
LOG_DIR=$ROOT/cases/function/apei-inj/log
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

	echo -e "<<< OS/kernel version is as follows >>>\n" >> $LOG
	uname -a >> $LOG
	cat /etc/os-release >> $LOG
	echo -e "\n<<< dmesg information is as follows >>>\n" >> $LOG
	while [ $time -lt $timeout ]
	do
		dmesg -c >> $LOG 2>&1
		grep -q "$GHES_REC" $LOG
		if [ $? -eq 0 ]
		then
			echo -e "\nGHES record is OK\n" |tee -a $LOG
			echo 0 >> $TMP_DIR/error.$$
			return
		fi
		sleep $sleep
		time=`expr $time + $sleep`
	done
	echo -e "\nGHES record is not expected\n" |tee -a $LOG
	echo 1 > $TMP_DIR/error.$$
	return 1
}

main()
{
	echo 0 > $TMP_DIR/error.$$
	mkdir -p $LOG_DIR
	dmesg -c > /dev/null
	#inject error type
	local type=$1

	check_debugfs
	#if einj is a module, it is ensured to have been loaded
	modinfo einj &> /dev/null
	if [ $? -eq 0 ]; then
		modprobe einj param_extension=1
		[ $? -eq 0 ] ||
			die "module einj isn't supported or EINJ Table doesn't exist?"
	fi
	#APEI_IF should be defined after debugfs is mounted
	APEI_IF=`cat /proc/mounts | grep debugfs | cut -d ' ' -f2 | head -1`/apei/einj
	[ -d $APEI_IF ] ||
		die "einj isn't supported in the kernel or EINJ Table doesn't exist."

	check_err_type $type
	[ $? -ne 0 ] && return 1

	echo $type > $APEI_IF/error_type

	killall victim &> /dev/null
	touch trigger
	tail -f trigger --pid=$$ | victim -d > $TMP_DIR/pagelist.$$ &
	sleep 1
	ADDR=`cat $TMP_DIR/pagelist.$$ | awk '{print $NF}' | head -n 1`
	if [ -f $APEI_IF/param1 ]
	then
		echo $ADDR > $APEI_IF/param1
		echo 0xfffffffffffff000 > $APEI_IF/param2
		echo 1 > $APEI_IF/notrigger
	else
		killall victim &> /dev/null
		rm -f trigger
		die "$APEI_IF/param'1-2' are missed! Ensure your BIOS supporting it and enabled."
	fi

	echo "1" > $APEI_IF/error_inject
	[ $? -ne 0 ] &&
	{
		cat <<-EOF

		Error injection fails. It maybe happens on some bogus BIOS. For example,
		some iomem region can't be acquired when requesting some resources.
		For detail information please refer to the following file:
		$LOG

		EOF
		killall victim &> /dev/null
		rm -f trigger
		echo 1 > $TMP_DIR/error.$$
		echo -e "\nTest FAILED\n"
		exit 1
	}
	sleep 1
	echo go > trigger
	sleep 3

	check_result
	killall victim &> /dev/null
	rm -f trigger
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

usage()
{
	cat <<-EOF
	usage: ${0##*/} [ available_error_type ]
	example: ${0##*/} [ 0x8 | 0x10 | 0x20 | ... ]

	EOF

	exit 0
}

[ $# -eq 0 ] && usage

main $1
