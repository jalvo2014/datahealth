#!/usr/local/bin/perl -w
#------------------------------------------------------------------------------
# Licensed Materials - Property of IBM (C) Copyright IBM Corp. 2010, 2010
# All Rights Reserved US Government Users Restricted Rights - Use, duplication
# or disclosure restricted by GSA ADP Schedule Contract with IBM Corp
#------------------------------------------------------------------------------

#  perl datahealth.pl
#
#  Identify cases where TEMS database is inconsistent
#   Version 0.60000 checks TNODESAV and TNODELST
#
#  john alvord, IBM Corporation, 5 July 2014
#  jalvord@us.ibm.com
#
# tested on Windows Activestate 5.16.2
# Should work on Linux/Unix but not yet tested
#
# $DB::single=2;   # remember debug breakpoint

## todos
#
#  TSITDESC multiple identical SITNAMEs
#

#use warnings::unused; # debug used to check for unused variables
use strict;
use warnings;

# See short history at end of module

my $gVersion = "0.60000";
my $gWin = (-e "C://") ? 1 : 0;    # 1=Windows, 0=Linux/Unix

use Data::Dumper;               # debug only

# a collection of variables which are used throughout the program.
# defined globally

my $args_start = join(" ",@ARGV);      # capture arguments for later processing
my $run_status = 0;                    # A count of pending runtime errors - used to allow multiple error detection before stopping process

# some common variables

#y @list = ();                         # used to get result of good SOAP capture
#y @alist = ();                        # used to get result of good SOAP capture descending order
my $rc;
my $node;
my $myargs;
my $survey_sqls = 0;                     # count of SQLs
my $survey_sql_time = 0;                 # record total elapsed time in SQL processing
my @words = ();
my $rt;
my $debugfile;
my $ll;
my $pcount;
my $oneline;
my $sx;
my $i;
my $exit_code;

# forward declarations of subroutines

sub init;                                # read command line and ini file
sub logit;                               # queue one record to survey log
sub datadumperlog;                       # dump a variable using Dump::Data if installed
sub gettime;                             # get time
sub init_txt;                            # input from txt files
sub init_lst;                            # input from lst files
sub parse_lst;                           # parse the KfwSQLClient output

my $sitdata_start_time = gettime();     # formated current time for report

# TNODELST type V record data           Vive records - list time connected
my $vlx;
my $nlistvi = -1;
my @nlistv = ();
my %nlistvx = ();
my @nlistv_thrunode = ();
my @nlistv_tems = ();
my @nlistv_not = ();
my @nlistv_ct = ();

# TNODELST type M record data           Managed Systemlists
my $mlx;
my $nlistmi = -1;
my @nlistm = ();
my %nlistmx = ();
my @nlistm_miss = ();
my @nlistm_nov = ();

my $mkey;
my $mlisti = -1;
my @mlist = ();
my %mlistx = ();
my @mlist_ct;


# TNODESAV record data                  Disk copy of INODESTS [mostly]
my $nsx;
my $nsavei = -1;
my @nsave = ();
my %nsavex = ();
my @nsave_product = ();
my @nsave_version = ();
my @nsave_sysmsl = ();
my @nsave_ct = ();

my $tx;                                  # TEMS information
my $temsi = -1;                          # count of TEMS
my @tems = ();                           # Array of TEMS names
my %temsx = ();                          # Hash to TEMS index
my @tems_hub = ();                       # When 1, is the hub TEMS
my @tems_ct = ();                        # Count of managed systems
my @tems_version = ();                   # TEMS version number
my $hub_tems = "";                       # hub TEMS nodeid

my $snx;
my $snodei = -1;
my @snode = ();
my %snodex = ();

my $o_file = "datahealth.csv";


# Situation Group related data
my $gx;
my $grpi = -1;
my @grp = ();
my %grpx = ();
my @grp_sit = ();
my @grp_grp = ();
my %sum_sits = ();

# Situation related data

