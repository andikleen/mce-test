#!/bin/bash

usage()
{
	cat <<-EOF
	This script is used to add CPU load in the test procedure.
	Please kill tese loads in the background after the tests.

	usage: ${0##*/} [program to load]
	example: ${0##*/} ./load.sh ./busy

	EOF

	exit 0
}


[ X"$1" = X ] && usage

cpu=`cat /proc/cpuinfo |grep -c processor`
cpu=`expr $cpu - 1`
for i in `seq 0 $cpu`
do
	taskset -c $i $1 &
done
