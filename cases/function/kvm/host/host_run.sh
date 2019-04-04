#!/bin/bash
#
# Test script for KVM RAS
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
# Copyright (C) 2010-2015, Intel Corp.
# Author: Jiajia Zheng <jiajia.zheng@intel.com>
# Author: Wen Jin <wenx.jin@intel.com>
#

export ROOT=`(cd ../../../../; pwd)`

. $ROOT/lib/functions.sh
setup_path
. $ROOT/lib/mce.sh

inject_type=0x00000010
EDAC_TYPE=""
g_debugfs=""

complain()
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

check_einj()
{
	check_debugfs

	g_debugfs=`cat /proc/mounts | grep debugfs | cut -d ' ' -f2 | head -1`
	#if einj is not builtin, just insmod it
	if [ ! -d $g_debugfs/apei/einj ]; then
		#if einj is a module, it is ensured to have been loaded
		modprobe einj param_extension=1 > /dev/null 2>&1
		[ $? -eq 0 ] || complain "module einj isn't supported?"
	fi
	[ -f $g_debugfs/apei/einj/param1 ] || complain "No BIOS extension support for APEI on this platform"
	[ -f $g_debugfs/apei/einj/notrigger ] ||
		complain "No parameter *notrigger*. Injection maybe causes system crash. Please check commit v3.3-3-gee49089"

	#check if the platform supports Uncorrectable non-fatal Memory Error injection
	cat $g_debugfs/apei/einj/available_error_type | grep -q $inject_type
	if [ $? -ne 0 ]; then
		complain "Uncorrectable non-fatal Memory Error is not supported"
	fi
}

rm_edac()
{
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
}

image=""
mce_inject_file=""

HOST_DIR=`pwd`
GUEST_DIR="/test"
early_kill="1"
RAM_size=""

kernel=""
initrd=""
root=""
test_type=""
format=""
trigger_file="trigger_start"

usage()
{
	echo "Usage: ./host_run.sh [-options] [arguments]"
	echo "================Below are the must have options==============="
	echo -e "\t-t test_type\t: spoof(mce_inject) or real(einj)"
	echo -e "\t-i image\t: guest image"
	echo "================Below are the optional options================"
	echo -e "\t-f mcefile\t: which mce data file to inject"
	echo -e "\t-d hostdir\t: where you put the test scripts on host system"
	echo -e "\t\t\tBe careful to change it"
	echo -e "\t-g guestdir\t: where you put the test scripts on guest system"
	echo -e "\t\t\tBy default, guestdir is set to $GUEST_DIR"
	echo -e "\t-o offset\t: guest image offset"
	echo -e "\t\t\tBy default, offset is calculated by kpartx "
	echo -e "\t-l\t\t: late kill, disable early kill in guest system"
	echo -e "\t\t\tBy default, earlykill is enabled "
	echo -e "\t-m ramsize\t: virtual RAM size of guest system"
	echo -e "\t\t\tBy default, qemu-kvm defaults to 2048M bytes"
	echo -e "\t-h\t\t: show this help"
	echo "============If you want to specify the guest kernel==========="
	echo "============please set below options all together============="
	echo -e "\t-k kernel\t: guest kernel"
	echo -e "\t-n initrd\t: guest initrd"
	echo -e "\t-r root\t\t: guest root partition"
	exit 0
}

while getopts "i:f:d:g:o:b:p:k:n:r:t:hlm:" option
do
	case $option in
		t) test_type=$OPTARG;;
		i) image=$OPTARG;;
		f) mce_inject_file=$OPTARG;;
		d) HOST_DIR=$OPTARG;;
		g) GUEST_DIR=$OPTARG;;
		o) offset=$OPTARG;;
		l) early_kill="0";;
		k) kernel=$OPTARG;;
		n) initrd=$OPTARG;;
		r) root=$OPTARG;;
		m) RAM_size=$OPTARG;;
		h) usage;;
		*) echo 'invalid option!'; usage;;
	esac
done

script_victim=guest_run_victim.sh
guest_script_victim=$GUEST_DIR/$script_victim
guest_tmp=$GUEST_DIR/guest_tmp
guest_page=$GUEST_DIR/guest_page
GUEST_PHY=""

host_key_pub=$HOST_DIR/id_rsa.pub
host_key_priv=$HOST_DIR/id_rsa
guest_init=$HOST_DIR/guest_init
host_start=$HOST_DIR/host_start
pid_file=$HOST_DIR/pid_file
monitor_console_output=$HOST_DIR/monitor_console_output
serial_console_output=$HOST_DIR/serial_console_output
host_tmp=$HOST_DIR/host_tmp
mce_inject_data=$HOST_DIR/mce_inject_data
monitor_console=""
serial_console=""
NBD_MAJOR="43"
NBD_DEV="/dev/nbd0"