my $siti = -1;                             # count of situations
my $curi;                                  # global index for subroutines
my @sit = ();                              # array of situations
my @sit_pdt = ();                          # array of predicates or situation formula
my @sit_fullname = ();                     # array of fullname
my @sit_psit = ();                         # array of printable situaton names
my @sit_sitinfo = ();                      # array of SITINFO columns
my @sit_autostart = ();                    # array of AUTOSTART columns
my %sitx = ();                             # Index from situation name to index
my @sit_value = ();                        # count of *VALUE
my @sit_sit = ();                          # count of *SIT
my @sit_str = ();                          # count of *STR
my @sit_scan = ();                         # count of *SCAN
my @sit_scan_ne = ();                      # count of *SCAN with invalid *NE
my @sit_change = ();                       # count of *CHANGE
my @sit_pctchange = ();                    # count of *PCTCHANGE
my @sit_count = ();                        # count of *COUNT
my @sit_count_zero = ();                   # count of *COUNT w/value zero
my @sit_count_ltone = ();                  # count of *COUNT *LT/*LE 1
my @sit_count_lt = ();                     # count of *COUNT *LT/*LE more then 1
my @sit_min = ();                          # count of *MIN
my @sit_max = ();                          # count of *MAX
my @sit_avg = ();                          # count of *AVG
my @sit_sum = ();                          # count of *SUM
my @sit_time = ();                         # count of *TIME
my @sit_time_same = ();                    # count of *TIME with same attribute table [bad]
my @sit_until_ttl = ();                    # value of UNTIL/*TTL
my @sit_until_sit = ();                    # value of UNTIL/*SIT
my @sit_tables = ();                       # list of attribute groups
my @sit_alltables = ();                    # list of all attribute groups
my @sit_missing = ();                      # count of *MISSING
my @sit_ms_offline = ();                   # count of MS_Offline type tests
my @sit_ms_online = ();                    # count of MS_Online type tests
my @sit_reason_ne_fa = ();                 # count of reason ne FA cases
my @sit_syntax = ();                       # syntax error caught
my @sit_persist = ();                      # persist count
my @sit_cmd = ();                          # 1 if CMD is present
my @sit_cmdtext = ();                      # cmd text
my @sit_autosopt = ();                     # autosopt column
my @sit_atom = ();                         # 1 if DisplayItem
my @sit_ProcessFilter = ();                # 1 if process Filter present
my @sit_alwaystrue = ();                   # 1 if always true *value test
my @sit_reeval = ();                       # sampling interval in seconds
my @sit_filter = ();                       # Where filtered
my @sit_dist = ();                         # When 1, distributed
my @sit_dist_objaccl = ();                 # Situation Distributions in TOBJACCL and TGROUP/TGROUPI
my @sit_process = ();                      # Process type attribute group
my @sit_fileinfo = ();                     # File Information type attribute group
my @sit_history_collect  = ();             # If History collection file, where collected - IRA or CMS
my @sit_history_interval = ();             # If History collection file, how often collected in seconds
my @sit_history_export   = ();             # If History collection file, how many collections before export
my $sit_distribution = 0;                  # when 1, distributions are present

my $sit_tems_alert = 0;
my $sit_tems_alert_run = 0;
my $sit_tems_alert_dist = 0;


# option and ini file variables variables

my $opt_txt;                    # input from .txt files
my $opt_txt_tnodelst;           # TNODELIST txt file
my $opt_txt_tnodesav;           # TNODESAV txt file
my $opt_lst;                    # input from .lst files
my $opt_lst_tnodesav;           # TNODESAV lst file
my $opt_lst_tnodelst;           # TNODELST lst file
my $opt_log;                    # name of log file
my $opt_ini;                    # name of ini file
my $opt_debuglevel;             # Debug level
my $opt_debug;                  # Debug level
my $opt_h;                      # help file
my $opt_v;                      # verbose flag
my $opt_dpr;                    # dump data structure flag
my $opt_workdir;                # Directory where files are processed
my $opt_nohdr = 0;              # skip header to make regression testing easier

# do basic initialization from parameters, ini file and standard input

$rc = init($args_start);

$opt_log = $opt_workdir . $opt_log;
open FH, ">>$opt_log" or die "can't open $opt_log: $!";

logit(0,"SITAUDIT000I - ITM_Situation_Audit $gVersion $args_start");

# process three different sources of situation data

if ($opt_txt == 1) {                    # text files
   $rc = init_txt();
} elsif ($opt_lst == 1) {               # KfwSQLClient LST files
   $rc = init_lst();
}

$o_file = $opt_workdir . $o_file;
\
open OH, ">$o_file" or die "can't open $o_file: $!";


my $advi = -1;
my @advonline = ();
my @advsit = ();
my @advimpact = ();
my @advcode = ();
my %advx = ();
my $hubi;
my $max_adv = -1;

$hubi = $temsx{$hub_tems};

for ($i=0; $i<=$nlistvi; $i++) {
   my $node1 = $nlistv[$i];
   next if $nlistv_tems[$i] eq "";
   my $tems1 = $nlistv_tems[$i];
   my $tx = $temsx{$tems1};
   next if !defined $tx;
   $tems_ct[$tx] += 1;
   $tems_ct[$hubi] += 1;
}


