#!/bin/bash

#set -x
export ROOT=`(cd ../../../; pwd)`

. $ROOT/lib/functions.sh
setup_path
. $ROOT/lib/mce.sh

inject_type=0x00000010
EDAC_TYPE=""

invalid()
{
	echo $*
	exit 1
}

apei_inj()
{
	echo $inject_type > $g_debugfs/apei/einj/error_type
	echo $1 > $g_debugfs/apei/einj/param1
	echo 0xfffffffffffff000 > $g_debugfs/apei/einj/param2
	echo 1 > $g_debugfs/apei/einj/notrigger
	echo 1 > $g_debugfs/apei/einj/error_inject
}

print_usage()
{
	echo -e "usage:
\t./srar_recovery.sh -d\t\tDCU error injection under user context
\t./srar_recovery.sh -i\t\tIFU error injection under user context"
}

if [ "$1" != "-d" -a "$1" != "-i" ]; then
	print_usage
	exit 1
fi
check_debugfs

g_debugfs=`cat /proc/mounts | grep debugfs | cut -d ' ' -f2 | head -1`
#if einj is not builtin, just insmod it
if [ ! -d $g_debugfs/apei/einj ]; then
	#if einj is a module, it is ensured to have been loaded
	modprobe einj param_extension=1 > /dev/null 2>&1
	[ $? -eq 0 ] || invalid "module einj isn't supported?"
fi
[ -f $g_debugfs/apei/einj/param1 ] || invalid "No BIOS extension support for APEI on this platform"
[ -f $g_debugfs/apei/einj/notrigger ] ||
	invalid "No parameter *notrigger*. Injection maybe causes system crash. Please check commit v3.3-3-gee49089"

#check if the platform supports Uncorrectable non-fatal Memory Error injection
cat $g_debugfs/apei/einj/available_error_type | grep -q $inject_type
if [ $? -ne 0 ]; then
	invalid "Uncorrectable non-fatal Memory Error is not supported"
fi

# remove possible EDAC module, otherwise, the error information will be ate
# by EDAC module and mcelog will not get it.
# By now, only i7core_edac and sb_edac hook into the mcelog kernel buffer
if cat /proc/modules | grep -q i7core_edac; then
	EDAC_TYPE="i7core_edac"
elif cat /proc/modules | grep -q sb_edac; then
	EDAC_TYPE="sb_edac"
elif cat /proc/modules | grep -q skx_edac; then
	EDAC_TYPE="skx_edac"
fi
rmmod $EDAC_TYPE >/dev/null 2>&1

[ -e $ROOT/bin/victim ] || invalid "file victim doesn't exist!" \
"maybe you forget to execute make install under directory $ROOT before test"
killall victim > /dev/null 2>&1
touch trigger
tail -f trigger --pid=$$ | victim $1 > log &
sleep 1
addr=`cat log |cut -d' '  -f6|head -1`
apei_inj $addr
sleep 1
echo go > trigger
sleep 5
rm -f trigger log
id=`pgrep victim`
if [ X"$id" != X ]; then
	echo $id | xargs kill -9 > /dev/null 2>&1
	invalid "The poisoned process can't be killed by kernel automatically. Test fails!"
fi

if [ $1 == "-d" ]; then
	echo "SRAR/DCU test passes!"
elif [ $1 == "-i" ]; then
	echo "SRAR/IFU test passes!"
fi

