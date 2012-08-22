#!/bin/bash
# This test is the SRAR/DCU functional test.
#

cat <<-EOF

***************************************************************************
Pay attention:

This test is SRAR functional test. It is for DCU part(L1 Data Cache). The
test highly depends on BIOS implementation, which means if BIOS is bogus,
it is possible to cause system hang/crash. If meeting this situation,
please test again after rebooot or just skip this test.
***************************************************************************


EOF

echo 0 > $TMP_DIR/error.$$

pushd `dirname $0` > /dev/null
./srar_recovery.sh -d
[ $? -eq 0 ] || echo 1 > $TMP_DIR/error.$$
popd > /dev/null

grep -q "1" $TMP_DIR/error.$$
if [ $? -eq 0 ]
then
        exit 1
else
        exit 0
fi

