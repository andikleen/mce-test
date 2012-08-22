#!/bin/bash

cat <<-EOF

***************************************************************************
Pay attention:

This is the functional test for transparent huge page support of HWPoison.
***************************************************************************


EOF

echo 0 > $TMP_DIR/error.$$

pushd `dirname $0` > /dev/null
./run-transhuge-test.sh
[ $? -eq 0 ] || echo 1 > $TMP_DIR/error.$$
popd > /dev/null

grep -q "1" $TMP_DIR/error.$$
if [ $? -eq 0 ]
then
	exit 1
else
	exit 0
fi
