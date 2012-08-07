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

	while [ $time -lt $timeout ]
	do
		dmesg -c | grep -q "$GHES_REC"
		[ $? -eq 0 ] && return 0
		time=`expr $time + $sleep`
	done

	return 1
}

main()
{
	#inject error type
	local type=$1

	check_debugfs
	#APEI_IF should be defined after debugfs is mounted
	APEI_IF=`cat /proc/mounts | grep debugfs | cut -d ' ' -f2 | head -1`/apei/einj

	#if einj is a module, it is ensured to have been loaded
	modinfo einj > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		[ -d $APEI_IF ] || modprobe einj param_extension=1
		[ $? -eq 0 ] ||
		die "module einj isn't supported or EINJ Table doesn't exist?"
	fi

	check_err_type $type
	[ $? -ne 0 ] && return 1

	mcelog &> /dev/null
	echo $type > $APEI_IF/error_type
	killall simple_process > /dev/null 2>&1
	simple_process > /dev/null &

	page-types -p `pidof simple_process` -LN -b ano > $TMP_DIR/pagelist.$$

	ADDR=`awk '$2 != "offset" {print "0x"$2"000"}' $TMP_DIR/pagelist.$$ | sed -n -e '1p'`
	if [ -f $APEI_IF/param1 ]
	then
		echo $ADDR > $APEI_IF/param1
		echo 0xfffffffffffff000 > $APEI_IF/param2
	fi

	dmesg -c > /dev/null
	echo "1" > $APEI_IF/error_inject 2>/dev/null
	[ $? -ne 0 ] &&
	{
		cat <<-EOF

		Error injection fails, it maybe happens on some
		bogus BIOS. For example, some iomem region can't
		be acquired when requesting some resources. Please
		contact BIOS engineer to get further information.

		EOF
	}
	sleep 1

	check_result
	if [ $? -eq 0 ]
	then
		echo "  PASSED: GHES record is ok"
		exit 0
	else
		echo "  FAILED: GHES record is not expected"
		exit 1
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
