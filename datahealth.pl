#!/usr/local/bin/perl -w
#------------------------------------------------------------------------------
# Licensed Materials - Property of IBM (C) Copyright IBM Corp. 2010, 2010
# All Rights Reserved US Government Users Restricted Rights - Use, duplication
# or disclosure restricted by GSA ADP Schedule Contract with IBM Corp
#------------------------------------------------------------------------------

#  perl datahealth.pl
#
#  Identify cases where TEMS database is inconsistent
#   Version 0.70000 checks TNODESAV and TNODELST
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

my $gVersion = "0.72000";
my $gWin = (-e "C://") ? 1 : 0;    # 1=Windows, 0=Linux/Unix

use Data::Dumper;               # debug only

# a collection of variables which are used throughout the program.
# defined globally

my $args_start = join(" ",@ARGV);      # capture arguments for later processing
my $run_status = 0;                    # A count of pending runtime errors - used to allow multiple error detection before stopping process

# some common variables

my $rc;                                  # command return code
my @words = ();
my $rt;
my $ll;
my $pcount;
my $oneline;
my $sx;
my $i;

# forward declarations of subroutines

sub init;                                # read command line and ini file
sub logit;                               # queue one record to survey log
sub datadumperlog;                       # dump a variable using Dump::Data if installed
sub gettime;                             # get time
sub init_txt;                            # input from txt files
sub init_lst;                            # input from lst files
sub parse_lst;                           # parse the KfwSQLClient output
sub new_tnodesav;                        # process the TNODESAV columns
sub new_tnodelstv;                       # process the TNODELST NODETYPE=V records
sub fill_tnodelstv;                      # reprocess new TNODELST NODETYPE=V data

my $sitdata_start_time = gettime();     # formated current time for report

# TNODELST type V record data           Alive records - list thrunode most importantly
my $vlx;                                # Access index
my $nlistvi = -1;                       # count of type V records
my @nlistv = ();                        # node name
my %nlistvx = ();                       # hash from name to index
my @nlistv_thrunode = ();               # agent thrunode
my @nlistv_tems = ();                   # TEMS if thrunode is agent
my @nlistv_ct = ();                     # count of agents

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
my @nsave_o4online = ();

# TNODESAV HOSTADDR duplications
my $hsx;
my $hsavei = -1;
my @hsave = ();
my %hsavex = ();
my @hsave_sav = ();
my @hsave_ndx = ();
my @hsave_ct = ();
my @hsave_thrundx = ();

my $tx;                                  # TEMS information
my $temsi = -1;                          # count of TEMS
my @tems = ();                           # Array of TEMS names
my %temsx = ();                          # Hash to TEMS index
my @tems_hub = ();                       # When 1, is the hub TEMS
my @tems_ct = ();                        # Count of managed systems
my @tems_version = ();                   # TEMS version number
my $hub_tems = "";                       # hub TEMS nodeid
my $hub_tems_no_tnodesav = 0;            # hub TEMS nodeid missingfrom TNODESAV
my $hub_tems_ct = 0;                     # total agents managed by a hub TEMS

my $mx;                                  # index
my $magenti = -1;                        # count of managing agents
my @magent = ();                         # name of managing agent
my %magentx = ();                        # hash from managing agent name to index
my @magent_subct = ();                   # count of subnode agents
my @magent_sublen = ();                  # length of subnode agent list
my @magent_tems_version = ();            # version of managing agent TEMS

my $snx;


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
my $opt_vt;                     # verbose traffic flag
my $opt_dpr;                    # dump data structure flag
my $opt_o;                      # output file
my $opt_workpath;               # Directory to store output files
my $opt_nohdr = 0;              # skip header to make regression testing easier
my $opt_subpc_warn;;             # advise when subnode length > 90 of limit on pre ITM 623 FP2

# do basic initialization from parameters, ini file and standard input

$rc = init($args_start);

$opt_log = $opt_workpath . $opt_log;
open FH, ">>$opt_log" or die "can't open $opt_log: $!";

logit(0,"SITAUDIT000I - ITM_Situation_Audit $gVersion $args_start");

