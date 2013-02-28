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

cat <<-EOF

***************************************************************************
Pay attention:

This test is basic APEI/ERST functional test. In this test case, it will
test ERST functionality of READ/WRITE/ERASE. Any error in the test
procedure will be considered as failure and reported.

Because the ERST test maybe damges the data in the ERST table, please
restore the valid data in the ERST to the other safe place.

***************************************************************************


EOF

TMP="../../../work"
TMP_DIR=${TMP_DIR:-$TMP}
if [ ! -d $TMP_DIR ]; then
	TMP_DIR=$TMP
fi
export TMP_DIR

ERST=./erst-inject
LOG=$TMP_DIR/erst.log.$$
MODSTATUS=0

err()
{
	echo
	echo -e ERROR: "$*"
	echo ERROR: "Please check dmesg or log for further information"
	echo -e "\n\nTEST FAILS"
	exit 1
}

pushd `dirname $0` > /dev/null

#prepare the test env
ls /dev/erst_dbg >/dev/null 2>&1
if [ $? -ne 0 ]; then
	modinfo erst_dbg > /dev/null 2>&1
	[ $? -eq 0 ] || err "Please ensure module erst_dbg existing"
	modprobe erst_dbg
	[ $? -eq 0 ] || err "Fail to load module erst_dbg"
	MODSTATUS=1
fi

which $ERST &> /dev/null
[ $? -eq 0 ] || err "Please compile the test case first"

# If ERST table is full, the test can't proceed. To ensure below
# test can go on, if existing records, remove one first.
COUNT=`$ERST -n|cut -d' ' -f5`
if [ $COUNT -ne 0 ]; then
	ID=`$ERST -p|grep "rcd id"|head -1|cut -d' ' -f3`
	$ERST -c $ID 1>/dev/null
fi

ID=0xdeadbeaf
echo -n "Write one error record into ERST... "
$ERST -i $ID 1>/dev/null
if [ ! $? -eq 0 ]; then
	err "ERST writing operation fails.\n"\
"Please confirm if command parameter erst_disable is used or hardware not available"
fi
sleep 1
echo "DONE"
# read all error records in ERST
$ERST -p > $LOG
echo -n "Check if existing the error record written before... "
grep -q $ID $LOG
if [ ! $? -eq 0 ]; then
	err "Don't find the error record written before in ERST"
fi
sleep 1
echo "DONE"

echo -n "Clear the error record written before... "
$ERST -c $ID 1>/dev/null
if [ ! $? -eq 0 ]; then
	err "ERST writing opertion fails"
fi
sleep 1
echo "DONE"

#read all error records again
$ERST -p > $LOG

echo -n "Check if the error record has been cleared... "
grep -q $ID $LOG
if [ $? -eq 0 ]; then
	err "ERST clearing opertion fails"
fi
sleep 1
echo "DONE"

popd > /dev/null

rm -f $LOG
if [ $MODSTATUS -eq 1 ]; then
	rmmod -f erst_dbg
fi

echo -e "\nTEST PASSES"

