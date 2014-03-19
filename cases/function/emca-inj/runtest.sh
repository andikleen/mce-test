#!/bin/bash

cat <<-EOF

***************************************************************************
Pay attention:

This is basic eMCA functional test. By now only eMCA Gen1 is supported,
which means only Corrected Error injection/trigger is doable.
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
./emca-inject.sh 0x8
[ $? -eq 0 ] || echo 1 > $TMP_DIR/error.$$
popd > /dev/null

grep -q "1" $TMP_DIR/error.$$
if [ $? -eq 0 ]
then
	exit 1
else
	exit 0
fi

