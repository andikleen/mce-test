#! /bin/bash
#
# Stress test driver for Linux MCA High Level Handlers
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public
# License as published by the Free Software Foundation; version
# 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should find a copy of v2 of the GNU General Public License somewhere
# on your Linux system; if not, write to the Free Software Foundation, 
# Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA 
#
# Copyright (C) 2009, Intel Corp.
# Author: Haicheng Li <haicheng.li@intel.com>
#

#set -x

DEBUG=0

silent_exec()
{
	local cmd=$@

	if [ $DEBUG -eq 0 ]; then
		$cmd > /dev/null 2>&1
	else
		$cmd
	fi
	return $?
}

silent_exec_background()
{
	local cmd=$@

	if [ $DEBUG -eq 0 ]; then
		$cmd > /dev/null 2>&1 & 
	else
		$cmd & 
	fi
	return $?
}

_print()
{
	echo $* > $g_tty
}

dbp()
{
	[ $DEBUG -ne 1 ] && return
	_print -en "\\033[0;33m" # set font color as yellow
	_print "[debug] $*" > $g_tty
	echo "[debug] $*" >> $g_logfile
	_print -en "\\033[0;39m"    # restore font color to normal
}

log()
{
	_print -en "\\033[0;33m" # set font color as yellow
	_print "[info] $*" > $g_tty
	echo "[info] $*" >> $g_logfile
	_print -en "\\033[0;39m"    # restore font color to normal
}

begin()
{
	_print -n "$*" > $g_tty
	_print -en "\\033[0;32m" # set font color as green
	_print -e "\t [start]" > $g_tty
	echo -e "$* \t [start]" >> $g_logfile
	_print -en "\\033[0;39m"    # restore font color to normal
}

end()
{
	_print -n "$*" > $g_tty
	_print -en "\\033[0;32m" # set font color as green
	_print -e "\t [done]" > $g_tty
	echo -e "$* \t [done]" >> $g_logfile
	_print -en "\\033[0;39m"    # restore font color to normal
}

err()
{
	_print -en "\\033[0;31m" # set font color as red
	echo > $g_tty
	echo "Test aborted by unexpected error!" > $g_tty
	_print "[error] !!! $* !!!" > $g_tty
	echo > $g_tty
	echo "Test aborted by unexpected error!" >> $g_result 
	echo "[error] !!! $* !!!" >> $g_result 
	echo "[error] !!! $* !!!" >> $g_logfile 
	_print -en "\\033[0;39m"    # restore font color to normal
	exit 1
}

invalid()
{
	_print -en "\\033[0;31m" # set font color as red
	echo > $g_tty
	echo "Test aborted by unexpected error!" > $g_tty
	_print "[error] !!! $* !!!" > $g_tty
	echo > $g_tty
	echo "Try \`./hwposion -h\` for more information." > $g_tty
	echo > $g_tty
	echo "Test aborted by unexpected error!" >> $g_result 
	echo "[error] !!! $* !!!" >> $g_result 
	echo "[error] !!! $* !!!" >> $g_logfile 
	_print -en "\\033[0;39m"    # restore font color to normal
	exit 0
}

result()
{
	_print -en "\\033[0;34m" # set font color as blue
	_print -e "$*" > $g_tty
	echo -e "$*" >> $g_result 
	echo -e "$*" >> $g_logfile
	_print -en "\\033[0;39m"    # restore font color to normal
}

setup_meminfo()
{
	local maxmem=0
	local lowmem_s=0
	local lowmem_e=0
	local highmem_s=0
	local highmem_e=0
	local tmp=

	lowmem_s=`printf "%i" 0x100000`	# start pfn of mem < 4G
	let "g_lowmem_s=$lowmem_s / $g_pgsize"
	tmp=`cat /proc/iomem | grep  "System RAM" | grep 100000- | awk -F "-" '{print $2}' | awk '{print $1}'`
	lowmem_e=`printf "%i" "0x$tmp"`
	let "g_lowmem_e=$lowmem_e / $g_pgsize"
	log "low mem: 0x100000 (pfn: $g_lowmem_s) ~ 0x$tmp (pfn: $g_lowmem_e)"

	highmem_s=`printf "%i" 0x100000000`	# start pfn of highmem > 4G
	let "g_highmem_s=$highmem_s / $g_pgsize"
	tmp=`cat /proc/iomem | grep  "System RAM" | grep 100000000- | awk -F "-" '{print $2}' | awk '{print $1}'`
	highmem_e=`printf "%i" "0x$tmp"`
	let "g_highmem_e=$highmem_e / $g_pgsize"
	log "high mem: 0x100000000 (pfn: $g_highmem_s) ~ 0x$tmp (pfn: $g_highmem_e)"

	maxmem=`cat /proc/meminfo | grep MemTotal | awk '{print $2}'`
	let "g_maxpfn= $maxmem / 4"
	log "max pfn number: g_maxpfn = $g_maxpfn"
}

