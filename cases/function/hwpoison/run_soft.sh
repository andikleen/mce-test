#!/bin/bash

pushd `dirname $0` > /dev/null

. ./helpers.sh

cat <<-EOF

***************************************************************************
Pay attention:

This test is soft mode of HWPoison functional test.
***************************************************************************


EOF

echo "------------------------------------------------------------------------"
echo "Running tsoft (simple soft offline test)"
run_test ./tsoft success

echo "------------------------------------------------------------------------"
echo "Running tsoftinj (soft offline test on various types of pages)"
mount_hugetlbfs
run_test ./tsoftinj success
unmount_hugetlbfs

echo "------------------------------------------------------------------------"
echo "Running random_offline (random soft offline test for 60 seconds)"
run_test "./random_offline -t 60" sucess

free_resources

show_summary

popd > /dev/null

exit $failed_testcase
