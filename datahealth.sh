#!/bin/sh
export DATADIR=$1
sh /common/public/tools/ITM6_Debug_Toolkit/sit_txtd.sh $1
perl /common/public/tools/ITM6_Debug_Toolkit/datahealth.pl -txt
