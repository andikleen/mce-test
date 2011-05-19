#!/bin/bash

# APEI ERST firmware interface and implementation has no multiple users
# in mind. For example, there is four records in storage with ID: 1, 2,
# 3 and 4, if two ERST readers enumerate the records via
# GET_NEXT_RECORD_ID as follow,
#
# reader 1             reader 2
# 1
#                      2
# 3
#                      4
# -1
#                      -1
#
# where -1 signals there is no more record ID.
#
# Reader 1 has no chance to check record 2 and 4, while reader 2 has no
# chance to check record 1 and 3. And any other GET_NEXT_RECORD_ID will
# return -1, that is, other readers will has no chance to check any
# record even they are not cleared by anyone.
#
# This makes raw GET_NEXT_RECORD_ID not suitable for usage of multiple
# users.
#
# This issue has been resolved since 2.6.39-rc1, so please run this case
# with Linux kernel >=2.6.39-rc1
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public
# License as published by the Free Software Foundation; version 2.
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
# Copyright (C) 2011, Intel Corp.
# Author: Chen Gong <gong.chen@intel.com>
#


ID=0xdeadbeaf
ERST=./erst-inject
LOG=./erst.log
MODSTATUS=0

err()
{
       echo "$*"
       echo "test fails"
       exit 1
}

#prepare the test env
ls /dev/erst_dbg >/dev/null 2>&1
if [ ! $? -eq 0 ]; then
       modinfo erst_dbg > /dev/null 2>&1
       [ $? -eq 0 ] || err "please ensure module erst_dbg existing"
       modprobe erst_dbg
       [ $? -eq 0 ] || err "fail to load module erst_dbg"
       MODSTATUS=1
fi

ls $ERST > /dev/null 2>&1
[ $? -eq 0 ] || err "please compile the test program first"

echo "write one error record into ERST..."
$ERST -i $ID 1>/dev/null
if [ ! $? -eq 0 ]; then
       err "ERST writing operation fails"
fi
echo "done"
# read all error records in ERST
$ERST -p > $LOG
echo "check if existing the error record written before..."
grep -q $ID $LOG
if [ ! $? -eq 0 ]; then
       err "don't find the error record written before in ERST"
fi
echo "done"

echo "clear the error record written before..."
$ERST -c $ID 1>/dev/null
if [ ! $? -eq 0 ]; then
       err "ERST writing opertion fails"
fi
echo "done"

#read all error records again
$ERST -p > $LOG

echo "check if the error record has been cleared..."
grep -q $ID $LOG
if [ $? -eq 0 ]; then
       err "ERST clearing opertion fails"
fi
echo "done"
echo -e "\ntest passes"

rm -f $LOG
if [ $MODSTATUS -eq 1 ]; then
       rmmod -f erst_dbg
fi