for ($i=0; $i<=$nsavei; $i++) {
   my $node1 = $nsave[$i];
   next if $nsave_product[$i] eq "EM";
   $nsx = $nlistvx{$node1};
   next if defined $nsx;
   $advi++;$advonline[$advi] = "Node present in node status but missing in TNODELIST Type V records";
   $advcode[$advi] = "DATAHEALTH1001E";
   $advimpact[$advi] = 100;
   $advsit[$advi] = $node1;
}

for ($i=0; $i<=$nsavei; $i++) {
   next if $nsave_sysmsl[$i] == 1;
   next if $nsave_product[$i] eq "EM";
   my $node1 = $nsave[$i];
   $vlx = $nlistvx{$node1};
   if (defined $vlx) {
      next if $nlistv_thrunode[$vlx] ne $nlistv_tems[$vlx];
   }
   $advi++;$advonline[$advi] = "Node without a system generated MSL in TNODELIST Type M records";
   $advcode[$advi] = "DATAHEALTH1002E";
   $advimpact[$advi] = 75;
   $advsit[$advi] = $node1;
}

for ($i=0; $i<=$nlistmi; $i++) {
   my $node1 = $nlistm[$i];
   if ($nlistm_miss[$i] != 0) {
      $advi++;$advonline[$advi] = "Node present in TNODELST Type M records but missing in Node Status";
      $advcode[$advi] = "DATAHEALTH1003I";
      $advimpact[$advi] = 00;
      $advsit[$advi] = $node1;
   }
   if ($nlistm_nov[$i] != 0) {
      $advi++;$advonline[$advi] = "Node present in TNODELST Type M records but missing TNODELIST Type V records";
      $advcode[$advi] = "DATAHEALTH1004I";
      $advimpact[$advi] = 00;
      $advsit[$advi] = $node1;
   }
}

for ($i=0;$i<=$nsavei;$i++) {
   next if $nsave_ct[$i] == 1;
   $advi++;$advonline[$advi] = "TNODESAV duplicate nodes";
   $advcode[$advi] = "DATAHEALTH1007E";
   $advimpact[$advi] = 100;
   $advsit[$advi] = $nsave[$i];
}

for ($i=0;$i<=$nlistvi;$i++) {
   next if $nlistv_ct[$i] == 1;
   $advi++;$advonline[$advi] = "TNODELST Type V duplicate nodes";
   $advcode[$advi] = "DATAHEALTH1008E";
   $advimpact[$advi] = 100;
   $advsit[$advi] = $nlistv[$i];
}

for ($i=0;$i<=$mlisti;$i++) {
   next if $mlist_ct[$i] == 1;
   $advi++;$advonline[$advi] = "TNODELST Type M duplicate NODE/NODELIST";
   $advcode[$advi] = "DATAHEALTH1009E";
   $advimpact[$advi] = 100;
   $advsit[$advi] = $mlist[$i];
}

print OH "ITM Database Health report $gVersion\n";
print OH "\n";

my $hub_limit = 10000;
$hub_limit = 20000 if substr($tems_ct[$hubi],0,5) gt "06.23";
my $remote_limit = 1500;

if ($tems_ct[$hubi] > $hub_limit){
   $advi++;$advonline[$advi] = "Hub TEMS has $tems_ct[$hubi] managed systems which exceeds limits $hub_limit";
   $advcode[$advi] = "DATAHEALTH1005W";
   $advimpact[$advi] = 75;
   $advsit[$advi] = $hub_tems;
}


print OH "Hub,$hub_tems,$tems_ct[$hubi]\n";
for (my $i=0;$i<=$temsi;$i++) {
   next if $i == $hubi;
   if ($tems_ct[$i] > $remote_limit){
      $advi++;$advonline[$advi] = "Remote TEMS has $tems_ct[$i] managed systems which exceeds limits $remote_limit";
      $advcode[$advi] = "DATAHEALTH1006W";
      $advimpact[$advi] = 75;
      $advsit[$advi] = $tems[$i];
   }
   print OH "Remote,$tems[$i],$tems_ct[$i]\n";
}
print OH "\n";

my $tadvi = $advi + 1;
print OH "Advisory messages,$tadvi\n";