invalid()
{
	echo $1
	echo "Try ./host_run.sh -h for more information."
	exit 0
}

check_env()
{
	if [ "`whoami`" != "root" ]; then
		echo "Must run as root"
		exit 1
	fi

	if modinfo mce_inject >/dev/null 2>&1; then
		if ! lsmod | grep -q mce_inject; then
			if ! modprobe mce_inject; then
				complain "module mce_inject isn't supported ?"
			fi
		fi
	fi

	which qemu-img >/dev/null 2>&1
	[ ! $? -eq 0 ] && complain "please install qemu-img tool!"
	which kpartx >/dev/null 2>&1
	[ ! $? -eq 0 ] && complain "please install kpartx tool!"
	which losetup >/dev/null 2>&1
	[ ! $? -eq 0 ] && complain "please install losetup tool!"
	which pvdisplay >/dev/null 2>&1
	[ ! $? -eq 0 ] && complain "please install pvdisplay tool!"
	which vgchange >/dev/null 2>&1
	[ ! $? -eq 0 ] && complain "please install vgchange tool!"
	which mce-inject >/dev/null 2>&1
	[ ! $? -eq 0 ] && complain "please install mce-inject tool!"

	[ -z $RAM_size ] && RAM_size=2048
	if [ -z $test_type ] || [ "$test_type" != "spoof" ] && [ "$test_type" != "real" ]
	then
	    invalid "please input inject type: spoof or real!"
	fi
	[ -z ${image} ] && invalid "please input the guest image!"
	[ ! -e ${image} ] && invalid "guest image ${image} does not exist!"
	if [ "$test_type" == "spoof" ]; then
	    [ -z $mce_inject_file ] && invalid "please input the mce data file!"
	    [ ! -e $mce_inject_file ] && invalid "mce data file $mce_inject_file does not exist!"
	fi

	[ ! -e $host_key_pub ] && complain "host public key does not exist!"
	[ ! -e $host_key_priv ] && complain "host privite key does not exist!"
	chmod 600 $host_key_pub
	chmod 600 $host_key_priv
	[ -e $ROOT/bin/victim ] || complain "file victim does not exist!" \
	"maybe you forget to run make install under directory $ROOT before test"
	if [ "$test_type" == "real" ]; then
		check_einj
		rm_edac
	fi
}

mount_image()
{
	local filename

	mnt=`mktemp -d`
	filename=${image}
	format=`qemu-img info ${image} | awk -F ': ' '/file format/ {print $NF}'`
	if [ "$format" != "raw" ]; then
	    which qemu-nbd >/dev/null 2>&1
	    [ ! $? -eq 0 ] && complain "please install qemu-nbd tool!"
	    if [ ! -b $NBD_DEV ] || [ `ls -l $NBD_DEV | awk '{print $5}' | cut -b 1-2` != $NBD_MAJOR ]; then
		modprobe nbd >/dev/null 2>&1
		[ $? -eq 0 ] || complain "module nbd isn't supported?"
	    fi
	    qemu-nbd -d $NBD_DEV
	    sleep 1
	    qemu-nbd -c $NBD_DEV ${image}
	    sleep 1
	    filename=$NBD_DEV
	fi

	offset=`kpartx -l ${filename} | awk '/loop deleted/ {next}; \
	{offset=$NF*512}; END {print offset}'`
	mount_err=`mount -oloop,offset=$offset ${filename} $mnt 2>&1`
	if [ $? -eq 0 ]; then
	    fs_type=unset
	    echo "mount image to $mnt"
	    return 0
	fi

	#See if we're dealing with a LVM filesystem type
	fs_type=`echo $mount_err | awk '/^mount: unknown filesystem type/ {print $NF}'`
	if [ "$fs_type" != "'LVM2_member'" ]; then
	    echo unknown filesystem type
	    rm -rf $mnt
	    if [ "$format" != "raw" ]; then
		qemu-nbd -d $NBD_DEV
	    fi
	    return 1
	fi

	#Try mounting the LVM image
	loop_dev=`losetup -o ${offset} -f --show ${filename}`
	sleep 1
	if [ -z "${loop_dev}" ]; then
	    echo no available loop device
	    rm -rf $mnt
	    if [ "$format" != "raw" ]; then
		qemu-nbd -d $NBD_DEV
	    fi
	    return 1
	fi

	vg=`pvdisplay ${loop_dev} | awk '/  VG Name/ {print $NF}'`
	if [ -z "${vg}" ]; then
	    losetup -d ${loop_dev}
	    rm -rf $mnt
	    if [ "$format" != "raw" ]; then
		qemu-nbd -d $NBD_DEV
	    fi
	    return 1
	fi

	vgchange -a ey ${vg}
	sleep 1
	#The device name under the /dev/mapper directory consists of vg(volume group) name
	#and lv(logical volume) name, in which the char '-' will be replaced with "--"
	#in the vg name part if it exists.
	devmap_vg=`echo ${vg} | sed 's/-/--/g'`
	devmap_root=`find /dev/mapper -name "${devmap_vg}*root" -print`
	if [ ! -b "${devmap_root}" ]; then
	    echo '! block special'
	    losetup -d ${loop_dev}
	    rm -rf $mnt
	    if [ "$format" != "raw" ]; then
		qemu-nbd -d $NBD_DEV
	    fi
	    return 1
	fi
	mount ${devmap_root} $mnt
	if [ $? -ne 0 ]; then
	    vgchange -a en ${vg}
	    losetup -d ${loop_dev}
	    rm -rf $mnt
	    if [ "$format" != "raw" ]; then
		qemu-nbd -d $NBD_DEV
	    fi
	    return 1
	fi
	echo "mount LVM image to $mnt"
	return 0
}

