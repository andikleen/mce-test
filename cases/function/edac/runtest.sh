#!/bin/bash
# This test is used to validate EDAC function for RAS. Only check EDAC
# relative information in dmesg output when inject Memory Correctable
# Error with EINJ tool.

cat <<-EOF

***************************************************************************
Pay attention:

EDAC subsystem is a hardware specific driver to report hardware related error,
here only Memory Correctable Error is checked.
This test is used for verifying EDAC driver by checking if its output can
keep correct under different kernel release via comparing against a reference
result run earlier or on earlier kernel version.
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
./edac.sh
[ $? -eq 0 ] || echo 1 > $TMP_DIR/error.$$
popd > /dev/null

grep -q "1" $TMP_DIR/error.$$
if [ $? -eq 0 ]
then
	exit 1
else
	exit 0
fi