if ($advi != -1) {
   print OH "\n";
   print OH "Impact,Advisory Code,Object,Advisory\n";
   for (my $a=0; $a<=$advi; $a++) {
       my $mysit = $advsit[$a];
       my $myimpact = $advimpact[$a];
       my $mykey = $mysit . "|" . $a;
       $advx{$mykey} = $a;
   }
   foreach my $f ( sort { $advimpact[$advx{$b}] <=> $advimpact[$advx{$a}] ||
                          $advcode[$advx{$a}] cmp $advcode[$advx{$b}] ||
                          $advsit[$advx{$a}] cmp $advsit[$advx{$b}] ||
                          $advonline[$advx{$a}] cmp $advonline[$advx{$b}]
                        } keys %advx ) {
      my $j = $advx{$f};
      my $skipone = $advcode[$j];
      print OH "$advimpact[$j],$advcode[$j],$advsit[$j],$advonline[$j]\n";
      $max_adv = $advimpact[$j] if $advimpact[$j] > $max_adv;
   }
}
if ($max_adv <= 0) {
   $exit_code = 0;                     # no actionable advisory messages
} elsif ($max_adv <= 25) {
   $exit_code = 1;                     # minor advisory messages
} else {
   $exit_code = 2;                     # major actionable advisory messages
}

exit $exit_code;

# following routine gets data from txt files. tems2sql.pl is an internal only program which can
# extract data from a TEMS database file.

#perl \rexx\bin\tems2sql.pl -txt -s SITNAME -tlim 0 -tc SITNAME,AUTOSTART,SITINFO,CMD,AUTOSOPT,REEV_DAYS,REEV_TIME,PDT  c:\ibm\itm622\kib.cat  QA1CSITF.DB  > QA1CSITF.DB.TXT
#perl \rexx\bin\tems2sql.pl -txt -s ID -tc ID,FULLNAME  c:\ibm\itm622\kib.cat  QA1DNAME.DB  > QA1DNAME.DB.TXT

