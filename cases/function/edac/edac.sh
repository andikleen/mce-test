#!/bin/bash

# This test is used for verifying EDAC driver by checking if its output can
# keep correct under different kernel release via comparing against a reference
# result run earlier or on earlier kernel version, which saved in a file, named
# as 'edac_ref_file'.
# Here we only do memory error injection check for EDAC driver.
# When inject CE memory error and consume it on some specific addresses that
# saved in the above reference file, if the EDAC related dmesg output is same
# as the relative content of the reference file, we call the test is PASS,
# otherwise call it FAIL. If the reference file doesn't exist, this script
# will generate it and exit test, you need to re-run the script to complete
# the test.
# If memory configuration on the SUT platform is changed, you need to delete the
# original reference file and re-generate it.

export ROOT=`(cd ../../../; pwd)`
. $ROOT/lib/functions.sh
setup_path
. $ROOT/lib/mce.sh

EDAC_DIR=$ROOT/cases/function/edac
LOG_DIR=$EDAC_DIR/log
EDAC_REF_FILE=$EDAC_DIR/edac_ref_file
MEM_CONF_FILE=$EDAC_DIR/mem_conf_file
EINJ_IF=""
LOG_FILE=$LOG_DIR/$(date +%Y-%m-%d.%H.%M.%S)-`uname -r`.log
# memory CE error
ERR_TYPE=0x8
URANDOM=0
PAGESIZE=4096
# Lots of addresses to be injected, actually it is a number of
# tested addresses during each iomem range, e.g.,if 3 iomem ranges
# are used, the total number will be $NUM_TESTADDR * 3 .
NUM_TESTADDR=100
NUM_TOSAVE=20
COUNT_FAIL=0
RANGE_SIZE_THR=500
declare -a LINE_REC

check_support()
{
	check_debugfs
	modinfo einj &> /dev/null
	if [ $? -eq 0 ]; then
		modprobe einj param_extension=1
		[ $? -eq 0 ] ||
			die "module einj is not supported?"
	fi
	lsmod | grep -q edac
	[ $? -eq 0 ] ||
		die "EDAC related modules aren't found."
	EINJ_IF=`cat /proc/mounts | grep debugfs | cut -d ' ' -f2 | head -1`/apei/einj
	if [ ! -d $EINJ_IF ]; then
		die "einj isn't supported, please check your bios setting"
	fi
}

save_memconf()
{
	# save memory configuration on the platform for comparison
	dmidecode -t 17 > $MEM_CONF_FILE
}

get_random()
{
	# get a random number greater than 32767
	URANDOM=`od -An -N4 -t uL /dev/urandom | tr -d " "`
}

# avoid selecting address at the same line
check_same_value()
{

	for i in `seq 0 $(($1 - 1))`
	do
		if [ $2 -eq ${LINE_REC[$i]} ]; then
			return 1
		fi
	done
	return 0
}

save_edac_info()
{
	local lines
	local rand_line
	local tmpfile=$(mktemp)
	local saved=0

	lines=`cat edac_mesg | grep "EDAC.*CE.*page:" | wc -l`
        if [ $lines -eq 0 ]; then
                echo "Fail: can't found EDAC related information"
                exit 1
        fi
	echo "Kernel Version: `uname -r`" >> $EDAC_REF_FILE
	echo -e "Created Date: `date`\n" >> $EDAC_REF_FILE
	cat edac_mesg | grep "EDAC.*CE.*page:" > $tmpfile
	while [ $saved -lt $NUM_TOSAVE ]
	do
		get_random
		rand_line=$(($URANDOM % $lines))
		if [ $rand_line -eq 0 ]; then
                        rand_line=1
                fi
		if [ $saved -eq 0 ]; then
			LINE_REC[$saved]=$rand_line
			let "saved += 1"
			sed -n "${rand_line}p" $tmpfile >> $EDAC_REF_FILE
			continue
		fi
		check_same_value $saved $rand_line
		[ $? -eq 1 ] && continue
		LINE_REC[$saved]=$rand_line
		let "saved += 1"
		sed -n "${rand_line}p" $tmpfile >> $EDAC_REF_FILE
	done
	rm -f $tmpfile
}

