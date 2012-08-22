#!/bin/bash

cat <<-EOF

***************************************************************************
Pay attention:

This test is soft mode of HWPoison functional test.
***************************************************************************


EOF

pushd `dirname $0` > /dev/null

./tsoft
./tsoftinj
echo "Running soft offline for 60 seconds"
./random_offline -t 60

popd > /dev/null
