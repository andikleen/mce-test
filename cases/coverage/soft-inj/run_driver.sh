#!/bin/bash

echo 0 > $TMP_DIR/error.$$

pushd `dirname $0` > /dev/null
./driver_kdump.sh config/kdump.conf
[ $? -eq 0 ] || echo 1 > $TMP_DIR/error.$$
popd > /dev/null

grep -q "1" $TMP_DIR/error.$$
if [ $? -eq 0 ]
then
	exit 1
else
	exit 0
fi

