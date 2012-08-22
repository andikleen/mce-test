#!/bin/bash
# This test is the basic EINJ functional test. Only Memory Correctable Error
# is touched because other tests are possible to cause system hang/crash.
#
#0x00000008      Memory Correctable
#0x00000010      Memory Uncorrectable non-fatal
#0x00000020      Memory Uncorrectable fatal

cat <<-EOF

***************************************************************************
Pay attention:

This test is basic APEI/EINJ functional test. Because other error injections
are possible to cause system hang/crash, only Memory Correctable Error is
injected to test the availiability of APEI/EINJ.
***************************************************************************


EOF

echo 0 > $TMP_DIR/error.$$

pushd `dirname $0` > /dev/null
./apei-inject.sh 0x8
[ $? -eq 0 ] || echo 1 > $TMP_DIR/error.$$
popd > /dev/null

grep -q "1" $TMP_DIR/error.$$
if [ $? -eq 0 ]
then
	exit 1
else
	exit 0
fi