sub init_txt {
   my @klst_data;
   my $inode;
   my $inodelist;
   my $inodetype;

   my @ksav_data;
   my $io4online;
   my $iproduct;
   my $iversion;

   open(KSAV, "< $opt_txt_tnodesav") || die("Could not open TNODESAV $opt_txt_tnodesav\n");
   @ksav_data = <KSAV>;
   close(KSAV);

   # Get data for all TNODESAV records
   $ll = 0;
   foreach $oneline (@ksav_data) {
      $ll += 1;
      next if $ll < 5;
      chop $oneline;
#      my $plen = length($oneline);
#   print "Working on sav $ll $plen\n";
      $inode = substr($oneline,0,32);
      $inode =~ s/\s+$//;   #trim trailing whitespace
      $io4online = substr($oneline,33,1);

      # if offline with no product, ignore - maybe produce advisory later
      if ($io4online eq "N") {
         next if length($oneline) < 58;
      }
      $iproduct = substr($oneline,42,2);
      $iversion = substr($oneline,50,8);
      $iversion =~ s/\s+$//;   #trim trailing whitespace
      $nsx = $nsavex{$inode};
      if (!defined $nsx) {
         $nsavei++;
         $nsx = $nsavei;
         $nsave[$nsx] = $inode;
         $nsavex{$inode} = $nsx;
         $nsave_sysmsl[$nsx] = 0;
         $nsave_product[$nsx] = $iproduct;
         $nsave_version[$nsx] = $iversion;
         $nsave_ct[$nsx] = 0;
      }
      $nsave_ct[$nsx] += 1;
      if ($iproduct eq "EM") {
         $tx = $temsx{inode};
         if (!defined $tx) {
            $temsi += 1;
            $tx = $temsi;
            $tems[$tx] = $inode;
            $temsx{$inode} = $tx;
            $tems_hub[$tx] = 0;
            $tems_ct[$tx] = 0;
            $tems_version[$tx] = $iversion;
         }
      }
   }

   open(KLST, "<$opt_txt_tnodelst") || die("Could not open TNODELST $opt_txt_tnodelst\n");
   @klst_data = <KLST>;
   close(KLST);

   # Get data for all TNODELST type V records
   $ll = 0;
   foreach $oneline (@klst_data) {
      $ll += 1;
      next if $ll < 5;
      chop $oneline;
      $inodetype = substr($oneline,33,1);
      next if $inodetype ne "V";
      $inodelist = substr($oneline,42,32);
      $inodelist =~ s/\s+$//;   #trim trailing whitespace
      $inode = substr($oneline,0,32);
      $inode =~ s/\s+$//;   #trim trailing whitespace
      $vlx = $nlistvx{$inodelist};
      if (!defined $vlx) {
         $nlistvi++;
         $vlx = $nlistvi;
         $nlistv[$vlx] = $inodelist;
         $nlistvx{$inodelist} = $vlx;
         $nlistv_thrunode[$vlx] = $inode;
         $nlistv_tems[$vlx] = "";
         $nlistv_not[$vlx] = 0;
         $nlistv_ct[$vlx] = 0;
      }
      $nlistv_ct[$vlx] += 1;
      $tx = $temsx{$inode};      # is thrunode a TEMS?
      if (!defined $tx) {
         $snx = $snodex{$inode};
         if (!defined $snx) {
            $snodei += 1;
            $snx = $snodei;
            $snode[$snx] = $inode;
            $snodex{$inode} = $snx;
         }
      } else {
        $nlistv_tems[$vlx] = $tems[$tx];
      }
   }

   #Go back and fill in the nlistv_tems
   for ($i=0; $i<=$nlistvi; $i++) {
       next if $nlistv_tems[$i] ne "";
       my $subnode = $nlistv_thrunode[$i];
       $vlx = $nlistvx{$subnode};
       if (!defined $vlx) {
         $nlistv_not[$i] = 1;
       } else {
          $nlistv_tems[$i] = $nlistv_thrunode[$vlx];
       }
   }




   # Get data for all TNODELST type M records
   $ll = 0;
   foreach $oneline (@klst_data) {
      $ll += 1;
      next if $ll < 5;
#      chop $oneline;
      $inodetype = substr($oneline,33,1);
      $inodelist = substr($oneline,42,32);
      $inodelist =~ s/\s+$//;   #trim trailing whitespace
      $inode = substr($oneline,0,32);
      $inode =~ s/\s+$//;   #trim trailing whitespace
      if (($inodetype eq " ") and ($inodelist eq "*HUB")) {    # *HUB has blank NODETYPE. Set to M for this calculation
         $inodetype = "M";
         $tx = $temsx{$inode};
         $tems_hub[$tx] = 1;
         $hub_tems = $inode;
      }
      next if $inodetype ne "M";
      next if $inode eq "--EMPTYNODE--";
      $mkey = $inode . "|" . $inodelist;
      $mlx = $mlistx{$mkey};
      if (!defined $mlx) {
         $mlisti += 1;
         $mlx = $mlisti;
         $mlist[$mlx] = $mkey;
         $mlistx{$mkey} = $mlx;
         $mlist_ct[$mlx] = 0;
      }
      $mlist_ct[$mlx] += 1;

      $mlx = $nlistmx{$inode};
      if (!defined $mlx) {
         $nlistmi++;
         $mlx = $nlistmi;
         $nlistm[$mlx] = $inode;
         $nlistmx{$inode} = $mlx;
         $nlistm_miss[$mlx] = 0;
         $nlistm_nov[$mlx] = 0;
      }
      $nsx = $nsavex{$inode};
      if (defined $nsx) {
         $vlx = $nlistvx{$inode};
         if (defined $vlx) {
           my $lthrunode = $nlistv_thrunode[$vlx];
           $tx = $temsx{$lthrunode};
           if (defined $tx) {
              $nsave_sysmsl[$nsx] += 1 if substr($inodelist,0,1) eq "*";
           }
         } else {
           $nlistm_nov[$mlx] = 1 if $nsave_product[$nsx] ne "EM";
         }
      } else {
         $nlistm_miss[$mlx] = 1;
      }
   }
}
sub parse_lst {
  my ($lcount,$inline) = @_;            # count of desired chunks and the input line
  my @retlist = ();                     # an array of strings to return
  my $chunk;                            # One chunk
  my $oct = 0;                          # output chunk count
  my $rest;                             # the rest of the line to process
  $inline =~ /\]\s*(.*)/;               # skip by [NNN]  field
  $rest = $1;

  # until the last cycle, we select out a blank delimited word.
  # The last cycle we take the end of the line, minus the added blank
  while ($oct < $lcount) {
     $oct += 1;
     if ($oct < $lcount) {
        $rest =~ /\s*(\S+)\s*(.*)/;      # skip by count
        $chunk = $1;
        $rest = $2;
     } else {
        $chunk = $rest;
        chop $chunk;
     }
     push @retlist, $chunk;
  }
  return @retlist;
}

