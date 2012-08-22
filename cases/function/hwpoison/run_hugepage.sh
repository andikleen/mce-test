#!/bin/bash

cat <<-EOF

***************************************************************************
Pay attention:

This is the functional test for huge page support of HWPoison.
***************************************************************************


EOF

pushd `dirname $0` > /dev/null

HT=$TMP_DIR/hugepage
mkdir -p $HT
mount -t hugetlbfs none $HT
./run-huge-test.sh $HT
umount $HT
popd > /dev/null