setup_errinj()
{
	local debugfs="/sys/kernel/debug"
	local dev_major=
	local dev_minor=
	local rc=0

	if [ $g_madvise -eq 1 ]; then
		[ -f "$debugfs/hwpoison/corrupt-filter-enable" ] && echo 0 > $debugfs/hwpoison/corrupt-filter-enable
		return
	else
		[ -f "$debugfs/hwpoison/corrupt-filter-enable" ] && echo 1 > $debugfs/hwpoison/corrupt-filter-enable
	fi	
	if [ $g_netfs -eq 0 ]; then
		dev_major=0x`/usr/bin/stat --format=%t $g_dev` > /dev/null 2>&1
		[ $? -ne 0 ] && rc=1	
		dev_minor=0x`/usr/bin/stat --format=%T $g_dev` > /dev/null 2>&1
		[ $? -ne 0 ] && rc=1	
		[ $rc -eq 1 ] && err "invalid device: no inode # can be found"
	else
		dev_major=0
		dev_minor=0
	fi
	echo $dev_major > $debugfs/hwpoison/corrupt-filter-dev-major
	echo $dev_minor > $debugfs/hwpoison/corrupt-filter-dev-minor
	[ $g_pgtype = "all" -a -f "$debugfs/hwpoison/corrupt-filter-flags-mask" ] && echo 0 > $debugfs/hwpoison/corrupt-filter-flags-mask
	[ -f "$debugfs/hwpoison/corrupt-filter-enable" ] && echo 1 > $debugfs/hwpoison/corrupt-filter-enable
	return
}

setup_fs()
{
	mkdir -p $g_testdir
	if [ $g_nomkfs -eq 0 -a $g_netfs -eq 0 ]; then 
		silent_exec which mkfs.$g_fstype || err "mkfs: unsupported fstype: $g_fstype"
		if [ $g_force -eq 0 ]; then
			echo -n "test will format $g_dev to $g_fstype, continue [y/n]? "
			read in
			[ $in = 'y' -o $in = "yes" -o $in = 'Y' ] || err "mkfs.$g_fstype on $g_dev is cancelled"
		fi
		begin "-- mkfs.$g_fstype $g_dev" 
		if [ $g_fstype = "vfat" -o $g_fstype = "msdos" ]; then
			silent_exec mkfs.$g_fstype $g_dev || err "cannot mkfs.$g_fstype on $g_dev"
		else
			silent_exec mkfs.$g_fstype -q $g_dev || err "cannot mkfs.$g_fstype on $g_dev"
		fi
		end "-- mkfs.$g_fstype $g_dev" 
	fi
	silent_exec mount -t $g_fstype $g_dev $g_testdir || err "cannot mount $g_fstype fs: $g_dev to $g_testdir"	
}

check_env()
{
	local debugfs="/sys/kernel/debug"

	silent_exec mount -t debugfs null $debugfs 
	[ -z "$g_tty" ] && invalid "$g_tty does not exist"
	[ -z "$g_dev" ] && invalid "device is not specified"
	if [ $g_fstype = "nfs" -o $g_fstype = "cifs" ]; then
		g_netfs=1
	else
		[ -b $g_dev ] || invalid "invalid device: $g_dev"
	fi
	df | grep $g_dev > /dev/null 2>&1 && err "device $g_dev has been mounted by others"
	[ -d $g_bindir ] || invalid "no bin subdir there"
	if [ $g_madvise -eq 0 ]; then
		silent_exec which $g_pagetool || err "no $g_pagetool tool on the system"
		g_pagetool=`which $g_pagetool`
		dbp "Found the tool: $g_pagetool"
	fi	
	if [ $g_pfninj -eq 1 ]; then
		[ -d $debugfs/hwpoison/ ] || invalid "pls. insmod hwpoison_inject module"
	fi
	if [ $g_apei -eq 1 ]; then
		[ -d $debugfs/apei/ ] || invalid "pls. insmod apei_inj module"
	fi
	[ -d $g_ltproot -a -f $g_ltppan ] || invalid "no ltp-pan on the machine: $g_ltppan"
	if [ $g_runltp -eq 1 ]; then 
		[ -d $g_ltproot -a -f $g_ltproot/runltp ] || invalid "no runltp on the machine"
	fi
	[ $g_duration -eq 0 ] && invalid "test duration is set as 0 second"
}

