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

killall simple_process

cd GUEST_DIR

./simple_process > /dev/null &

./page-types -p `pidof simple_process` -LN -b anon > guest_page
if [ -s guest_page ]; then
	ADDR_KLOG=`awk 'NR > 3 {print "0x"$2}' guest_page | sed -n -e '1p'`
	ADDR=`echo $ADDR_KLOG"000"`
	echo "guest physical address is $ADDR" > guest_tmp
fi

