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
# Copyright (C) 2010, Intel Corp.
# Author: Jiajia Zheng <jiajia.zheng@intel.com>
#

image=""
mce_inject_file=""

HOST_DIR=`pwd`
GUEST_DIR="/test"
early_kill="1"
RAM_size=""

kernel=""
initrd=""
root=""

usage()
{
	echo "Usage: ./host_run.sh [-options] [arguments]"
	echo "================Below are the must have options==============="
	echo -e "\t-i image\t: guest image"
	echo -e "\t-f mcefile\t: which mce data file to inject"
	echo "================Below are the optional options================"
	echo -e "\t-d hostdir\t: where you put the test scripts on host system"
	echo -e "\t\t\tBe careful to change it"
	echo -e "\t-g guestdir\t: where you put the test scripts on guest system"
	echo -e "\t\t\tBy default, guestdir is set to $GUEST_DIR"
	echo -e "\t-o offset\t: guest image offset"
	echo -e "\t\t\tBy default, offset is calculated by kpartx "
        echo -e "\t-l\t\t: late kill, disable early kill in guest system"
        echo -e "\t\t\tBy default, earlykill is enabled "
        echo -e "\t-m ramsize\t: virtual RAM size of guest system"
        echo -e "\t\t\tBy default, qemu-kvm defaults to 512M bytes"
        echo -e "\t-h\t\t: show this help"
	echo "============If you want to specify the guest kernel==========="
	echo "============please set below options all together============="
	echo -e "\t-k kernel\t: guest kernel"
	echo -e "\t-n initrd\t: guest initrd"
	echo -e "\t-r root\t\t: guest root partition"
	exit 0
}

while getopts "i:f:d:g:o:b:p:k:n:r:hlm:" option
do
        case $option in
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


guest_script=$GUEST_DIR/guest_run.sh
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

	if modinfo mce_inject &> /dev/null; then
		if ! lsmod | grep -q mce_inject; then
			if ! modprobe mce_inject; then
				invalid "module mce_inject isn't supported ?"
			fi
		fi
	fi

	which kpartx &>/dev/null
	[ ! $? -eq 0 ] && invalid "please install kpartx tool!"
	which mce-inject &>/dev/null
	[ ! $? -eq 0 ] && invalid "please install mce-inject tool!"

	[ -z $RAM_size ] && RAM_size=512
	[ -z $image ] && invalid "please input the guest image!"
	[ ! -e $image ] && invalid "guest image $image does not exist!"
	[ -z $mce_inject_file ] && invalid "please input the mce data file!"
	[ ! -e $mce_inject_file ] && invalid "mce data file $mce_inject_file does not exist!"

	[ ! -e $host_key_pub ] && invalid "host public key does not exist!"
	[ ! -e $host_key_priv ] && invalid "host privite key does not exist!"
	chmod 600 $host_key_pub
	chmod 600 $host_key_priv
}

mount_image()
{
	mnt=`mktemp -d`
	offset=`kpartx -l $image | awk '/loop deleted/ {next}; \
	{offset=$NF*512}; END {print offset}'`
	mount_err=`mount -oloop,offset=$offset $image $mnt 2>&1`
	if [ $? -eq 0 ]; then
	    fs_type=unset
	    echo "mount image to $mnt"
	    return 0
	fi

	#See if we're dealing with a LVM filesystem type
	fs_type=`echo $mount_err | awk '/^mount: unknown filesystem type/ {print $NF}'`
	if [ $fs_type != "'LVM2_member'" ]; then
	    echo unknown filesystem type
	    rm -rf $mnt
	    return 1
	fi

	which losetup &>/dev/null
	[ ! $? -eq 0 ] && invalid "please install losetup tool!"
	which pvdisplay &>/dev/null
	[ ! $? -eq 0 ] && invalid "please install pvdisplay tool!"
	which vgchange &>/dev/null
	[ ! $? -eq 0 ] && invalid "please install vgchange tool!"

	#Try mounting the LVM image
	loop_dev=`losetup -o ${offset} -f --show ${image}`
	if [ -z ${loop_dev} ]; then
	    echo no available loop device
	    rm -rf $mnt
	    return 1
	fi
	vg=`pvdisplay ${loop_dev} | awk '/  VG Name/ {print $NF}'`
	lv=lv_root
	vgchange -a ey ${vg}
	if [ ! -b /dev/mapper/${vg}-${lv} ]; then
	    echo '! block special'
	    losetup -d ${loop_dev}
	    rm -rf $mnt
	    return 1
	fi
	mount /dev/mapper/${vg}-${lv} $mnt
	if [ $? -ne 0 ]; then
	    vgchange -a en ${vg}
	    losetup -d ${loop_dev}
	    rm -rf $mnt
	    return 1
	fi
	echo "mount LVM image to $mnt"
	return 0
}