setup_log()
{
	mkdir -p $g_resultdir
	rm -rf $g_logdir
	mkdir -p $g_logdir
	echo -n "" > $g_logfile
	echo -n "" > $g_result
	clear > $g_tty
}

setup_env() 
{
	begin "setup test environment"
	mkdir -p $g_casedir  
	check_env	
	setup_errinj
	setup_meminfo
	trap "cleanup" 0
	setup_fs
	export PATH="${PATH}:$g_bindir"
	end "setup test environment"
}

run_ltp()
{
	local ltp_failed=$g_logdir/ltp/ltp_failed
	local ltp_log=$g_logdir/ltp/ltp_log
	local ltp_output=$g_logdir/ltp/ltp_output
	local ltp_tmp=$g_testdir/ltp_tmp

	begin "launch ltp workload in background"
	mkdir -p $g_logdir/ltp
	echo -n "" > $ltp_failed
	echo -n "" > $ltp_log
	echo -n "" > $ltp_output
	mkdir -p $ltp_tmp
	silent_exec_background $g_ltproot/runltp -d $ltp_tmp -l $ltp_log -o $ltp_output -r $g_ltproot -t ${g_duration}s -C $ltp_failed 
	g_pid_ltp=$!
	end "launch ltp workload in background (pid: $g_pid_ltp)"
}

ltp_result()
{
	local num=0;
	local ltp_failed=$g_logdir/ltp/ltp_failed
	local ltp_output=$g_logdir/ltp/ltp_output
	
	[ -f $ltp_failed ] || {
		result "\tltp -- error: no ltp result there"
		result "\t    log: $ltp_output"
		g_failed=`expr $g_failed + 1`
		return
	}
	num=`wc -l $ltp_failed | awk '{print $1}'`
	if [ $num -ne 0 ]; then
		result "\tltp -- $num case(s) failed"
		result "\t    log: $ltp_output"
		g_failed=`expr $g_failed + 1`
	else
		result "\tltp -- all tests pass"
	fi
}


fs_metadata()
{
	local dir=$g_logdir/fs_metadata	
	local result=$dir/fs_metadata.result
	local log=$dir/fs_metadata.log
	local pan_log=$dir/pan_log
	local pan_output=$dir/pan_output
	local pan_zoo=$dir/pan_zoo
	local pan_failed=$dir/pan_failed
	local tmp=$g_testdir/fs_metadata
	local threads=
	local node_number=5
	local tree_depth=6
	let "threads= $g_duration / 720"
	[ $threads -gt 10 ] && threads=10 && node_number=6
	[ $threads -eq 0 ] && threads=1

	begin "launch fs_metadata workload"
	mkdir -p $dir
	echo -n "" > $pan_failed
	echo -n "" > $pan_log
	echo -n "" > $pan_output
	echo -n "" > $pan_zoo
	mkdir -p $tmp

	echo "fs_metadata fs-metadata.sh $tree_depth $node_number $threads $g_duration $result $tmp $log" > $g_casedir/fs_metadata 
	dbp "g_ltppan -n fs_metadata -a $pan_zoo -f $g_casedir/fs_metadata -o $pan_output -l $pan_log -C $pan_failed &"
	silent_exec_background $g_ltppan -n fs_metadata -a $pan_zoo -f $g_casedir/fs_metadata -o $pan_output -l $pan_log -C $pan_failed
	g_pid_fsmeta=$!
	sleep $g_interval
	silent_exec grep "abort" $log && err "failed to launch fs_metadata workload, it might be due to insufficient disk space, pls read $log for details!"
	end "launch fs_metadata workload (pid: $g_pid_fsmeta)"
}