# process three different sources of situation data

if ($opt_txt == 1) {                    # text files
   $rc = init_txt();
} elsif ($opt_lst == 1) {               # KfwSQLClient LST files
   $rc = init_lst();
}


open OH, ">$opt_o" or die "can't open $opt_o: $!";


my $advi = -1;
my @advonline = ();
my @advsit = ();
my @advimpact = ();
my @advcode = ();
my %advx = ();
my $hubi;


if ($hub_tems_no_tnodesav == 1) {
   $advi++;$advonline[$advi] = "HUB TEMS $hub_tems is present in TNODELST but missing from TNODESAV";
   $advcode[$advi] = "DATAHEALTH1011E";
   $advimpact[$advi] = 105;
   $advsit[$advi] = $hub_tems;
}

if ($nlistvi == -1) {
   $advi++;$advonline[$advi] = "No TNODELIST NODETYPE=V records";
   $advcode[$advi] = "DATAHEALTH1012E";
   $advimpact[$advi] = 105;
   $advsit[$advi] = $hub_tems;
   $hub_tems_no_tnodesav = 1;
}

# following produces a report of how many agents connect to a TEMS.

if ($hub_tems_no_tnodesav == 0) {
   $hubi = $temsx{$hub_tems};

   for ($i=0; $i<=$nlistvi; $i++) {
      my $node1 = $nlistv[$i];
      next if $nlistv_tems[$i] eq "";
      my $tems1 = $nlistv_tems[$i];
      my $tx = $temsx{$tems1};
      next if !defined $tx;
      $hub_tems_ct += 1;
      $tems_ct[$tx] += 1;
   }
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
   my $node1 = $nsave[$i];
   next if $nsave_product[$i] eq "EM";
   $nsx = $nlistvx{$node1};
   if (defined $nsx) {
      my $subn = 0;
      my $thru1 = $nlistv_thrunode[$nsx];
      if ($thru1 eq "") {
        $subn = 1;
      } else {
        my $tx = $temsx{$thru1};
        $subn = 1 if !defined $tx;
      }
      if ($subn == 0) {
         next if length($node1) < 32;
         $advi++;$advonline[$advi] = "Node Name at 32 characters and might be truncated";
         $advcode[$advi] = "DATAHEALTH1013W";
         $advimpact[$advi] = 20;
         $advsit[$advi] = $node1;
      } else {
         next if length($node1) < 31;
         $advi++;$advonline[$advi] = "Subnode Name at 31/32 characters and might be truncated";
         $advcode[$advi] = "DATAHEALTH1014W";
         $advimpact[$advi] = 20;
         $advsit[$advi] = $node1;
      }
   }
}

for ($i=0; $i<=$magenti;$i++) {
   my $onemagent = $magent[$i];
   next if $magent_tems_version[$i] ge "06.23.02";
   if ($magent_sublen[$i]*100 > $opt_subpc_warn*32768){
      $advi++;$advonline[$advi] = "Managing agent subnodelist is $magent_sublen[$i],  more then $opt_subpc_warn% of 32768 bytes";
      $advcode[$advi] = "DATAHEALTH1015W";
      $advimpact[$advi] = 80;
      $advsit[$advi] = $onemagent;
   }
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
   $advimpact[$advi] = 105;
   $advsit[$advi] = $nsave[$i];
}

for ($i=0;$i<=$hsavei;$i++) {
   next if $hsave_ct[$i] == 1;
   next if !defined $hsave[$i];
   my $pi;
   my @hagents = split(" ",$hsave_ndx[$i]);
   my $pagents = "";
   my @tagents = split(" ",$hsave_thrundx[$i]);
   for (my $j=0;$j<=$#hagents;$j++) {
      $pi = $hagents[$j];
      my $oneagent = $nsave[$pi];
      my $onethru = $tagents[$j];
      my $nx = $nsavex{$oneagent};
      if (defined $nx) {
         $pagents .= $nsave[$pi]. "[$onethru][Y] " if $nsave_o4online[$nx] eq "Y";
      } else {
         $pagents .= $nsave[$pi]. "[][Y] " if $nsave_o4online[$nx] eq "Y";
      }
   }
   next if $pagents eq "";
   $advi++;$advonline[$advi] = "TNODESAV duplicate hostaddr in [$pagents]";
   $advcode[$advi] = "DATAHEALTH1010W";
   $advimpact[$advi] = 10;
   $advsit[$advi] = $hsave[$i];
}

