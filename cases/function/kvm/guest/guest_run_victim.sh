#!/bin/bash
#
# Test script for SRAR error injection
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
# Copyright (C) 2015, Intel Corp.
# Author: Wen Jin <wenx.jin@intel.com>
#

killall victim
cat /dev/null > /var/log/mcelog
sleep 1

cd GUEST_DIR/victim
gcc -o victim victim.c
cd ..

./victim/victim -k 0 -d > guest_phys &
sleep 1

if [ -s guest_phys ]; then
	ADDR=`cat guest_phys | awk '{print $NF}'`
	echo "guest physical address is $ADDR" > guest_tmp
fi