fs_metadata_result()
{
	local fail_num=0;
	local pass_num=0;
	local dir=$g_logdir/fs_metadata	
	local result=$dir/fs_metadata.result
	local log=$dir/fs_metadata.log

	[ -f $result ] || {
		result "\tfs_metadata -- error: no result there"
		result "\t    details: $log"
		g_failed=`expr $g_failed + 1`
		return
	}
	fail_num=`grep FAIL $result | awk -F : '{print $NF}'`
	pass_num=`grep PASS $result | awk -F : '{print $NF}'`
	[ -z "$fail_num" ] && fail_num=0 && pass_num=0
	if [ $fail_num -ne 0 ]; then
		result "\tfs_metadata -- $fail_num tests failed, $pass_num tests pass."
		result "\t    details: $result"
		g_failed=`expr $g_failed + 1`
	else
		if [ $pass_num -eq 0 ]; then
			result "\tfs_metadata -- no test finished"
			result "\t    details: $log"
			g_failed=`expr $g_failed + 1`
		else 
			result "\tfs_metadata -- all $pass_num tests got pass"
		fi
	fi

	return
}

# fs_specific workload, TBD
fs_specific()
{
	begin "launch $g_fstype specific workload"

	touch $g_logdir/fs_specific
#	$g_ltppan -n fs_specific -a $g_logdir/fs_specific -f $g_casedir/fs_specific -t ${g_duration}s &
	end "launch $g_fstype specific workload"
}

page_poisoning()
{
	local dir=$g_logdir/page_poisoning	
	local pan_failed=$dir/pan_failed
	local pan_log=$dir/pan_log
	local pan_output=$dir/pan_output
	local tmp=$g_testdir/page_poisoning
	local pan_zoo=$dir/pan_zoo
	local result=$dir/page_poisoning.result
	local log=$dir/page_poisoning.log

	begin "-- launch page_poisoning test"
	mkdir -p $dir
	echo -n "" > $pan_failed
	echo -n "" > $pan_log
	echo -n "" > $pan_output
	echo -n "" > $pan_zoo
	echo -n "" > $log
	echo -n "" > $result
	mkdir -p $tmp

	echo "page_poisoning page-poisoning -l $log -r $result -t $tmp" > $g_casedir/page_poisoning
	dbp "$g_ltppan -n page_poisoning -a $pan_zoo -f $g_casedir/page_poisoning -t ${g_duration}s -o $pan_output -l $pan_log -C $pan_failed &"
	silent_exec_background $g_ltppan -n page_poisoning -a $pan_zoo -f $g_casedir/page_poisoning -t ${g_duration}s -o $pan_output -l $pan_log -C $pan_failed 
	g_pid_madv=$!
	end "-- launch page_poisoning test (pid: $g_pid_madv)"
}

page_poisoning_result()
{
	local fail_num=0
	local pass_num=0
	local dir=$g_logdir/page_poisoning	
	local result=$dir/page_poisoning.result
	local log=$dir/page_poisoning.log
	
	[ -f $result ] || {
		result "\tpage_poisoning -- error: no result file there"
		result "\t    details: $log"
		g_failed=`expr $g_failed + 1`
		return
	}
	fail_num=`grep FAILED $result | wc -l | awk '{print $1}'`
	pass_num=`grep PASS $result | wc -l | awk '{print $1}'`
	if [ $fail_num -ne 0 ]; then
		result "\tpage_poisoning -- $fail_num tests failed, $pass_num tests pass."
		result "\t    details: $result"
		g_failed=`expr $g_failed + 1`
	else
		if [ $pass_num -eq 0 ]; then
			result "\tpage_poisoning -- no case finished"
			result "\t    details: $log"
			g_failed=`expr $g_failed + 1`
		else 
			result "\tpage_poisoning -- all $pass_num tests got pass"
		fi
	fi

	return
}

run_workloads()
{
	fs_metadata
	fs_specific
	return
}

show_progress()
{
	local cur=
	local rest=0
	local percent=0
	
	cur=`date +%s` 
	[ "$cur" -ge "$g_time_e" ] && return
	rest=`expr $g_time_e - $cur`
	let "percent= ($g_duration - $rest) * 100 / $g_duration"

	log "hwpoison page error injection: $percent% pages done"	
}

_pfn_inj()
{
	local pg=$1

	echo $pg > $debugfs/hwpoison/corrupt-pfn
	dbp "echo $pg > $debugfs/hwpoison/corrupt-pfn"
}