sub init_lst {
   my @klst_data;
   my $inode;
   my $inodelist;
   my $inodetype;

   my @ksav_data;
   my $iproduct;
   my $iversion;

   # Parsing the KfwSQLClient output has some challenges. For example
   #      [1]  OGRP_59B815CE8A3F4403  2010  Test Group 1
   # Using the blank delimiter is OK for columns that are never blank or have no embedded blanks.
   # In this case the GRPNAME column is "Test Group 1". To manage this the SQL is arranged so
   # that a column with embedded blanks always placed at the end. The one table TSITDESC which has
   # two such columns is retrieved with two separate SQLs.
   #
   # The one case where a column might be blank is the TNODESAV HOSTINFO column. In that case
   # a fixup is performed in case the third column [VERSION] is blank,
   #
   # There may be similar fixes in the future.


   open(KSAV, "< $opt_lst_tnodesav") || die("Could not open TNODESAV $opt_lst_tnodesav\n");
   @ksav_data = <KSAV>;
   close(KSAV);

   # Get data for all TNODESAV records
   $ll = 0;
   foreach $oneline (@ksav_data) {
      $ll += 1;
      next if $ll < 2;
      chop $oneline;
      ($inode,$iproduct,$iversion) = parse_lst(3,$oneline);
      $inode =~ s/\s+$//;   #trim trailing whitespace
      $iversion =~ s/\s+$//;   #trim trailing whitespace
      $iproduct =~ s/\s+$//;   #trim trailing whitespace
      $nsx = $nsavex{$inode};
      if (!defined $nsx) {
         $nsavei++;
         $nsx = $nsavei;
         $nsave[$nsx] = $inode;
         $nsavex{$inode} = $nsx;
         $nsave_sysmsl[$nsx] = 0;
         $nsave_product[$nsx] = $iproduct;
         $nsave_version[$nsx] = $iversion;
         $nsave_ct[$nsx] = 0;
      }
      $nsave_ct[$nsx] += 1;
      if ($iproduct eq "EM") {
         $tx = $temsx{inode};
         if (!defined $tx) {
            $temsi += 1;
            $tx = $temsi;
            $tems[$tx] = $inode;
            $temsx{$inode} = $tx;
            $tems_hub[$tx] = 0;
            $tems_ct[$tx] = 0;
            $tems_version[$tx] = $iversion;
         }
      }
   }

   open(KLST, "<$opt_lst_tnodelst") || die("Could not open TNODELST $opt_lst_tnodelst\n");
   @klst_data = <KLST>;
   close(KLST);

   # Get data for all TNODELST type V records
   $ll = 0;
   foreach $oneline (@klst_data) {
      $ll += 1;
      next if $ll < 2;
      chop $oneline;
      ($inode,$inodetype,$inodelist) = parse_lst(3,$oneline);
      next if $inodetype ne "V";
      $inodelist =~ s/\s+$//;   #trim trailing whitespace
      $inode =~ s/\s+$//;   #trim trailing whitespace
      $vlx = $nlistvx{$inodelist};
      if (!defined $vlx) {
         $nlistvi++;
         $vlx = $nlistvi;
         $nlistv[$vlx] = $inodelist;
         $nlistvx{$inodelist} = $vlx;
         $nlistv_thrunode[$vlx] = $inode;
         $nlistv_tems[$vlx] = "";
         $nlistv_not[$vlx] = 0;
         $nlistv_ct[$vlx] = 0;
      }
      $nlistv_ct[$vlx] += 1;
      $tx = $temsx{$inode};      # is thrunode a TEMS?
      if (!defined $tx) {
         $snx = $snodex{$inode};
         if (!defined $snx) {
            $snodei += 1;
            $snx = $snodei;
            $snode[$snx] = $inode;
            $snodex{$inode} = $snx;
         }
      } else {
        $nlistv_tems[$vlx] = $tems[$tx];
      }
   }

   #Go back and fill in the nlistv_tems
   for ($i=0; $i<=$nlistvi; $i++) {
       next if $nlistv_tems[$i] ne "";
       my $subnode = $nlistv_thrunode[$i];
       $vlx = $nlistvx{$subnode};
       if (!defined $vlx) {
         $nlistv_not[$i] = 1;
       } else {
          $nlistv_tems[$i] = $nlistv_thrunode[$vlx];
       }
   }

   # Get data for all TNODELST type M records
   $ll = 0;
   foreach $oneline (@klst_data) {
      $ll += 1;
      next if $ll < 2;
      chop $oneline;
      ($inode,$inodetype,$inodelist) = parse_lst(3,$oneline);
      $inodelist =~ s/\s+$//;   #trim trailing whitespace
      $inode =~ s/\s+$//;   #trim trailing whitespace
      if ($inodelist eq "") {    # *HUB has blank NODETYPE. Set to M for this calculation
         next if $inodetype ne "*HUB";
         $inodelist = $inodetype;
         $inodetype = "M";
         $tx = $temsx{$inode};
         $tems_hub[$tx] = 1;
         $hub_tems = $inode;
      }
      next if $inodetype ne "M";
      next if $inode eq "--EMPTYNODE--";
      $mkey = $inode . "|" . $inodelist;
      $mlx = $mlistx{$mkey};
      if (!defined $mlx) {
         $mlisti += 1;
         $mlx = $mlisti;
         $mlist[$mlx] = $mkey;
         $mlistx{$mkey} = $mlx;
         $mlist_ct[$mlx] = 0;
      }
      $mlist_ct[$mlx] += 1;

      $mlx = $nlistmx{$inode};
      if (!defined $mlx) {
         $nlistmi++;
         $mlx = $nlistmi;
         $nlistm[$mlx] = $inode;
         $nlistmx{$inode} = $mlx;
         $nlistm_miss[$mlx] = 0;
         $nlistm_nov[$mlx] = 0;
      }
      $nsx = $nsavex{$inode};
      if (defined $nsx) {
         $vlx = $nlistvx{$inode};
         if (defined $vlx) {
           my $lthrunode = $nlistv_thrunode[$vlx];
           $tx = $temsx{$lthrunode};
           if (defined $tx) {
              $nsave_sysmsl[$nsx] += 1 if substr($inodelist,0,1) eq "*";
           }
         } else {
           $nlistm_nov[$mlx] = 1 if $nsave_product[$nsx] ne "EM";
         }
      } else {
         $nlistm_miss[$mlx] = 1;
      }
   }
}