for ($i=0;$i<=$nlistvi;$i++) {
   next if $nlistv_ct[$i] == 1;
   $advi++;$advonline[$advi] = "TNODELST Type V duplicate nodes";
   $advcode[$advi] = "DATAHEALTH1008E";
   $advimpact[$advi] = 105;
   $advsit[$advi] = $nlistv[$i];
}

for ($i=0;$i<=$mlisti;$i++) {
   next if $mlist_ct[$i] == 1;
   $advi++;$advonline[$advi] = "TNODELST Type M duplicate NODE/NODELIST";
   $advcode[$advi] = "DATAHEALTH1009E";
   $advimpact[$advi] = 105;
   $advsit[$advi] = $mlist[$i];
}

if ($opt_nohdr == 0) {
   print OH "ITM Database Health Report $gVersion\n";
   print OH "\n";
}

   my $remote_limit = 1500;
if ($hub_tems_no_tnodesav == 0) {
   my $hub_limit = 10000;
   $hub_limit = 20000 if substr($tems_ct[$hubi],0,5) gt "06.23";

   if ($hub_tems_ct > $hub_limit){
      $advi++;$advonline[$advi] = "Hub TEMS has $hub_tems_ct managed systems which exceeds limits $hub_limit";
      $advcode[$advi] = "DATAHEALTH1005W";
      $advimpact[$advi] = 75;
      $advsit[$advi] = $hub_tems;
   }


   print OH "Hub,$hub_tems,$hub_tems_ct\n";
   for (my $i=0;$i<=$temsi;$i++) {
      next if $i == $hubi;
      if ($tems_ct[$i] > $remote_limit){
         $advi++;$advonline[$advi] = "TEMS has $tems_ct[$i] managed systems which exceeds limits $remote_limit";
         $advcode[$advi] = "DATAHEALTH1006W";
         $advimpact[$advi] = 75;
         $advsit[$advi] = $tems[$i];
      }
      print OH "Remote,$tems[$i],$tems_ct[$i]\n";
   }
print OH "\n";
}

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

   }
}
my $exit_code = ($advi != -1);
exit $exit_code;

# Record data from the TNODESAV table. This is the disk version of [most of] the INODESTS or node status table.
# capture node name, product, version, online status

sub new_tnodesav {
   my ($inode,$iproduct,$iversion,$io4online,$ihostaddr) = @_;
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
      $nsave_o4online[$nsx] = $io4online;
   }
   # count number of nodes. If more then one there is a primary key duplication error
   $nsave_ct[$nsx] += 1;
   # track the TEMS and the version
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
   # track individual HOSTADDR
   # duplicates often reflect minor issues
   if (defined $ihostaddr) {
      if ($ihostaddr ne "") {
         $hsx = $hsavex{$ihostaddr};
         if (!defined $hsx) {
            $hsavei++;
            $hsx = $hsavei;
            $hsave[$hsx] = $ihostaddr;
            $hsavex{$ihostaddr} = $hsx;
            $hsave_ndx[$hsx] = "";
            $hsave_ct[$hsx] = 0;
            $hsave_thrundx[$hsx] = "";
         }

         # record the node indexes of each duplicate
         $hsave_ndx[$hsx] .= $nsx . " ";
         $hsave_ct[$hsx] += 1;
      }
   }
}

# Record data from the TNODELST NODETYPE=V table. This is the ALIVE data which captures the thrunode