pfn_inj()
{
	local debugfs="/sys/kernel/debug"
	local pg_list=
	local pg=0
	local pfn=0
	local cur=
	local i=0

	if [ $g_pgtype = "all" ]; then
		pfn=$g_lowmem_s 	# start from 1M.
		while [ "$pfn" -lt "$g_maxpfn" ]
		do
			pg=`printf "%x" $pfn`
			_pfn_inj 0x$pg > /dev/null 2>&1
			pfn=`expr $pfn + 1`
			[ $pfn -gt $g_lowmem_e ] && pfn=$g_highmem_s
			[ $pfn -gt $g_highmem_e ] && break
			i=`expr $i + 1`
			if [ $i -eq $g_progress ]; then
				cur=`date +%s`
				[ "$cur" -ge "$g_time_e" ] && break
				show_progress
				i=0 
			fi
		done
	else
		silent_exec $g_pagetool -Nrb $g_pgtype || err "unsupported pagetype, pls. refer to command: $g_pagetool -h"
		pg_list=`$g_pagetool -NLrb $g_pgtype | grep -v offset | cut -f1`
		for pg in $pg_list
		do
			_pfn_inj 0x$pg > /dev/null 2>&1
			i=`expr $i + 1`
			if [ $i -eq $g_progress ]; then
				cur=`date +%s`
				[ "$cur" -ge "$g_time_e" ] && break
				show_progress
				i=0 
			fi
		done
	fi
}

_apei_inj()
{
	local pfn=`printf "%x" $1`
	local type=$2

	echo $type > $debugfs/apei/einj/error_type
	echo "0x${pfn}000" > $debugfs/apei/err_inj/error_address
	echo "1" > $debugfs/apei/einj/error_inject
}

apei_ewb_ucr()
{
	_apei_inj $1 0x2	
}

apei_mem_ucr()
{
	_apei_inj $1 0x10
}

apei_inj()
{
	local debugfs="/sys/kernel/debug"
	local pg_list=
	local pg=
	local cur=
	local i=0

	pg_list=`$g_pagetool -NLrb $g_pgtype | grep -v offset | cut -f1`
	for pg in $pg_list
	do
		apei_mem_ucr $pg 
		i=`expr $i + 1`
		if [ $i -eq $g_progress ]; then
			cur=`date +%s`
			[ "$cur" -ge "$g_time_e" ] && break
			show_progress
			i=0 
		fi
	done

	return
}

err_inject()
{
	local cur=
	local i=0

	if [ $g_madvise -eq 1 ]; then
		begin "inject HWPOISON error to pages thru madvise syscall"
	else
		begin "inject HWPOISON error to pages ($g_pgtype)"
	fi
	let "g_progress=$g_duration * 100"
	g_time_s=`date +%s`	
	g_time_e=`expr $g_time_s + $g_duration`
	cur=$g_time_s
	[ $g_madvise -eq 1 ] && { 
		page_poisoning	
		show_progress
	}
	while [ "$cur" -lt "$g_time_e" ]
	do
		if [ $g_madvise -eq 0 ]; then 
			show_progress 
			[ $g_apei -eq 1 ] && apei_inj
			[ $g_pfninj -eq 1 ] && pfn_inj
		else 
			if [ $i -eq $g_progress ]; then
				show_progress
				i=0 
			fi
			i=`expr $i + 1`
		fi	
		cur=`date +%s` 
	done
	log "hwpoison page error injection: 100% pages done"	
	# wait workloads to be finished.	
	sleep $g_interval 

	if [ $g_madvise -eq 1 ]; then
		end "inject HWPOISON error to pages thru madvise syscall"
	else
		end "inject HWPOISON error to pages ($g_pgtype)"
	fi
}

fsck_err()
{
	local dir=$g_logdir/fsck	
	local result=$dir/fsck.result
	local log=$dir/fsck.log

	echo "FAILED: $@" > $result
	echo "FAILED: $@" > $log
}

fsck_pass()
{
	local dir=$g_logdir/fsck	
	local result=$dir/fsck.result
	local log=$dir/fsck.log

	echo "PASS: $@" > $result
	echo "PASS: $@" > $log
}