umount_image()
{
	umount $mnt
	sleep 2
	if [ "$fs_type" = "'LVM2_member'" ]; then
	    vgchange -a en ${vg}
	    losetup -d ${loop_dev}
	fi
	rm -rf $mnt
	if [ "$format" != "raw" ]; then
	    qemu-nbd -d $NBD_DEV
	fi
}

#Guest Image Preparation
image_prepare()
{
	local i

	mount_image
	if [ $? -ne 0 ]; then
	    echo 'mount of image failed!'
	    return 1
	fi
	i=`grep id:.*:initdefault $mnt/etc/inittab |cut -d':' -f2`
	rm -f $mnt/etc/rc${i}.d/S99kvm_ras
	rm -f $mnt/$guest_tmp $mnt/$guest_page

	if [ ! -d $mnt/root/.ssh ]; then
	    mkdir $mnt/root/.ssh
	    chmod 700 $mnt/root/.ssh
	fi
	mkdir -p $mnt/$GUEST_DIR
	rm -f $mnt/$GUEST_DIR/$trigger_file
	cp -f ../guest/$script_victim $mnt/$GUEST_DIR
	cp -rf $ROOT/tools/victim $mnt/$GUEST_DIR
	cat $host_key_pub >> $mnt/root/.ssh/authorized_keys
	kvm_ras=/etc/init.d/kvm_ras
	sed -i -e "s#GUEST_DIR#$GUEST_DIR#g" $mnt/$guest_script_victim
	sed -e "s#EARLYKILL#$early_kill#g" \
	-e "s#GUESTRUN#$guest_script_victim#g" $guest_init > $mnt/$kvm_ras
	chmod a+x $mnt/$kvm_ras
	ln -s $kvm_ras $mnt/etc/rc${i}.d/S99kvm_ras
	sleep 2
	umount_image
	return 0
}

#Start guest system
start_guest()
{
	if [ ! -z $kernel ]; then
	    if [ ! -z $initrd ]; then
		if [ ! -z $root ]; then
		    append="root=$root ro loglevel=8 mce=3 console=ttyS0,115200n8 console=tty0"
		    qemu-system-x86_64 -hda ${image} -kernel $kernel -initrd $initrd --append "$append" \
		    -m $RAM_size -net nic,model=rtl8139 -net user,hostfwd=tcp::5555-:22 \
		    -monitor pty -serial pty -pidfile $pid_file > $host_start 2>&1 &
		    sleep 5
		else
		    invalid "please specify the guest root partition!"
		fi
	    else
		invalid "please specify the guest initrd!"
	    fi
	else
	    echo "Start the default kernel on guest system,${image}"
	    qemu-system-x86_64  -smp 2 -machine accel=kvm -drive file=${image},format=$format \
	    -m $RAM_size -net nic,model=rtl8139 -net user,hostfwd=tcp::5555-:22 \
	    -monitor pty -serial pty -pidfile $pid_file > $host_start 2>&1 &
	    sleep 10
	fi
	monitor_console=`awk '{print $5}' $host_start | sed -n -e '1p'`
	serial_console=`awk '{print $5}' $host_start | sed -n -e '2p'`
	QEMU_PID=`cat $pid_file`
	echo "monitor console is $monitor_console"
	echo "serial console is $serial_console"
	echo "Waiting for guest system start up..."
}

