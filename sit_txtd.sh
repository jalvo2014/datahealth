#!/bin/sh
#if [ "$1" = "" ]; then
#echo missing directory to user data;
#exit 1;
#fi
TOOLKIT='/common/public/tools/ITM6_Debug_Toolkit'
DATADIR=$1
perl ${TOOLKIT}/tems2sql.pl -txt -o -s NODE -s NODELIST -tc NODE,NODETYPE,NODELIST,LSTDATE ${TOOLKIT}/kib.cat  ${DATADIR}QA1CNODL.DB
perl ${TOOLKIT}/tems2sql.pl -txt -o -s NODE -tc NODE,O4ONLINE,PRODUCT,VERSION,HOSTADDR,RESERVED,THRUNODE,HOSTINFO,AFFINITIES ${TOOLKIT}/kib.cat  ${DATADIR}QA1DNSAV.DB
perl ${TOOLKIT}/tems2sql.pl -txt -o -s SITNAME -tlim 0 -tc SITNAME,AUTOSTART,LSTDATE,REEV_DAYS,REEV_TIME,SITINFO,PDT ${TOOLKIT}/kib.cat  ${DATADIR}QA1CSITF.DB
perl ${TOOLKIT}/tems2sql.pl -txt -o -s ID -tc ID,LSTDATE,FULLNAME ${TOOLKIT}/kib.cat  ${DATADIR}QA1DNAME.DB
perl ${TOOLKIT}/tems2sql.pl -txt -o -s OBJCLASS -s OBJNAME -s NODEL -tc OBJCLASS,OBJNAME,NODEL,LSTDATE ${TOOLKIT}/kib.cat  ${DATADIR}QA1DOBJA.DB
perl ${TOOLKIT}/tems2sql.pl -txt -o -s ID -tc GRPCLASS,ID,LSTDATE,GRPNAME ${TOOLKIT}/kib.cat  ${DATADIR}QA1DGRPA.DB
perl ${TOOLKIT}/tems2sql.pl -txt -o -s ID -tc GRPCLASS,ID,LSTDATE,OBJCLASS,OBJNAME  ${TOOLKIT}/kib.cat  ${DATADIR}QA1DGRPI.DB
perl ${TOOLKIT}/tems2sql.pl -txt -o -s ID -tc ID,LSTDATE,LSTUSRPRF          ${TOOLKIT}/kib.cat  ${DATADIR}QA1DEVSR.DB
perl ${TOOLKIT}/tems2sql.pl -txt -o -sql SYSTABLES -x RECORDTYPE!=! ${TOOLKIT}/kds.cat ${DATADIR}QA1CDSCA.DB
perl ${TOOLKIT}/tems2sql.pl -txt -o -s KEY -tc KEY,LSTDATE,NAME          ${TOOLKIT}/kib.cat  ${DATADIR}QA1DCCT.DB
perl ${TOOLKIT}/tems2sql.pl -txt -o -s KEY -tc ID,LSTDATE,MAP            ${TOOLKIT}/kib.cat  ${DATADIR}QA1DEVMP.DB
perl ${TOOLKIT}/tems2sql.pl -txt -o -s PCYNAME -tc PCYNAME,LSTDATE,AUTOSTART ${TOOLKIT}/kib.cat  ${DATADIR}QA1DPCYF.DB
perl ${TOOLKIT}/tems2sql.pl -txt -o -s PCYNAME -s ACTNAME -tc ACTNAME,PCYNAME,LSTDATE,TYPESTR,ACTINFO      ${TOOLKIT}/kib.cat  ${DATADIR}QA1DACTP.DB
perl ${TOOLKIT}/tems2sql.pl -txt -o -s ID  -tc ID,LSTDATE,NAME ${TOOLKIT}/kib.cat  ${DATADIR}QA1DCALE.DB
perl ${TOOLKIT}/tems2sql.pl -txt -o -s ID  -tc ID,LSTDATE,SITNAME ${TOOLKIT}/kib.cat  ${DATADIR}QA1DOVRD.DB
perl ${TOOLKIT}/tems2sql.pl -txt -o -s ID  -tc ID,LSTDATE,ITEMID,CALID ${TOOLKIT}/kib.cat  ${DATADIR}QA1DOVRI.DB
perl ${TOOLKIT}/tems2sql.pl -txt -o -s OBJNAME -tc GBLTMSTMP,OBJNAME,OPERATION,TABLENAME ${TOOLKIT}/kib.cat  ${DATADIR}QA1CEIBL.DB
perl ${TOOLKIT}/tems2sql.pl -txt -o -s OBJNAME -x DELTASTAT=S -x DELTASTAT=P -tlim 0 -tc GBLTMSTMP,DELTASTAT,SITNAME,NODE,ORIGINNODE,ATOMIZE ${TOOLKIT}/kib.cat  ${DATADIR}QA1CSTSH.DB
perl ${TOOLKIT}/tems2sql.pl -txt -o -s NAME -tc NAME,RESERVED ${TOOLKIT}/kib.cat  ${DATADIR}QA1CCKPT.DB