run_fsck()
{
	local dir=$g_logdir/fsck	
	local result=$dir/fsck.result
	local log=$dir/fsck.log

	mkdir -p $dir
	echo -n "" > $log
	echo -n "" > $result

	begin "launch fsck.$g_fstype on $g_dev to check test result"
	silent_exec which fsck.$g_fstype || {
		fsck_err "fsck: unsupported fstype: $g_fstype"
		return
	}
	fs_sync
	silent_exec umount -f $g_dev || sleep $g_interval
	df | grep $g_dev > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		silent_exec umount $g_dev || {
			fsck_err "cannot umount $g_dev to do fsck.$g_fstype" 
			return
		}
	fi
	fsck.$g_fstype $g_dev || fsck_err "err #$? while fsck.$g_fstype on $g_dev"
	silent_exec mount -t $g_fstype $g_dev $g_testdir || { 
		fsck_err "cannot mount $g_testdir back after fsck_check"
		return
	}
	fsck_pass "fsck.$g_fstype got pass on $g_dev"
	end "launch fsck.$g_fstype on $g_dev to check test result"
}

fsck_result()
{
	local dir=$g_logdir/fsck	
	local result=$dir/fsck.result
	local log=$dir/fsck.log
	local fail_num=0;
	local pass_num=0;
	[ -f $result ] || { 
		result "\tfsck.$g_fstype -- no result found" 
		result "\t    details: $log"
		g_failed=`expr $g_failed + 1`
		return
	}

	fail_num=`grep FAILED $result | wc -l | awk '{print $1}'`
	pass_num=`grep PASS $result | wc -l | awk '{print $1}'`
	if [ $fail_num -ne 0 ]; then
		result "\tfsck.$g_fstype -- failed"
		result "\t    log: $log"
		g_failed=`expr $g_failed + 1`
	else
		if [ $pass_num -eq 0 ]; then
			result "\tfsck.$g_fstype -- not executed"
			result "\t    log: $log"
			g_failed=`expr $g_failed + 1`
		else 
			result "\tfsck.$g_fstype -- fsck on $g_dev got pass"
		fi
	fi
}

result_check()
{
	begin "-- collecting test result"
	result "#############################################"
	result "result summary:"
	if [ $g_madvise -eq 1 ]; then
		page_poisoning_result
	else
		fs_metadata_result
		[ $g_runltp -eq 1 ] && ltp_result
	fi
	[ $g_netfs -eq 0 ] && fsck_result
	result ""
	result "totally $g_failed tasks failed"
	result "#############################################"
	end "-- collecting test result"
}

usage()
{
	echo "Usage: ./hwpoison.sh -d /dev/device [-options] [arguments]"
	echo
	echo "Stress Testing for Linux MCA High Level Handlers: "
	echo -e "\t-c console\t: target tty console to print test log" 
	echo -e "\t-d device\t: target block device to run test on" 
	echo -e "\t-f fstype\t: filesystem type to be tested"
	echo -e "\t-l logfile\t: log file"
	echo -e "\t-t duration\t: test duration time (default is $g_duration seconds)"
	echo -e "\t-i interval\t: sleep interval (default is $g_interval seconds)"
	echo -e "\t-o ltproot\t: ltp root directory (default is $g_ltproot/)"
	echo -e "\t-p pagetype\t: page type to inject error "
	echo -e "\t-s pagesize\t: page size on the system (default is $g_pgsize bytes)"
	echo -e "\t-r result\t: result file"
	echo -e "\t-h \t\t: print this page"
	echo -e "\t-L \t\t: run ltp in background"
	echo -e "\t-M \t\t: run page_poisoning test thru madvise syscall"
	echo -e "\t-A \t\t: use APEI to inject error"
	echo -e "\t-F \t\t: execute as force mode, no interaction with user"
	echo -e "\t-N \t\t: do not mkfs target block device"
	echo -e "\t-V \t\t: verbose mode, show debug info"
	echo
	echo -e "device:" 
	echo -e "\tthis is a mandatory argument. typically, it's a disk partition." 
	echo -e "\tall temporary files will be created on this device." 
	echo -e "\terror injector will just inject errors to the pages associated" 
	echo -e "\twith this device (except for the testing thru madvise syscall)." 
	echo
	echo -e "pagetype:"
 	echo -e "\tdefault page type:" 
	echo -e "\t    $g_pgtype"
	echo -e "\tfor more details, pls. try \`page-types -h\`." 
	echo -e "\tsee the definition of \"bits-spec\"." 
	echo
	echo -e "console:" 
	echo -e "\ttest can print output to the console you specified." 
	echo -e "\te.g. '-c /dev/tty1'" 
	echo

	exit 0
}

