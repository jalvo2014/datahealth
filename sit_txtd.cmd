rem Prepare txt files for datahealth.pl
perl \support\itm\bin\tems2sql.pl -txt -o -s NODE -s NODELIST -tc NODE,NODETYPE,NODELIST,LSTDATE \support\itm\dat\kib.cat  QA1CNODL.DB
perl \support\itm\bin\tems2sql.pl -txt -o -s NODE -tc NODE,O4ONLINE,PRODUCT,VERSION,HOSTADDR,RESERVED,THRUNODE,HOSTINFO,AFFINITIES \support\itm\dat\kib.cat  QA1DNSAV.DB
perl \support\itm\bin\tems2sql.pl -txt -o -s SITNAME -tlim 0 -tc SITNAME,AUTOSTART,LSTDATE,REEV_DAYS,REEV_TIME,SITINFO,PDT \support\itm\dat\kib.cat  QA1CSITF.DB
perl \support\itm\bin\tems2sql.pl -txt -o -s ID -tc ID,LSTDATE,FULLNAME \support\itm\dat\kib.cat  QA1DNAME.DB
perl \support\itm\bin\tems2sql.pl -txt -o -s OBJCLASS -s OBJNAME -s NODEL -tc OBJCLASS,OBJNAME,NODEL,LSTDATE \support\itm\dat\kib.cat  QA1DOBJA.DB
perl \support\itm\bin\tems2sql.pl -txt -o -s ID -tc GRPCLASS,ID,LSTDATE,GRPNAME \support\itm\dat\kib.cat  QA1DGRPA.DB
perl \support\itm\bin\tems2sql.pl -txt -o -s ID -tc GRPCLASS,ID,LSTDATE,OBJCLASS,OBJNAME  \support\itm\dat\kib.cat  QA1DGRPI.DB
perl \support\itm\bin\tems2sql.pl -txt -o -s ID -tc ID,LSTDATE,LSTUSRPRF          \support\itm\dat\kib.cat  QA1DEVSR.DB
perl \support\itm\bin\tems2sql.pl -txt -o -sql SYSTABLES -x RECORDTYPE!=! \support\itm\dat\kds.cat QA1CDSCA.DB
perl \support\itm\bin\tems2sql.pl -txt -o -s KEY -tc KEY,LSTDATE,NAME          \support\itm\dat\kib.cat  QA1DCCT.DB
perl \support\itm\bin\tems2sql.pl -txt -o -s KEY -tc ID,LSTDATE,MAP            \support\itm\dat\kib.cat  QA1DEVMP.DB
perl \support\itm\bin\tems2sql.pl -txt -o -s PCYNAME -tc PCYNAME,LSTDATE,AUTOSTART \support\itm\dat\kib.cat  QA1DPCYF.DB
perl \support\itm\bin\tems2sql.pl -txt -o -s PCYNAME -s ACTNAME -tc ACTNAME,PCYNAME,LSTDATE,TYPESTR,ACTINFO      \support\itm\dat\kib.cat  QA1DACTP.DB
perl \support\itm\bin\tems2sql.pl -txt -o -s ID  -tc ID,LSTDATE,NAME \support\itm\dat\kib.cat  QA1DCALE.DB
perl \support\itm\bin\tems2sql.pl -txt -o -s ID  -tc ID,LSTDATE,SITNAME \support\itm\dat\kib.cat  QA1DOVRD.DB
perl \support\itm\bin\tems2sql.pl -txt -o -s ID  -tc ID,LSTDATE,ITEMID,CALID \support\itm\dat\kib.cat  QA1DOVRI.DB
perl \support\itm\bin\tems2sql.pl -txt -o -s OBJNAME -tc GBLTMSTMP,OBJNAME,OPERATION,TABLENAME \support\itm\dat\kib.cat  QA1CEIBL.DB
perl \support\itm\bin\tems2sql.pl -txt -o -s OBJNAME -x DELTASTAT=S -x DELTASTAT=P -tlim 0 -tc GBLTMSTMP,DELTASTAT,SITNAME,NODE,ORIGINNODE,ATOMIZE \support\itm\dat\kib.cat  QA1CSTSH.DB
perl \support\itm\bin\tems2sql.pl -txt -o -s NAME -tc NAME,RESERVED \support\itm\dat\kib.cat  QA1CCKPT.DB
