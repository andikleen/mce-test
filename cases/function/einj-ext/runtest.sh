#!/bin/bash

cat <<-EOF

***************************************************************************
Pay attention:

This is a functional test for ACPI5.0 extension support for EINJ, including
regular EINJ error injection test and Vendor Extension Specific Error
Injection test with ACPI5.0 enabled BIOS.
***************************************************************************

EOF

TMP="../../../work"
export TMP_DIR=${TMP_DIR:-$TMP}

echo 0 > $TMP_DIR/error.$$

pushd `dirname $0` > /dev/null
./einj-ext.sh
[ $? -eq 0 ] || echo 1 > $TMP_DIR/error.$$
popd > /dev/null

grep -q "1" $TMP_DIR/error.$$
if [ $? -eq 0 ]
then
	exit 1
else
	exit 0
fi