fs_sync()
{
	log "now to sync up the disk under testing, might need several minutes ..."
	sync
}

stop_children()
{
	begin "-- cleaning up remaining tasks in background" 
	if [ -n "$g_pid_madv" ]; then
		silent_exec ps $g_pid_madv 
		[ $? -eq 0 ] && { 
			kill -15 $g_pid_madv > /dev/null 2>&1
			sleep $g_interval
		} 
	fi
	if [ -n "$g_pid_fsmeta" ]; then
		silent_exec ps $g_pid_fsmeta 
		[ $? -eq 0 ] && { 
			kill -15 $g_pid_fsmeta > /dev/null 2>&1
			sleep $g_interval
		}
	fi 
	if [ -n "$g_pid_ltp" ]; then
		silent_exec ps $g_pid_ltp 
		[ $? -eq 0 ] && { 
			kill -15 $g_pid_ltp > /dev/null 2>&1
			sleep $g_interval
		}
	fi 
	end "-- cleaning up remaining tasks in background" 
}

cleanup()
{
	log "!!! EXIT signal received, need to exit testing now. !!!"
	begin "preparing to complete testing"
	stop_children
	fs_sync
	result_check
	df | grep $g_dev > /dev/null 2>&1 && silent_exec umount -f $g_dev
	end "preparing to complete testing"
	log "!!! Linux HWPOISON stress testing DONE !!!"
	log "result: $g_result"
	log "log: $g_logfile"
	[ $g_failed -ne 0 ] && exit 1
}

select_injector()
{
# apei injector is 1st priority.
	if [ $g_apei -eq 1 ]; then
		g_pfninj=0
		g_madvise=0
	fi

	if [ $g_madvise -eq 1 ]; then
		g_pfninj=0
	fi
}

g_dev=
g_testdir="/hwpoison"
g_fstype=ext3
g_netfs=0
g_nomkfs=0
g_force=0
let "g_duration=120"
g_interval=5
g_runltp=0
g_ltproot="/ltp"
g_ltppan="$g_ltproot/pan/ltp-pan"
g_pagetool="page-types"
g_madvise=0
g_apei=0
g_pfninj=1
g_rootdir=`pwd`
g_bindir=$g_rootdir/bin
g_casedir=$g_rootdir/runtest
g_logdir=$g_rootdir/log
g_resultdir=$g_rootdir/result
g_logfile=$g_resultdir/hwpoison.log
g_result=$g_resultdir/hwpoison.result
g_failed=0
g_time_s=
g_time_e=
g_tty=`tty`
g_pid_madv=
g_pid_fsmeta=
g_pid_ltp=
g_progress=
g_pgtype="lru,referenced,readahead,swapcache,swapbacked,anonymous"
g_pgsize=4096	# page size on the system
g_maxpfn=	# maxpfn on the system
g_highmem_s=	# start pfn of highmem 
g_highmem_e=	# end pfn of highmem
g_lowmem_s=	# start pfn of mem < 4G
g_lowmem_e=	# end pfn of mem < 4G

while getopts ":c:d:f:l:t:o:i:r:p:s:hLMAFNV" option
do 
	case $option in
		c) g_tty=$OPTARG;;
		d) g_dev=$OPTARG;;
		f) g_fstype=$OPTARG;;
		l) g_logfile=$OPTARG;;
		t) g_duration=$OPTARG;;
		i) g_interval=$OPTARG;;
		o) g_ltproot=$OPTARG;;
		p) g_pgtype=$OPTARG;;
		s) g_pgsize=$OPTARG;;
		r) g_result=$OPTARG;;
		L) g_runltp=1;; 
		M) g_madvise=1;;
		A) g_apei=1;;
		F) g_force=1;;
		N) g_nomkfs=1;;
		V) DEBUG=1;;
		h) usage;;
		*) invalid "invalid option";;
	esac
done

select_injector
setup_log
log "!!! Linux HWPOISON stress testing starts NOW !!!"
log "!!! test will run about $g_duration seconds !!!"
setup_env
if [ $g_madvise -eq 0 ]; then
	[ $g_runltp -eq 1 ] && run_ltp
	run_workloads
fi
err_inject
[ $g_netfs -eq 0 ] &&  run_fsck
