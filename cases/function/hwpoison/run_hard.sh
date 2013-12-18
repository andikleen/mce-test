#!/bin/bash

pushd `dirname $0` > /dev/null

. ./helpers.sh

load_hwpoison_inject

# make sure we have no hwpoisoned hugepage before starting this test.
free_resources > /dev/null

cat <<-EOF

***************************************************************************
Pay attention:

This test is hard mode of HWPoison functional test.
***************************************************************************


EOF

echo "------------------------------------------------------------------------"
echo "Running tsimpleinj (simple hard offline test)"
run_test ./tkillpoison failure

echo "------------------------------------------------------------------------"
echo "Running tsimpleinj (simple hard offline test)"
run_test ./tsimpleinj success

echo "------------------------------------------------------------------------"
echo "Running tinjpage (hard offline test on various types of pages)"
mount_hugetlbfs
run_test ./tinjpage success
unmount_hugetlbfs

echo "------------------------------------------------------------------------"
echo "Running tprctl (hard offline test with various prctl settings)"
run_test ./tprctl success

free_resources

show_summary

popd > /dev/null

exit $failed_testcase