umount_image()
{
	umount $mnt
	sleep 2
	if [ $fs_type = "'LVM2_member'" ]; then
	    vgchange -a en ${vg}
	    losetup -d ${loop_dev}
	fi
	rm -rf $mnt
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
	cp ../guest/guest_run.sh $mnt/$GUEST_DIR
	gcc -o simple_process ../../tools/simple_process/simple_process.c
	gcc -o page-types ../../tools/page-types.c
	cp simple_process $mnt/$GUEST_DIR
	cp page-types $mnt/$GUEST_DIR
	sed -i -e "s#GUEST_DIR#$GUEST_DIR#g" $mnt/$guest_script
	cat $host_key_pub >> $mnt/root/.ssh/authorized_keys
        kvm_ras=/etc/init.d/kvm_ras
	sed -e "s#EARLYKILL#$early_kill#g" \
	-e "s#GUESTRUN#$guest_script#g" $guest_init > $mnt/$kvm_ras
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
	            qemu-system-x86_64 -hda $image -kernel $kernel -initrd $initrd --append "$append" \
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
	    echo "Start the default kernel on guest system"
	    qemu-system-x86_64 -hda $image \
	    -m $RAM_size -net nic,model=rtl8139 -net user,hostfwd=tcp::5555-:22 \
	    -monitor pty -serial pty -pidfile $pid_file > $host_start 2>&1 &
	    sleep 5
	fi
	monitor_console=`awk '{print $NF}' $host_start | sed -n -e '1p'`
	serial_console=`awk '{print $NF}' $host_start | sed -n -e '2p'`
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
            ssh -i $host_key_priv -o StrictHostKeyChecking=no localhost -p 5555 echo "" > /dev/null 2>&1
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
	localhost:$guest_tmp $HOST_DIR/guest_tmp > /dev/null 2>&1
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
	HOST_VIRT=`awk '/qemu|QEMU/{next} {print $NF}' $monitor_console_output |cut -b 3-11`
	echo "Host virtual address is $HOST_VIRT"

	#Get Host physical address
	./page-types -p $QEMU_PID -LN -b anon | grep $HOST_VIRT > $host_tmp
	sleep 5
	ADDR=`cat $host_tmp | awk '{print "0x"$2"000"}' `
	echo "Host physical address is $ADDR"
}

error_inj()
{
	#Inject SRAO error
	cat $mce_inject_file > $mce_inject_data
	echo "ADDR $ADDR" >> $mce_inject_data
	echo "calling mce-inject $mce_inject_data"
	mce-inject $mce_inject_data
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
	check_guest_klog
	if [ $? -ne 0 ]; then
            echo 'FAIL: Did not get expected log!'
            kill -9 $QEMU_PID
	    exit 1
	else
	    echo 'PASS: Inject error into guest!'
	fi
	sleep 10
	check_guest_alive
	if [ $? -ne 0 ]; then
            echo 'FAIL: Guest System could have died!'
	else
	    echo 'PASS: Guest System alive!'
	fi
    fi
fi

rm -f guest_tmp $host_start $monitor_console_output $serail_console_output $host_tmp $pid_file $mce_inject_data
rm -f ./simple_process ./page-types