check_guest_alive()
{
	for i in 1 2 3 4 5 6 7 8 9
	do
	    sleep 10
	    ssh -i $host_key_priv -o StrictHostKeyChecking=no 127.0.0.1 -p 5555 echo "" > /dev/null 2>&1
	    if [ $? -eq 0 ]; then
		return 0
	    else
		echo "Waiting..."
	    fi
	done
	return 1
}

addr_translate()
{
	#Get Guest physical address
	scp -o StrictHostKeyChecking=no -i $host_key_priv -P 5555 \
	    127.0.0.1:$guest_tmp $HOST_DIR/guest_tmp > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo "Failed to get Guest physical address, quit testing!"
		kill -9 $QEMU_PID
		exit 0
	fi
	sleep 2
	GUEST_PHY=`awk '{print $NF}' $HOST_DIR/guest_tmp`
	echo "Guest physical address is $GUEST_PHY"
	sleep 2

	#Get Host virtual address
	echo x-gpa2hva $GUEST_PHY > $monitor_console
	cat $monitor_console > $monitor_console_output &
	sleep 5
	HOST_VIRT=`awk '/x-gpa2hva|qemu|QEMU/{next} {print $NF}' $monitor_console_output`
	echo "Host virtual address is $HOST_VIRT"

	#Get Host physical address
	victim -a vaddr=$HOST_VIRT,pid=$QEMU_PID > $host_tmp
	sleep 5
	ADDR=`cat $host_tmp | awk '{print $NF}'`
	echo "Host physical address is $ADDR"
}

error_inj()
{
	if [ "$test_type" == "real" ]; then
		#Inject via APEI
		echo "calling apei_inj $ADDR"
		apei_inj $ADDR
		sleep 1
		touch $HOST_DIR/$trigger_file
		echo "trigger" > $HOST_DIR/$trigger_file
		scp -o StrictHostKeyChecking=no -i $host_key_priv -P 5555 $HOST_DIR/$trigger_file \
			127.0.0.1:$GUEST_DIR > /dev/null 2>&1
	elif [ "$test_type" == "spoof" ]; then
		#Inject via mce_inject
		cat $mce_inject_file > $mce_inject_data
		echo "ADDR $ADDR" >> $mce_inject_data
		echo "calling mce-inject $mce_inject_data"
		mce-inject $mce_inject_data
		sleep 1
		touch $HOST_DIR/$trigger_file
		echo "trigger" > $HOST_DIR/$trigger_file
		scp -o StrictHostKeyChecking=no -i $host_key_priv -P 5555 $HOST_DIR/$trigger_file \
			127.0.0.1:$GUEST_DIR > /dev/null 2>&1
	fi

}


get_guest_klog()
{
	cat $serial_console > $serial_console_output &
}

check_guest_klog()
{
	GUEST_PHY_KLOG=`echo $GUEST_PHY | sed 's/000$//'`
	echo "Guest physical klog address is $GUEST_PHY_KLOG"
	cat $serial_console_output | grep "MCE $GUEST_PHY_KLOG"
	if [ $? -ne 0 ]; then
		return 1
	fi
	return 0
}


check_srar_lmce_log()
{
	ssh -i $host_key_priv -o StrictHostKeyChecking=no 127.0.0.1 -p 5555 \
		"cat /var/log/mcelog" >> $serial_console_output
	cat $serial_console_output | grep -q "SRAR"
	if [ $? -ne 0 ]; then
	    return 1
	fi
	echo "SRAR error triggered successfully"
	cat $serial_console_output | grep -q "LMCE"
	if [ $? -eq 0 ]; then
	    echo "LMCE happens"
	fi
	return 0
}


check_env
image_prepare
if [ $? -ne 0 ]; then
    echo 'Mount Guest image failed, quit testing!'
else
    start_guest
    get_guest_klog
    check_guest_alive
    if [ $? -ne 0 ]; then
	echo 'Start Guest system failed, quit testing!'
    else
	sleep 5
	addr_translate
	error_inj
	sleep 5
	if [ "$test_type" == "real" ]; then
		check_srar_lmce_log
	elif [ "$test_type" == "spoof" ]; then
		check_guest_klog
	fi
	if [ $? -ne 0 ]; then
	    echo 'FAIL: Did not get expected log!'
	    kill -9 $QEMU_PID
	    exit 1
	else
	    echo 'PASS: Inject error into guest!'
	fi
	check_guest_alive
	if [ $? -ne 0 ]; then
	    echo 'FAIL: Guest System could have died!'
	else
	    echo 'PASS: Guest System alive!'
	fi
    fi
fi

rm -f guest_tmp $host_start $monitor_console_output $serial_console_output $host_tmp \
    $pid_file $HOST_DIR/$trigger_file
if [ "$test_type" == "spoof" ]; then
	rm -f $mce_inject_data
fi
