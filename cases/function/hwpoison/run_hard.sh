#!/bin/bash

cat <<-EOF

***************************************************************************
Pay attention:

This test is hard mode of HWPoison functional test.
***************************************************************************


EOF

echo 0 > $TMP_DIR/error.$$

pushd `dirname $0` > /dev/null
./tinjpage
./tsimpleinj
if ! ./tkillpoison
then
	echo "killed as expected"
else
	echo "didn't get killed"
	echo 1 > $TMP_DIR/error.$$
fi
./tprctl

popd > /dev/null

grep -q "1" $TMP_DIR/error.$$
if [ $? -eq 0 ]
then
	exit 1
else
	exit 0
fi
