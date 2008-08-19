#!/bin/sh -xe
#
# Setup environment for executing command remotely.
#
# Copyright (C) 2008-2009, Intel Corp.
#   Author: Huang Ying <ying.huang@intel.com>
#
# This file is released under the GPLv2.
#

sd=$(dirname "$0")
export ROOT=`(cd $sd/../..; pwd)`

. $ROOT/lib/functions.sh
setup_path
. $ROOT/lib/dirs.sh

eval $@