# Get options from command line - first priority
sub init {
   my $myargs_remain;
   my @myargs_remain_array;
   use Getopt::Long qw(GetOptionsFromString);
   $myargs = shift;
   ($rc,$myargs_remain) = GetOptionsFromString($myargs,
              'log=s' => \ $opt_log,                  # log file
              'ini=s' => \ $opt_ini,                  # control file
              'debuglevel=i' => \ $opt_debuglevel,    # log file contents control
              'debug' => \ $opt_debug,                # log file contents control
              'h' => \ $opt_h,                        # help
              'v' => \  $opt_v,                       # verbose - print immediately as well as log
              'workdir=s' => \ $opt_workdir,          # Work directories
              'nohdr' => \ $opt_nohdr,                # Skip header for regression test
              'txt' => \ $opt_txt,                    # txt input
              'lst' => \ $opt_lst                     # lst input
             );
   # if other things found on the command line - complain and quit
   @myargs_remain_array = @$myargs_remain;
   if ($#myargs_remain_array != -1) {
      foreach (@myargs_remain_array) {
        print STDERR "SITAUDIT001E Unrecognized command line option - $_\n";
      }
      print STDERR "SITAUDIT001E exiting after command line errors\n";
      exit 1;
   }

   # Following are command line only defaults. All others can be set from the ini file

   if (!defined $opt_ini) {$opt_ini = "sitaudit.ini";}         # default control file if not specified
   if ($opt_h) {&GiveHelp;}  # GiveHelp and exit program
   if (!defined $opt_debuglevel) {$opt_debuglevel=90;}         # debug logging level - low number means fewer messages
   if (!defined $opt_debug) {$opt_debug=0;}                    # debug - turn on rare error cases

   # ini control file must be present

   if (-e $opt_ini) {                                      # make sure ini file is present

      open( FILE, "< $opt_ini" ) or die "Cannot open ini file $opt_ini : $!";
      my @ips = <FILE>;
      close FILE;

      # typical ini file scraping. Could be improved by validating parameters

      my $l = 0;
      foreach my $oneline (@ips)
      {
         $l++;
         chomp($oneline);
         next if (substr($oneline,0,1) eq "#");  # skip comment line
         @words = split(" ",$oneline);
         next if $#words == -1;                  # skip blank line
          if ($#words == 0) {                         # single word parameters
            if ($words[0] eq "verbose") {$opt_v = 1;}
            else {
               print STDERR "SITAUDIT003E Control without needed parameters $words[0] - $opt_ini [$l]\n";
               $run_status++;
            }
            next;
         }

         if ($#words == 1) {
            # two word controls - option and value
            if ($words[0] eq "log") {$opt_log = $words[1];}
            elsif ($words[0] eq "log") {$opt_log = $words[1];}
            elsif ($words[0] eq "workdir") {$opt_workdir = $words[1];}
            else {
               print STDERR "SITAUDIT005E ini file $l - unknown control oneline\n"; # kill process after current phase
               $run_status++;
            }
            next;
         }
         print STDERR "SITAUDIT005E ini file $l - unknown control $oneline\n"; # kill process after current phase
         $run_status++;
      }
   }

   # defaults for options not set otherwise

   if (!defined $opt_log) {$opt_log = "sitaudit.log";}           # default log file if not specified
   if (!defined $opt_h) {$opt_h=0;}                            # help flag
   if (!defined $opt_v) {$opt_v=0;}                            # verbose flag
   if (!defined $opt_dpr) {$opt_dpr=0;}                        # data dump flag
   if (!defined $opt_workdir) {$opt_workdir="";}               # default work directory is current directory
   if (!defined $opt_txt) {$opt_txt = 0;}                      # default no txt input
   if (!defined $opt_lst) {$opt_lst = 0;}                      # default no lst input
   $opt_workdir =~ s/\\/\//g;                                 # convert to standard perl forward slashes
   if ($opt_workdir ne "") {
      $opt_workdir .= "\/" if substr($opt_workdir,-1,1) ne "\/";
   }
   if (defined $opt_txt) {
      $opt_txt_tnodelst = $opt_workdir . "QA1CNODL.DB.TXT";
      $opt_txt_tnodesav =  $opt_workdir . "QA1DNSAV.DB.TXT";
   }
   if (defined $opt_lst) {
      $opt_lst_tnodesav  =  $opt_workdir . "QA1DNSAV.DB.LST";
      $opt_lst_tnodelst  =  $opt_workdir . "QA1CNODL.DB.LST";
   }


   if ($opt_dpr == 1) {
#     my $module = "Data::Dumper";
#     eval {load $module};
#     if ($@) {
#        print STDERR "Cannot load Data::Dumper - ignoring -dpr option\n";
#        $opt_dpr = 0;
#     }
      $opt_dpr = 0;
   }

   # if credential as passed in via standard input, then that takes precendence.

   # complain about options which must be present
   if (($opt_txt + $opt_lst) != 1) {
      print STDERR "SITINFO006E exactly one of txt/lst must be present\n";
      $run_status++;
   }

   # if any errors, then dump log and exit
   # this way we can show multiple errors at startup
   if ($run_status) { exit 1;}

}