sub new_tnodelstv {
   my ($inodetype,$inodelist,$inode) = @_;
   # The $inodelist is the managed system name. Record that data
   $vlx = $nlistvx{$inodelist};
   if (!defined $vlx) {
      $nlistvi++;
      $vlx = $nlistvi;
      $nlistv[$vlx] = $inodelist;
      $nlistvx{$inodelist} = $vlx;
      $nlistv_thrunode[$vlx] = $inode;
      $nlistv_tems[$vlx] = "";
      $nlistv_ct[$vlx] = 0;
   }

   # The $inode is the thrunode, capture that data.
   $nlistv_ct[$vlx] += 1;
   $tx = $temsx{$inode};      # is thrunode a TEMS?
   # keep track of managing agent - which have subnodes
   # before ITM 623 FP2 this was limited in size and needs an advisory
   if (!defined $tx) {        # if not it is a managing agent
      $mx = $magentx{$inode};
      if (!defined $mx) {
         $magenti += 1;
         $mx = $magenti;
         $magent[$mx] = $inode;
         $magentx{$inode} = $mx;
         $magent_subct[$mx] = 0;
         $magent_sublen[$mx] = 0;
         $magent_tems_version[$mx] = "";
      }
      $magent_subct[$mx] += 1;
      # the actual limit is the names in a list with single blank delimiter
      # If the exceeds 32767 bytes, a TEMS crash or other malfunction can happen.
      $magent_sublen[$mx] += length($inodelist) + 1;
   } else {
     # if directly connected to a TEMS, record the TEMS
     $nlistv_tems[$vlx] = $tems[$tx];
   }
}

# After the TNODELST NODETYPE=V data is captured, correlate data

sub fill_tnodelstv {
   #Go back and fill in the nlistv_tems
   # If the node is a managing agent, determine what the TEMS it reports to
   for ($i=0; $i<=$nlistvi; $i++) {
       next if $nlistv_tems[$i] ne "";
       my $subnode = $nlistv_thrunode[$i];
       $vlx = $nlistvx{$subnode};
       if (defined $vlx) {
          $nlistv_tems[$i] = $nlistv_thrunode[$vlx];
       }
   }

   #Go back and fill in the $magent_tems_version
   #if the agent reports to a managing agent, count the instances and also
   #record the TEMS version the managing agent connects to.
   for ($i=0; $i<=$nlistvi; $i++) {
       my $node1 = $nlistv[$i];
       $mx = $magentx{$node1};
       next if !defined $mx;
       my $mnode = $magent[$mx];
       $vlx = $nlistvx{$mnode};
       next if !defined $vlx;
       my $mthrunode = $nlistv_thrunode[$vlx];
       $tx = $temsx{$mthrunode};
       next if !defined $tx;
       $magent_tems_version[$mx] = $tems_version[$tx];
   }


   #Go back and fill in the $hsave_thrundx
   for ($i=0; $i<=$hsavei; $i++) {
      my $pi;
      next if $hsave_ndx[$i] eq "";
      my @hagents = split(" ",$hsave_ndx[$i]);
      my $pthrundx = "";
      for (my $j=0;$j<=$#hagents;$j++) {
         $pi = $hagents[$j];
         my $oneagent = $nsave[$pi];
         my $vx = $nlistvx{$oneagent};
         if (!defined $vx) {
            $pthrundx .= ". ";
            next;
         }
         my $onethru = $nlistv_thrunode[$vx];
         $tx = $temsx{$onethru};
         if (!defined $tx) {
            $pthrundx .= ". ";
            next;
         }
         if ($nlistv_thrunode[$vx] ne "") {
            $pthrundx .= $nlistv_thrunode[$vx] . " ";
         } else {
            $pthrundx .= ". ";
         }
      }
      $hsave_thrundx[$i] = $pthrundx;
   }
   for ($i=0; $i<=$nlistvi; $i++) {
       my $node1 = $nlistv[$i];
       $mx = $magentx{$node1};
       next if !defined $mx;
       my $mnode = $magent[$mx];
       $vlx = $nlistvx{$mnode};
       next if !defined $vlx;
       my $mthrunode = $nlistv_thrunode[$vlx];
       $tx = $temsx{$mthrunode};
       next if !defined $tx;
       $magent_tems_version[$mx] = $tems_version[$tx];
   }
}


