#! /bin/bash
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
# Copyright (C) 2012, Intel Corp.
#

cat <<-EOF

***************************************************************************
Pay attention:

This test is for HWPoison stress test. In this test case, it will
try to inject errors via soft-offline instead of madvice. Usually
this test needs to touch many pages and no failure happens on these pages.
The test is always considered as PASS, even if failure happens in test
procedure. When meeting this situation, please contact experts to confirm
whether or not it is a real error.
***************************************************************************


EOF

TMP="../../../work"
TMP_DIR=${TMP_DIR:-$TMP}
if [ ! -d $TMP_DIR ]; then
	TMP_DIR=$TMP
fi
export TMP_DIR

echo 0 > $TMP_DIR/error.$$

pushd `dirname $0` > /dev/null
echo "run soft stress tester for 60 seconds"
./hwpoison.sh -T -C 1 -t 60 -S
[ $? -eq 0 ] || echo 1 > $TMP_DIR/error.$$
popd > /dev/null

grep -q "1" $TMP_DIR/error.$$
if [ $? -eq 0 ]
then
	exit 1
else
	exit 0
fi

