#!/bin/sh

. ../../../lib/mce.sh

INJ_TYPE=0x00000008
APEI_IF=""
PFA_BIN=""

invalid()
{
	echo $*
	exit 1
}

apei_inj()
{
	echo $INJ_TYPE > $APEI_IF/error_type
	echo $1 > $APEI_IF/param1
	echo 0xfffffffffffff000 > $APEI_IF/param2
	echo 1 > $APEI_IF/error_inject
}

usage()
{
	cat <<-EOF
	usage: ${0##*/} [PFA program] [trigger interval time]
	example: ${0##*/} ./pfa 10

	EOF
}

main()
{
	if [ X"$1" = X -o X"$2" = X ]
	then
		usage
		exit 0
	fi

	PFA_BIN=$1
	check_debugfs

	APEI_IF=`cat /proc/mounts | grep debugfs | cut -d ' ' -f2 | head -1`/apei/einj

	#if einj is not builtin, just insmod it
	if [ ! -d $APEI_IF ]; then
		#if einj is a module, it is ensured to have been loaded
		modprobe einj param_extension=1 > /dev/null 2>&1
		[ $? -eq 0 ] || invalid "module einj isn't supported?"
	fi
	[ -f $APEI_IF/param1 ] ||
	invalid "no BIOS extension support for APEI on this platform"

	#check if the platform supports Correctable Memory Error injection
	cat $APEI_IF/available_error_type | grep -q $INJ_TYPE
	[ $? -ne 0 ] &&
	invalid "Necessary Error Injection for PFA is not supported on this platform"

	killall $PFA_BIN > /dev/null 2>&1
	$PFA_BIN | tee log &
	#wait to flush stdout into log
	sleep 1
	addr=`cat log |cut -d' '  -f8|tail -1`
	last_addr=$addr
	while :
	do
		echo inject address = $addr
		apei_inj $addr
		sleep $2
		addr=`cat log |cut -d' '  -f8|tail -1`
		if [ X"$last_addr" != X"$addr" ]
		then
			break
		fi
	done
}

cleanup()
{
	rm -f trigger log
}

trap "cleanup" 0
main "$@"