# Record data from the TNODELST NODETYPE=M table. This is the MSL

sub new_tnodelstm {
my ($inodetype,$inodelist,$inode) = @_;
   return if $inode eq "--EMPTYNODE--";         # ignore empty tables
   # primary key is node and nodelist. Track and count duplicates for the severe index error
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

   # record the agent oriented data. During processing we will record data about
   # various missing cases.
   $mlx = $nlistmx{$inode};
   if (!defined $mlx) {
      $nlistmi++;
      $mlx = $nlistmi;
      $nlistm[$mlx] = $inode;
      $nlistmx{$inode} = $mlx;
      $nlistm_miss[$mlx] = 0;
      $nlistm_nov[$mlx] = 0;
   }

   # record data about missing system generated MSLs
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
   my $ihostaddr;

   open(KSAV, "< $opt_txt_tnodesav") || die("Could not open TNODESAV $opt_txt_tnodesav\n");
   @ksav_data = <KSAV>;
   close(KSAV);

   # Get data for all TNODESAV records
   $ll = 0;
   foreach $oneline (@ksav_data) {
      $ll += 1;
      next if $ll < 5;
      chop $oneline;
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
      $ihostaddr = "";
      if (length($oneline) > 59) {
         $ihostaddr = substr($oneline,59);
         $ihostaddr =~ s/\s+$//;   #trim trailing whitespace
      }
      new_tnodesav($inode,$iproduct,$iversion,$io4online,$ihostaddr);
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
      new_tnodelstv($inodetype,$inodelist,$inode);
   }
   fill_tnodelstv();


   # Get data for all TNODELST type M records
   $ll = 0;
   foreach $oneline (@klst_data) {
      $ll += 1;
      next if $ll < 5;
      $inodetype = substr($oneline,33,1);
      $inodelist = substr($oneline,42,32);
      $inodelist =~ s/\s+$//;   #trim trailing whitespace
      $inode = substr($oneline,0,32);
      $inode =~ s/\s+$//;   #trim trailing whitespace
      if (($inodetype eq " ") and ($inodelist eq "*HUB")) {    # *HUB has blank NODETYPE. Set to M for this calculation
         $inodetype = "M";
         $tx = $temsx{$inode};
         if (defined $tx) {
            $tems_hub[$tx] = 1;
            $hub_tems = $inode;
         } else {
            $hub_tems_no_tnodesav = 1;
            $hub_tems = $inode;
         }
      }
      next if $inodetype ne "M";
      new_tnodelstm($inodetype,$inodelist,$inode);
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
   my $ihostaddr;
   my $io4online;

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
      $ihostaddr = "";
      $io4online = "Y";
      new_tnodesav($inode,$iproduct,$iversion,$io4online,$ihostaddr);
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
      new_tnodelstv($inodetype,$inodelist,$inode);
   }
   fill_tnodelstv();

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
      new_tnodelstm($inodetype,$inodelist,$inode);
   }
}