#------------------------------------------------------------------------------
sub GiveHelp
{
  $0 =~ s|(.*)/([^/]*)|$2|;
  print <<"EndOFHelp";

  $0 v$gVersion

  This script surveys an ITM environment looking for possibly unhealthy agents
  which are online not responsive.

  Default values:
    log           : sitaudit.log
    ini           : sitaudit.ini
    debuglevel    : 90 [considerable number of messages]
    debug         : 0  when 1 some breakpoints are enabled]
    h             : 0  display help information
    v             : 0  display log messages on console
    vt            : 0  record http traffic on traffic.txt file
    dpr           : 0  dump data structure if Dump::Data installed

  Example invovation
    $0  -ini <control file> -pc ux

  Note: $0 uses an initialization file [default sitaudit.ini] for many controls.

EndOFHelp
exit;
}


#------------------------------------------------------------------------------
# capture log record
sub logit
{
   my $level = shift;
   if ($level <= $opt_debuglevel) {
      my $iline = shift;
      my $itime = gettime();
      chop($itime);
      my $oline = $itime . " " . $level . " " . $iline;
      if ($opt_debuglevel >= 100) {
         my $ofile = (caller(0))[1];
         my $olino = (caller(0))[2];
         if (defined $ofile) {
            $oline = $ofile . ":" . $olino . " " . $oline;
         }
      }
      print FH "$oline\n";
      print "$oline\n" if $opt_v == 1;
   }
}

#------------------------------------------------------------------------------
# capture agent log record
#------------------------------------------------------------------------------
# capture agent error record

# write output log
sub datadumperlog
{
   require Data::Dumper;
   my $dd_msg = shift;
   my $dd_var = shift;
   print FH "$dd_msg\n";
   no strict;
   print FH Data::Dumper->Dumper($dd_var);
}

# return timestamp
sub gettime
{
   my $sec;
   my $min;
   my $hour;
   my $mday;
   my $mon;
   my $year;
   my $wday;
   my $yday;
   my $isdst;
   ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
   return sprintf "%4d-%02d-%02d %02d:%02d:%02d\n",$year+1900,$mon+1,$mday,$hour,$min,$sec;
}

# get current time in ITM standard timestamp form
# History log

# 0.60000  : New script based somewhat on ITM Situation Audit 1.14000
