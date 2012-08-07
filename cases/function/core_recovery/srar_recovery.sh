#!/bin/sh

#set -x
export ROOT=`(cd ../../../; pwd)`

. $ROOT/lib/mce.sh

inject_type=0x00000010

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
[ -f $g_debugfs/apei/einj/param1 ] || invalid "no BIOS extension support for APEI on this platform"

#check if the platform supports Uncorrectable non-fatal Memory Error injection
cat $g_debugfs/apei/einj/available_error_type | grep -q $inject_type
if [ $? -ne 0 ]; then
	invalid "Uncorrectable non-fatal Memory Error is not supported"
fi

touch trigger
tail -f trigger | ./core_recovery $1 > log &
addr=`cat log |cut -d' '  -f6|head -1`
apei_inj $addr
sleep 1
echo go > trigger
sleep 2
rm -f trigger log
pgrep core_recovery > /dev/null 2>&1 | xargs kill -9 > /dev/null 2>&1
[ $? -eq 0 ] && invalid "The poisoned process can't be killed by kernel. Test fails!"

if [ $1 == "-d" ]; then
	echo "SRAR/DCU test passes!"
elif [ $1 == "-i" ]; then
	echo "SRAR/IFU test passes!"
fi