inject_lot_ce()
{
	local start_addr
	local end_addr
	local rand_addr
	local test_pfn
	local test_addr

	dmesg -c &> /dev/null
	: > edac_mesg
	echo $ERR_TYPE > $EINJ_IF/error_type
	echo 0xfffffffffffff000 > $EINJ_IF/param2
	echo 0x0 > $EINJ_IF/notrigger
	get_random
	cat /proc/iomem | grep "System RAM" | cut -d ':' -f1 > iomem_tmp
	echo "Inject a lot of CE memory errors into some of the following addresses:"
	while read line
	do
		start_addr=`echo $line | awk -F '-' '{print "0x"$1}'`
		end_addr=`echo $line | awk -F '-' '{print "0x"$2}'`
		# pick address greater than or equal to 0x100000
		[[ $start_addr -lt 0x100000 ]] && continue
		# skip injecting error into small memory areas(<500MB)
		[[ $(($end_addr - $start_addr)) -lt $(($RANGE_SIZE_THR * 0x100000)) ]] && continue
		printf "0x%016lx - 0x%016lx\n" $start_addr $end_addr
		rand_addr=$(($start_addr + $URANDOM % ($end_addr - $start_addr)))
		if [[ $(($rand_addr + $NUM_TESTADDR * $PAGESIZE)) -gt $end_addr ]]; then
			rand_addr=$(printf "0x%lx" $start_addr)
		fi
		for i in `seq 1 $NUM_TESTADDR`
		do
			let "test_pfn = $rand_addr / $PAGESIZE + $i"
			test_addr=$(printf "0x%lx" $test_pfn)"000"
			[[ $test_addr -gt $end_addr ]] && break
			echo $test_addr > $EINJ_IF/param1
			echo 1 > $EINJ_IF/error_inject
			dmesg -c >> edac_mesg
		done
	done < iomem_tmp
	# avoid some messages coming later
	sleep 1
	dmesg -c >> edac_mesg
	save_edac_info
	save_memconf
}

inject_spec_addr()
{
	local addr

	dmesg -c &> /dev/null
	echo $ERR_TYPE > $EINJ_IF/error_type
	echo 0xfffffffffffff000 > $EINJ_IF/param2
	echo 0x0 > $EINJ_IF/notrigger
	while read line
	do
		# check only EDAC related information
		echo "$line" | grep -q EDAC
		[ $? -ne 0 ] && continue
		addr=$(echo "$line" | grep -o "page:0x[a-f0-9]*" | cut -d':' -f2)"000"
		#printf "addr=0x%x\n" $addr
		echo $addr > $EINJ_IF/param1
		echo 1 > $EINJ_IF/error_inject
		check_result "$line"
	done < $EDAC_REF_FILE
}

check_result()
{
	local addr
	local tmpstr
	local edac_str

	addr=$(echo "$@" | grep -o "page:0x[a-f0-9]*" | cut -d':' -f2)"000"
	tmpstr="$@"
	# remove timestamp in head of each line
	edac_str=${tmpstr#\[*.*\] }
	dmesg | grep -q "$edac_str"
	if [ $? -ne 0 ]; then
		# re-check it to avoid later coming message
		sleep 1
		dmesg | grep -q "$edac_str"
		if [ $? -eq 0 ]; then
			printf "0x%016lx PASS\n" $addr | tee -a $LOG_FILE
		else
			printf "0x%016lx FAIL\n" $addr | tee -a $LOG_FILE
			let "COUNT_FAIL += 1"
		fi
	else
		printf "0x%016lx PASS\n" $addr | tee -a $LOG_FILE
	fi
	echo -e "\nEDAC dmesg output as below:\n" >> $LOG_FILE
	dmesg -c >> $LOG_FILE
	echo >> $LOG_FILE
}

check_mem_conf()
{
	local tmpfile=$(mktemp)
	dmidecode -t 17 > $tmpfile
	diff -q $tmpfile $MEM_CONF_FILE &> /dev/null
	if [ $? -eq 0 ]; then
		rm -f $tmpfile
		return 0
	else
		rm -f $tmpfile
		return 1
	fi
}

cleanup()
{
	rm -f iomem_tmp
	rm -f edac_mesg
}

trap "cleanup" 0 2 9 15
main()
{
	if [ `id -u` -ne 0 ]; then
		echo "Must be run as root"
	fi
	check_support
	if [ ! -e $EDAC_REF_FILE ]; then
		echo "---------------------------------------------------"
		echo "Reference result doesn't exist, wait to generate..."
		echo "---------------------------------------------------"
		inject_lot_ce
		echo "----------------------------------------------------------------------------"
		echo "Reference result is already generated, please go test via re-running the script!"
		echo "----------------------------------------------------------------------------"
		exit 1
	fi
	check_mem_conf
	[ $? -eq 0 ] || \
		die "memory configuration changed, please delete '$EDAC_REF_FILE', then re-run the test."
	mkdir -p $LOG_DIR
	echo -e "\nKernel Version: `uname -r`\n" | tee -a $LOG_FILE
	echo -e "Test all addresses in EDAC reference file...\n" | tee -a $LOG_FILE
	inject_spec_addr
	if [ $COUNT_FAIL -gt 0 ]; then
		echo -e "\nTest FAIL\n" | tee -a $LOG_FILE
	else
		echo -e "\nTest PASS\n" | tee -a $LOG_FILE
	fi
	echo "More detail please check log in $LOG_FILE"
}
main