# Get options from command line - first priority
sub init {
   while (@ARGV) {
      if ($ARGV[0] eq "-log") {
         shift(@ARGV);
         $opt_log = shift(@ARGV);
         die "option -log with no following log specification\n" if !defined $opt_log;
      } elsif ( $ARGV[0] eq "-ini") {
         shift(@ARGV);
         $opt_ini = shift(@ARGV);
         die "option -ini with no following ini specification\n" if !defined $opt_ini;
      } elsif ( $ARGV[0] eq "-debuglevel") {
         shift(@ARGV);
         $opt_debuglevel = shift(@ARGV);
         die "option -debuglevel with no following debuglevel specification\n" if !defined $opt_debuglevel;
      } elsif ( $ARGV[0] eq "-debug") {
         shift(@ARGV);
         $opt_debug = 1;
      } elsif ( $ARGV[0] eq "-h") {
         shift(@ARGV);
         $opt_h = 1;
      } elsif ( $ARGV[0] eq "-o") {
         shift(@ARGV);
         $opt_o = shift(@ARGV);
         die "option -o with no following output file specification\n" if !defined $opt_o;
      } elsif ( $ARGV[0] eq "-workpath") {
         shift(@ARGV);
         $opt_workpath = shift(@ARGV);
         die "option -workpath with no following debuglevel specification\n" if !defined $opt_workpath;
      } elsif ( $ARGV[0] eq "-nohdr") {
         shift(@ARGV);
         $opt_nohdr = 1;
      } elsif ( $ARGV[0] eq "-txt") {
         shift(@ARGV);
         $opt_txt = 1;
      } elsif ( $ARGV[0] eq "-lst") {
         shift(@ARGV);
         $opt_lst = 1;
      } elsif ( $ARGV[0] eq "-subpc") {
         shift(@ARGV);
         $opt_subpc_warn = shift(@ARGV);
         die "option -subpc with no following per cent specification\n" if !defined $opt_subpc_warn;
      } else {
         print STDERR "SITAUDIT001E Unrecognized command line option - $ARGV[0]\n";
         exit 1;
      }
   }

   # Following are command line only defaults. All others can be set from the ini file

   if (!defined $opt_ini) {$opt_ini = "sitaudit.ini";}         # default control file if not specified
   if ($opt_h) {&GiveHelp;}  # GiveHelp and exit program
   if (!defined $opt_debuglevel) {$opt_debuglevel=90;}         # debug logging level - low number means fewer messages
   if (!defined $opt_debug) {$opt_debug=0;}                    # debug - turn on rare error cases
   if (defined $opt_txt) {
      $opt_txt_tnodelst = "QA1CNODL.DB.TXT";
      $opt_txt_tnodesav = "QA1DNSAV.DB.TXT";
   }
   if (defined $opt_lst) {
      $opt_lst_tnodesav  = "QA1DNSAV.DB.LST";
      $opt_lst_tnodelst  = "QA1CNODL.DB.LST";
   }

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
            elsif ($words[0] eq "traffic") {$opt_vt = 1;}
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
            elsif ($words[0] eq "o") {$opt_o = $words[1];}
            elsif ($words[0] eq "workpath") {$opt_workpath = $words[1];}
            elsif ($words[0] eq "subpc") {$opt_subpc_warn = $words[1];}
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

   if (!defined $opt_log) {$opt_log = "datahealth.log";}       # default log file if not specified
   if (!defined $opt_h) {$opt_h=0;}                            # help flag
   if (!defined $opt_v) {$opt_v=0;}                            # verbose flag
   if (!defined $opt_vt) {$opt_vt=0;}                          # verbose traffic default off
   if (!defined $opt_dpr) {$opt_dpr=0;}                        # data dump flag
   if (!defined $opt_o) {$opt_o="datahealth.csv";}               # default output file
   if (!defined $opt_workpath) {$opt_workpath="";}             # default is current directory
   if (!defined $opt_txt) {$opt_txt = 0;}                      # default no txt input
   if (!defined $opt_lst) {$opt_lst = 0;}                      # default no lst input
   if (!defined $opt_subpc_warn) {$opt_subpc_warn=90;}                   # default warn on 90% of maximum subnode list

   $opt_workpath =~ s/\\/\//g;                                 # convert to standard perl forward slashes
   if ($opt_workpath ne "") {
      $opt_workpath .= "\/" if substr($opt_workpath,length($opt_workpath)-1,1) ne "\/";
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
    user          : <none>
    passwd        : <none>
    debuglevel    : 90 [considerable number of messages]
    debug         : 0  when 1 some breakpoints are enabled]
    h             : 0  display help information
    v             : 0  display log messages on console
    vt            : 0  record http traffic on traffic.txt file
    dpr           : 0  dump data structure if Dump::Data installed
    std           : 0  get user/password from stardard input

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

# 0.60000  : New script based on ITM Situation Audit 1.14000
# 0.70000  : Advisory when duplicatee HOSTADDR columns
# 0.71000  : Adapt to regression test process
#          : low impact advisory on long node names
# 0.72000  : count size of subnode list and advise if TEMS < "06.23.02" and near 32K
