#!/usr/local/bin/perl -w
#------------------------------------------------------------------------------
# Licensed Materials - Property of IBM (C) Copyright IBM Corp. 2010, 2010
# All Rights Reserved US Government Users Restricted Rights - Use, duplication
# or disclosure restricted by GSA ADP Schedule Contract with IBM Corp
#------------------------------------------------------------------------------

#  perl datahealth.pl
#
#  Identify cases where TEMS database is inconsistent
#   Version 0.88000 checks TNODESAV, TNODELST, TSITDESC, TNAME, TOBJACCL
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
#

#use warnings::unused; # debug used to check for unused variables
use strict;
use warnings;

# See short history at end of module

my $gVersion = "0.92000";
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
sub new_tobjaccl;                        # process the TOBJACCL records
sub fill_tnodelstv;                      # reprocess new TNODELST NODETYPE=V data

my $sitdata_start_time = gettime();     # formated current time for report


my %miss = ();                          # collection of missing cases

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

my $nlx;
my $nlisti = -1;
my @nlist = ();
my %nlistx = ();


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
my @nsave_temaver = ();

# TNODESAV HOSTADDR duplications
my $hsx;
my $hsavei = -1;
my @hsave = ();
my %hsavex = ();
my @hsave_sav = ();
my @hsave_ndx = ();
my @hsave_ct = ();
my @hsave_thrundx = ();

# TOBJACCL data
my %tobjaccl = ();
my $obji = -1;
my @obj = ();
my %objx = ();
my @obj_objclass = ();
my @obj_objname = ();
my @obj_nodel = ();
my @obj_ct = ();


my $tx;                                  # TEMS information
my $temsi = -1;                          # count of TEMS
my @tems = ();                           # Array of TEMS names
my %temsx = ();                          # Hash to TEMS index
my @tems_hub = ();                       # When 1, is the hub TEMS
my @tems_ct = ();                        # Count of managed systems
my @tems_ctnok = ();                     # Count of managed systems excluding OK at FTO hub TEMS
my @tems_version = ();                   # TEMS version number
my @tems_thrunode = ();                  # TEMS THRUNODE, when NODE=THRUNODE that is a hub TEMS
my @tems_affinities = ();                # TEMS AFFINITIES
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

my $advi = -1;
my @advonline = ();
my @advsit = ();
my @advimpact = ();
my @advcode = ();
my %advx = ();
my $hubi;
my $max_impact = 0;
my $isFTO = 0;

my $test_node;
my $invalid_node;

my $key;
my $vtx;                                 # index
my $vti = -1;                            # count of node types affecting virtual hub table
my @vtnode = ();                         # virtual hub table agent type
my %vtnodex = ();                        # virtual hub table agent index
my @vtnode_rate = ();                    # how many minutes apart
my @vtnode_tab = ();                     # number of virtual hub tables updates found in *SYN autostart mode
my @vtnode_ct = ();                      # count of virtual table hub agents
my @vtnode_hr = ();                      # virtual hub table updates per hour
my $vtnode_tot_ct = 0;                   # total count of virtual table hub agents
my $vtnode_tot_hr = 0;                   # total virtual hub table updates per hour
my $vtnodes = "";                        # list of node types affecting virtual hub table updates

# initialize above table
$vti = 0;$key="UX";$vtnode[$vti]=$key;$vtnodex{$key}=$vti;$vtnode_rate[$vti]=3;$vtnode_tab[$vti]=0;$vtnode_ct[$vti]=0;$vtnode_hr[$vti]=0;
$vti = 1;$key="OQ";$vtnode[$vti]=$key;$vtnodex{$key}=$vti;$vtnode_rate[$vti]=2;$vtnode_tab[$vti]=0;$vtnode_ct[$vti]=0;$vtnode_hr[$vti]=0;
$vti = 2;$key="OR";$vtnode[$vti]=$key;$vtnodex{$key}=$vti;$vtnode_rate[$vti]=2;$vtnode_tab[$vti]=0;$vtnode_ct[$vti]=0;$vtnode_hr[$vti]=0;
$vti = 3;$key="OY";$vtnode[$vti]=$key;$vtnodex{$key}=$vti;$vtnode_rate[$vti]=2;$vtnode_tab[$vti]=0;$vtnode_ct[$vti]=0;$vtnode_hr[$vti]=0;
$vti = 4;$key="Q5";$vtnode[$vti]=$key;$vtnodex{$key}=$vti;$vtnode_rate[$vti]=1;$vtnode_tab[$vti]=0;$vtnode_ct[$vti]=0;$vtnode_hr[$vti]=0;
$vti = 5;$key="HV";$vtnode[$vti]=$key;$vtnodex{$key}=$vti;$vtnode_rate[$vti]=2;$vtnode_tab[$vti]=0;$vtnode_ct[$vti]=0;$vtnode_hr[$vti]=0;

my %hSP2OS = (
   UADVISOR_OMUNX_SP2OS => 'UX',
   UADVISOR_KOQ_VKOQDBMIR => 'OQ',
   UADVISOR_KOQ_VKOQLSDBD => 'OQ',
   UADVISOR_KOQ_VKOQSRVR => 'OQ',
   UADVISOR_KOQ_VKOQSRVRE => 'OQ',
   UADVISOR_KOR_VKORSRVRE => 'OR',
   UADVISOR_KOR_VKORSTATE => 'OR',
   UADVISOR_KOY_VKOYSRVR => 'OY',
   UADVISOR_KOY_VKOYSRVRE => 'OY',
   UADVISOR_KQ5_VKQ5CLUSUM => 'Q5',
   UADVISOR_KHV_VKHVHYPERV => 'HV',
);

my $snx;

my %hnodelist = (
   KKT3S => '*EM_SERVER_DB',                                     # T3
   KKYJW => '*CAM_J2EE_WLS_SERVER',                              # YJ
   KWMI => '*IBM_RemoteWinOS_WMI',                               # R2
   KR2 => '*IBM_RemoteWinOS',                                    # R2
   KRZ => '*IBM_OracleAgents',                                   # RZ
   KEX => '*NT_EXCHANGE',                                        # EX
   KRDB => '*IBM_OracleAgentRD',                                 # RZ
   KSVR => '*HMC_BASE_SERVERS',                                  # SVR
   KM6 => '*IBM_WM',                                             # M6
   KFTE => '*IBM_WMQFTEAgent',                                   # FTE
   KVM => '*VMWARE_VI_AGENT',                                    # VM
   KT5 => '*EM_WRM',                                             # T5
   KT3 => '*EM_DB',                                              # T3
   KQS => '*IBM_KQS',                                            # QS
   KIS => '*NETCOOL_ISM_AGENT',                                  # IS
   KUD => '*UNIVERSAL_DATABASE',                                 # UD
   KQ8 => '*IBM_IPAS_A',                                         # Q8
   KQ7 => '*IBM_IIS',                                            # Q7
   KQ5 => '*MS_CLUSTER',                                         # Q5
   KR3 => '*IBM_RmtAIXOS',                                       # R3
   KMSS => '*MS_SQL_SERVER',                                     # OQ
   KORA => '*ALL_ORACLE',                                        # OR
   KKA4 => '*OS400_OM',                                          # A4
   KTO => '*IBM_ITCAMfT_KTO',                                    # TO
   KIns => '*SAP_R3',                                            # SA
   KNT => '*NT_SYSTEM',                                          # NT
   KKT3A => '*EM_APPLICATION_DB',                                # T3
   KESX => '*VMWARE_VI',                                         # ES
   KTEPS => '*TEPS',                                             # CQ
   KKSDSDE => '*SDMSESS',                                        # SD
   KMQQSG => '*MQ_QSG',                                          # MQ
   KKHTA => '*ITCAM_WEB_SERVER_AGENT',                           # HT
   KR4 => '*IBM_RLinuxOS',                                       # R4
   KTU => '*IBM_KTU',                                            # TU
   KBN => '*IBM_KBN' ,                                           # BN
   KOS => '*CS_K0S',                                             # OS
     # 0S:custommq:M05 *CS_K0SM05
   KCPIRA => '*CPIRA_MGR',                                       # CP
   KKYNT => '*CAM_WAS_PROCESS_SERVER',                           # KY
   KKYJT => '*CAM_J2EE_TOMCAT_SERVER',                           # KJ
   KKHTP => '*CAM_APACHE_WEB_SERVER',                            # KH
   KD4 => '*SERVICES_MANAGEMENT_AGENT',                          # D4
     # D4:06c17c5e:nzxpap159-Prod-NCAL  M        *SERVICES_MANAGEMENT_AGENT_ENVIR
   KLO => '*IBM_KLO',                                            # LO
     # LO:nzapps5_OMPlus =>  *IBM_KLOpro
   K07 => '*GSMA_K07',                                           # 07
   KCONFIG => '*GENERIC_CONFIG',                                 # CF
   KDB2 => '*MVS_DB2',                                           # D5
   KGB => '*LOTUS_DOMINO',                                       # GB
   KWarehouse => '*WAREHOUSE_PROXY',                             # HD
   KIGASCUSTOM_UA00 => '*CUSTOM_IGASCUSTOM_UA00',                # IG
   KLZ => '*LINUX_SYSTEM',                                       # LZ
   KMVSSYS => '*MVS_SYSTEM',                                     # M5
   KRCACFG => '*MQ_AGENT',                                       # MC
   KMQ => '*MVS_MQM',                                            # MQ
   KMQIRA => '*MQIRA_MGR',                                       # MQ
   KMQESA => '*MVS_MQM',                                         # MQ
   KKQIA => '*MQSI_AGENT',                                       # QI
   KPH => '*HMC_BASE',                                           # PH
   KPK => '*CEC_BASE',                                           # PK
   KPV => '*VIOS_BASE',                                          # PV
   KPX => '*AIX_PREMIUM',                                        # PX
   KKQIB => '*MQSI_BROKER,*MQSI_BROKER_V7',                      # QI ???
   KSTORAGE => '*OMEGAMONXE_SMS,*OM_SMS',                        # S3
                                                                #    OMIICT:7VSG:STORAGE         managing agent?
                                                                #    IRAM:OMIICMS:NADH:STORAGE   [subnode??]
   KmySAP => '*SAP_AGENT',                                       # SA
   KSK => '*IBM_TSM_Agent',                                      # SK
   KSY => '*AGGREGATION_AND_PRUNING',                            # SY
   KUAGENT00 => '*CUSTOM_UAGENT00',                              # UA
   KKUL => '*UNIX_LOG_ALERT',                                    # UL
   KUA  => '*UNIVERSAL',                                         # UM
   KKUX => '*ALL_UNIX',                                          # UX
   KVA => '*VIOS_PREMIUM',                                       # VA
   KVL => '*OMXE_VM',                                            # VL
   KKYJA => '*ITCAM_J2EE_AGENT',                                 # YJ
   KKYJN => '*CAM_J2EE_NETWEAVER_SERVER',                        # YJ
   KKYNA => '*ITCAM_WEBSPHERE_AGENT',                            # YN
   KKYNR => '*CAM_WAS_PORTAL_SERVER',                            # YN
   KKYNP => '*CAM_WAS_PROCESS_SERVER',                           # YN
   KKYNS => '*CAM_WAS_SERVER',                                   # YN
   KDSGROUP => '*MVS_DB2',                                       # D5
   KPlexview => '*MVS_DB2',                                      # D5
   KSYSPLEX => '*MVS_SYSPLEX',                                   # M5
);
$hnodelist{'KSNMP-MANAGER00'} ='*CUSTOM_SNMP-MANAGER00';

# Situation Group related data
my %group = ();                            # situation group base data, hash of hashes
my %groupi = ();                           # situation group item data, hash of hashes
my %groupx = ();


# Situation related data

my $siti = -1;                             # count of situations
my $curi;                                  # global index for subroutines
my @sit = ();                              # array of situations
my %sitx = ();                             # Index from situation name to index
my @sit_pdt = ();                          # array of predicates or situation formula
my @sit_ct = ();                           # count of situation references
my @sit_fullname = ();                     # array of fullname
my @sit_psit = ();                         # array of printable situaton names
my @sit_sitinfo = ();                      # array of SITINFO columns
my @sit_autostart = ();                    # array of AUTOSTART columns
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

my $nax;
my $nami = -1;                             # count of fullname indexes
my @nam = ();                              # array of index
my %namx = ();                             # Index from index name to index
my @nam_fullname = ();                     # array of fullnames
my @nam_ct = ();                           # count of tname references

my $evti = -1;                             # event destination data
my @evt = ();
my @evt_lstdate = ();
my @evt_lstusrprf = ();

# option and ini file variables variables

my $opt_txt;                    # input from .txt files
my $opt_txt_tnodelst;           # TNODELIST txt file
my $opt_txt_tnodesav;           # TNODESAV txt file
my $opt_txt_tsitdesc;           # TSITDESC txt file
my $opt_txt_tname;              # TNAME txt file
my $opt_txt_tobjaccl;           # TOBJACCL txt file
my $opt_txt_tgroup;             # TGROUP txt file
my $opt_txt_tgroupi;            # TGROUPI txt file
my $opt_txt_evntserver;         # EVNTSERVER txt file
my $opt_lst;                    # input from .lst files
my $opt_lst_tnodesav;           # TNODESAV lst file
my $opt_lst_tnodelst;           # TNODELST lst file
my $opt_lst_tsitdesc;           # TSITDESC lst file
my $opt_lst_tname;              # TNAME lst file
my $opt_lst_tobjaccl;           # TOBJACCL lst file
my $opt_lst_tgroup;             # TGROUP lst file
my $opt_lst_tgroupi;            # TGROUPI lst file
my $opt_lst_evntserver;         # EVNTSERVER lst file
my $opt_log;                    # name of log file
my $opt_ini;                    # name of ini file
my $opt_hub;                    # externally supplied nodeid of hub TEMS
my $opt_debuglevel;             # Debug level
my $opt_debug;                  # Debug level
my $opt_h;                      # help file
my $opt_v;                      # verbose flag
my $opt_vt;                     # verbose traffic flag
my $opt_dpr;                    # dump data structure flag
my $opt_o;                      # output file
my $opt_s;                      # write summary line if max impact > 0
my $opt_workpath;               # Directory to store output files
my $opt_nohdr = 0;              # skip header to make regression testing easier
my $opt_subpc_warn;             # advise when subnode length > 90 of limit on pre ITM 623 FP2
my $opt_peak_rate;              # Advise when virtual hub update peak is higher
my $opt_vndx;                   # when 1 create a index for missing TNODELST NODETYPE=V records
my $opt_vndx_fn;                # when opt_vndx - this is filename
my $opt_mndx;                   # when 1 create a index for missing TNODELST NODETYPE=M records
my $opt_mndx_fn;                # when opt_mndx - this is filename
my $opt_miss;                   # when 1 create a missing.sql file
my $opt_miss_fn;                # missing file SQL name
my $opt_nodist;            # TGROUP names which are planned as non-distributed

# do basic initialization from parameters, ini file and standard input

$rc = init($args_start);

$opt_log = $opt_workpath . $opt_log;
$opt_o = $opt_workpath . $opt_o;
$opt_s = $opt_workpath . $opt_s;
$opt_log =~ s/\\\\/\//g;
$opt_log =~ s/\/\//\//g;
$opt_o =~ s/\\\\/\//g;
$opt_o =~ s/\/\//\//g;
$opt_s =~ s/\\\\/\//g;
$opt_s =~ s/\/\//\//g;

open FH, ">>$opt_log" or die "can't open $opt_log: $!";

logit(0,"SITAUDIT000I - ITM_Situation_Audit $gVersion $args_start");

# process three different sources of situation data

if ($opt_txt == 1) {                    # text files
   $rc = init_txt();
} elsif ($opt_lst == 1) {               # KfwSQLClient LST files
   $rc = init_lst();
}


open OH, ">$opt_o" or die "can't open $opt_o: $!";

if ($opt_vndx == 1) {
   open NDX, ">$opt_vndx_fn" or die "can't open $opt_vndx_fn: $!";
}

if ($opt_mndx == 1) {
   open MDX, ">$opt_mndx_fn" or die "can't open $opt_mndx_fn: $!";
}

if ($opt_miss == 1) {
   open MIS, ">$opt_miss_fn" or die "can't open $opt_miss_fn: $!";
}



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

$hub_tems = $opt_hub if $hub_tems eq "";
if ($hub_tems_no_tnodesav == 0) {
   # following is a rare case where the TNODELIST *HUB entry is missing.
   # for analysis work, that can be supplied by a -hub <nodeid> parameter
   if ($hub_tems eq "") {
      $advi++;$advonline[$advi] = "*HUB node missing from TNODELIST Type M records";
      $advcode[$advi] = "DATAHEALTH1038E";
      $advimpact[$advi] = 105;
      $advsit[$advi] = "*HUB";
   } else {
      $hubi = $temsx{$hub_tems};
      for ($i=0; $i<=$nlistvi; $i++) {
         my $node1 = $nlistv[$i];
         next if $nlistv_tems[$i] eq "";
         my $tems1 = $nlistv_tems[$i];
         my $tx = $temsx{$tems1};
         next if !defined $tx;
         $hub_tems_ct += 1;
         $tems_ct[$tx] += 1;
         my $nx = $nsavex{$node1};
         next if !defined $nx;
         if (($nsave_product[$nx] ne "CQ") and ($nsave_product[$nx] ne "HD") and ($nsave_product[$nx] ne "SY")) {
            $tems_ctnok[$tx] += 1;
         }
      }
   }
}


for ($i=0; $i<=$nsavei; $i++) {
   my $node1 = $nsave[$i];
   next if $nsave_product[$i] eq "EM";
   $nsx = $nlistvx{$node1};
   next if defined $nsx;
   if (index($node1,":") !=  -1) {
      $advi++;$advonline[$advi] = "Node present in node status but missing in TNODELIST Type V records";
      $advcode[$advi] = "DATAHEALTH1001E";
      $advimpact[$advi] = 100;
      $advsit[$advi] = $node1;
      next if $opt_vndx == 0;
      print NDX "$node1\n";
   }
}

for ($i=0; $i<=$nsavei; $i++) {
   my $node1 = $nsave[$i];
   next if $nsave_product[$i] eq "EM";
   my $product1 = $nsave_product[$i];
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
         my $known_ext = 0;
         @words = split(":",$node1);
         if ($#words > 0) {
            my $lastseg = $words[$#words];
            my $keyseg = "K" . $lastseg;
           $known_ext = 1 if defined $hnodelist{$keyseg};
         }
         next if $known_ext == 1;
         $advi++;$advonline[$advi] = "Node Name at 32 characters and might be truncated - product[$product1]";
         $advcode[$advi] = "DATAHEALTH1013W";
         $advimpact[$advi] = 10;
         $advsit[$advi] = $node1;
      } else {
         next if length($node1) < 31;
         $advi++;$advonline[$advi] = "Subnode Name at 31/32 characters and might be truncated - product[$product1]";
         $advcode[$advi] = "DATAHEALTH1014W";
         $advimpact[$advi] = 10;
         $advsit[$advi] = $node1;
      }
   }
}

for ($i=0; $i<=$magenti;$i++) {
   my $onemagent = $magent[$i];
   next if $magent_tems_version[$i] ge "06.23.02";
   if ($magent_sublen[$i]*100 > $opt_subpc_warn*32768){
      $advi++;$advonline[$advi] = "Managing agent subnodelist is $magent_sublen[$i]: more then $opt_subpc_warn% of 32768 bytes";
      $advcode[$advi] = "DATAHEALTH1015W";
      $advimpact[$advi] = 90;
      $advsit[$advi] = $onemagent;
   }
}

for ($i=0; $i<=$evti;$i++) {
   my $oneid = $evt[$i];
   if ($evt_lstdate[$i] eq "") {
      $advi++;$advonline[$advi] = "Event Destination LSTDATE is blank and will not synchronize in FTO configuration";
      $advcode[$advi] = "DATAHEALTH1039E";
      $advimpact[$advi] = 100;
      $advsit[$advi] = $oneid;
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
   if (index($node1,":") !=  -1) {
      $advi++;$advonline[$advi] = "Node without a system generated MSL in TNODELIST Type M records";
      $advcode[$advi] = "DATAHEALTH1002E";
      $advimpact[$advi] = 90;
      $advsit[$advi] = $node1;
      next if $opt_mndx == 0;
      print MDX "$node1\n";
   }
}

for ($i=0; $i<=$nlistmi; $i++) {
   my $node1 = $nlistm[$i];
   if ($nlistm_miss[$i] != 0) {
      $advi++;$advonline[$advi] = "Node present in TNODELST Type M records but missing in Node Status";
      $advcode[$advi] = "DATAHEALTH1003I";
      $advimpact[$advi] = 0;
      $advsit[$advi] = $node1;
      if ($opt_miss == 1) {
         my $key = "DATAHEALTH1003I" . " " . $node1;
         $miss{$key} = 1;
      }
   }
   if ($nlistm_nov[$i] != 0) {
      $advi++;$advonline[$advi] = "Node present in TNODELST Type M records but missing TNODELIST Type V records";
      $advcode[$advi] = "DATAHEALTH1004I";
      $advimpact[$advi] = 0;
      $advsit[$advi] = $node1;
   }
}

foreach my $f (keys %group) {
   my $group_detail_ref = $group{$f};
   if ($group_detail_ref->{indirect} == 0) {
      my $nodist = 0;
      if ($opt_nodist ne "") {
         if (substr($group_detail_ref->{grpname},0,length($opt_nodist)) eq $opt_nodist){
            $nodist = 1;
         }
      }
      if ($nodist == 0) {
         my $gkey = substr($f,5);
         my $ox = $tobjaccl{$gkey};
         if (!defined $ox) {
            $advi++;$advonline[$advi] = "TGROUP ID $f NAME $group_detail_ref->{grpname} not distributed in TOBJACCL";
            $advcode[$advi] = "DATAHEALTH1034W";
            $advimpact[$advi] = 10;
            $advsit[$advi] = $group_detail_ref->{grpname};
         }
      }
   }
}

for ($i=0;$i<=$nsavei;$i++) {
   $invalid_node = 0;
   if (index("\.\ \*\#",substr($nsave[$i],0,1)) != -1) {
      $invalid_node = 1;
   } else {
      $test_node = $nsave[$i];
      $test_node =~ s/[A-Za-z0-9\*\ \_\-\:\@\$\#\.]//g;
      $invalid_node = 1 if $test_node ne "";
   }
   if ($invalid_node == 1) {
      $advi++;$advonline[$advi] = "TNODESAV invalid node name";
      $advcode[$advi] = "DATAHEALTH1016E";
      $advimpact[$advi] = 50;
      $advsit[$advi] = $nsave[$i];
   }
   next if $nsave_ct[$i] == 1;
   $advi++;$advonline[$advi] = "TNODESAV duplicate nodes";
   $advcode[$advi] = "DATAHEALTH1007E";
   $advimpact[$advi] = 105;
   $advsit[$advi] = $nsave[$i];
}

for ($i=0;$i<=$siti;$i++) {
   if (substr($sit[$i],0,8) eq "UADVISOR") {
      if ($sit_autostart[$i] ne "*NO") {              ##check maybe ne "*NO" versus *SYN ????
         my $hx = $hSP2OS{$sit[$i]};
         if (defined $hx) {
            $vtx = $vtnodex{$hx};
            if (defined $vtx) {
               $vtnode_tab[$vtx] += 1;
            }
         }
      }

   }
   next if $sit_ct[$i] == 1;
   $advi++;$advonline[$advi] = "TSITDESC duplicate nodes";
   $advcode[$advi] = "DATAHEALTH1021E";
   $advimpact[$advi] = 105;
   $advsit[$advi] = $sit[$i];
}

for ($i=0;$i<=$nami;$i++) {
   next if $nam_ct[$i] == 1;
   $advi++;$advonline[$advi] = "TNAME duplicate nodes";
   $advcode[$advi] = "DATAHEALTH1022E";
   $advimpact[$advi] = 105;
   $advsit[$advi] = $nam[$i];
}

for ($i=0;$i<=$nami;$i++) {
   next if defined $sitx{$nam[$i]};
   next if substr($nam[$i],0,8) eq "UADVISOR";
   $advi++;$advonline[$advi] = "TNAME ID index missing in TSITDESC";
   $advcode[$advi] = "DATAHEALTH1023E";
   $advimpact[$advi] = 25;
   $advsit[$advi] = $nam[$i];
}

for ($i=0;$i<=$siti;$i++) {
   my $pdtone = $sit_pdt[$i];
   my $mysit;
   while($pdtone =~ m/.*?\*SIT (\S+) /g) {
      $mysit = $1;
      next if defined $sitx{$mysit};
      $advi++;$advonline[$advi] = "Situation Formula *SIT [$mysit] Missing from TSITDESC table";
      $advcode[$advi] = "DATAHEALTH1024E";
      $advimpact[$advi] = 90;
      $advsit[$advi] = $sit[$i];
   }

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
      next if $onethru eq ".";
      if (defined $nx) {
         $pagents .= $nsave[$pi]. "[$onethru][Y] " if $nsave_o4online[$nx] eq "Y";
      } else {
         $pagents .= $nsave[$pi]. "[][Y] " if $nsave_o4online[$nx] eq "Y";
      }
   }
   my @ragents = split(" ",$pagents);
   next if $#ragents < 1;
   $advi++;$advonline[$advi] = "TNODESAV duplicate hostaddr in [$pagents]";
   $advcode[$advi] = "DATAHEALTH1010W";
   $advimpact[$advi] = 80;
   $advsit[$advi] = $hsave[$i];
}

for ($i=0;$i<=$nlistvi;$i++) {
   if ($nlistv_ct[$i] > 1) {
      $advi++;$advonline[$advi] = "TNODELST Type V duplicate nodes";
      $advcode[$advi] = "DATAHEALTH1008E";
      $advimpact[$advi] = 105;
      $advsit[$advi] = $nlistv[$i];
   }
   my $thru1 = $nlistv_thrunode[$i];
   $nsx = $nsavex{$thru1};
   if (!defined $nsx) {
      $advi++;$advonline[$advi] = "TNODELST Type V Thrunode $thru1 missing in Node Status";
      $advcode[$advi] = "DATAHEALTH1025E";
      $advimpact[$advi] = 100;
      $advsit[$advi] = $nlistv[$i];
      if ($opt_miss == 1) {
         my $key = "DATAHEALTH1025E" . " " . $thru1;
         $miss{$key} = 1;
      }
   }
   $invalid_node = 0;
   if (index("\.\ \*\#",substr($nlistv[$i],0,1)) != -1) {
      $invalid_node = 1;
   } else {
      $test_node = $nlistv[$i];
      $test_node =~ s/[A-Za-z0-9\*\ \_\-\:\@\$\#\.]//g;
      $invalid_node = 1 if $test_node ne "";
   }
   if ($invalid_node == 1) {
      $advi++;$advonline[$advi] = "TNODELST Type V node invalid name";
      $advcode[$advi] = "DATAHEALTH1026E";
      $advimpact[$advi] = 50;
      $advsit[$advi] = $nlistv[$i];
   }
   $invalid_node = 0;
   if (index("\.\ \*\#",substr($thru1,0,1)) != -1) {
      $invalid_node = 1;
   } else {
      $test_node = $thru1;
      $test_node =~ s/[A-Za-z0-9\*\ \_\-\:\@\$\#\.]//g;
      $invalid_node = 1 if $test_node ne "";
   }
   if ($invalid_node == 1) {
      $advi++;$advonline[$advi] = "TNODELST Type V Thrunode $thru1 invalid name";
      $advcode[$advi] = "DATAHEALTH1027E";
      $advimpact[$advi] = 50;
      $advsit[$advi] = $nlistv[$i];
   }
}

##check nodelist validity
for ($i=0;$i<=$nlisti;$i++) {
   $invalid_node = 0;
   if (index("\.\ \#",substr($nlist[$i],0,1)) != -1) {
      $invalid_node = 1;
   } else {
      $test_node = $nlist[$i];
      $test_node =~ s/[A-Za-z0-9\* _\-:@\$\#\.]//g;
      $invalid_node = 1 if $test_node ne "";
   }
   if ($invalid_node == 1) {
      $advi++;$advonline[$advi] = "TNODELIST NODETYPE=M invalid nodelist name";
      $advcode[$advi] = "DATAHEALTH1017E";
      $advimpact[$advi] = 50;
      $advsit[$advi] = $nlist[$i];
   }
}

# check TOBJACCL validity
for ($i=0;$i<=$obji;$i++){
   if ($obj_ct[$i] > 1) {
      $advi++;$advonline[$advi] = "TOBJACCL duplicate nodes";
      $advcode[$advi] = "DATAHEALTH1028E";
      $advimpact[$advi] = 105;
      $advsit[$advi] = $obj[$i];
   }
   my $objname1 = $obj_objname[$i];
   my $nodel1 = $obj_nodel[$i];
   my $class1 = $obj_objclass[$i];
   if ($class1 == 5140) {
      next if defined $nlistx{$nodel1};         # if known as a MSL, no check for node status
      my $nodist = 0;
      if ($opt_nodist ne "") {
         if (substr($nodel1,0,length($opt_nodist)) eq $opt_nodist){
            $nodist = 1;
         }
         if (substr($objname1,0,length($opt_nodist)) eq $opt_nodist){
            $nodist = 1;
         }
      }
      next if $nodist == 1;
      if (substr($nodel1,0,1) eq "*") {
         $advi++;$advonline[$advi] = "TOBJACCL Nodel $nodel1 Apparent MSL but missing from TNODELST";
         $advcode[$advi] = "DATAHEALTH1029W";
         $advimpact[$advi] = 0;
         $advsit[$advi] = $obj[$i];
         if ($opt_miss == 1) {
            my $pick = $obj[$i];
            $pick =~ /.*\|.*\|(.*)/;
            my $key = "DATAHEALTH1029W" . " " . $1;
            $miss{$key} = 1;
         }
         next;
      }
      $nsx = $nsavex{$nodel1};
      if (!defined $nsx) {
         $advi++;$advonline[$advi] = "TOBJACCL Node or MSL [$nodel1] missing from TNODESAV or TNODELST";
         $advcode[$advi] = "DATAHEALTH1030W";
         $advimpact[$advi] = 0;
         $advsit[$advi] = $obj[$i];
         if ($opt_miss == 1) {
            my $pick = $obj[$i];
            $pick =~ /.*\|.*\|(.*)/;
            my $key = "DATAHEALTH1030W" . " " . $1;
            $miss{$key} = 1;
         }
      }
   } elsif ($class1 == 2010) {
      next if defined $groupx{$objname1};       # if item being distributed is known as a situation group, good
      $advi++;$advonline[$advi] = "TOBJACCL Group name missing in Situation Group";
      $advcode[$advi] = "DATAHEALTH1035W";
      $advimpact[$advi] = 0;
      $advsit[$advi] = $nodel1;
$DB::single=2;
      if ($opt_miss == 1) {
$DB::single=2;
         my $pick = $nodel1;
         $pick =~ /.*\|.*\|(.*)/;
         my $key = "DATAHEALTH1035W" . " " . $1;
         $miss{$key} = 1;
      }
   }
}



##check for TEMA level 6.1
for ($i=0;$i<=$nsavei;$i++) {
   next if $nsave_temaver[$i] eq "";
   next if substr($nsave_temaver[$i],0,5) gt "06.10";
   $advi++;$advonline[$advi] = "Agent using TEMA at $nsave_temaver[$i] level";
   $advcode[$advi] = "DATAHEALTH1019W";
   $advimpact[$advi] = 10;
   $advsit[$advi] = $nsave[$i];
}
## Check for TEMA level below Agent version
for ($i=0;$i<=$nsavei;$i++) {
   next if $nsave_temaver[$i] eq "";
   next if substr($nsave_temaver[$i],0,3) ne "06.";
   next if substr($nsave_temaver[$i],0,2) ne substr($nsave_version[$i],0,2);
   next if substr($nsave_temaver[$i],0,5) ge substr($nsave_version[$i],0,5);
   $advi++;$advonline[$advi] = "Agent at version [$nsave_version[$i]] using TEMA at lower release version [$nsave_temaver[$i]]";
   $advcode[$advi] = "DATAHEALTH1037W";
   $advimpact[$advi] = 25;
   $advsit[$advi] = $nsave[$i];
}
## Check for virtual hub table update impact
my $peak_rate = 0;
for ($i=0;$i<=$vti;$i++) {
   next if $vtnode_tab[$i] == 0;
   my $node_hr = (60/$vtnode_rate[$i])*$vtnode_tab[$i];
   $vtnode_hr[$i] = $node_hr*$vtnode_ct[$i];
   $vtnode_tot_hr += $vtnode_hr[$i];
   $peak_rate +=  $vtnode_ct[$i] * $vtnode_tab[$i];
}

if ($peak_rate > $opt_peak_rate) {
   for ($i=0;$i<=$vti;$i++) {
      next if $vtnode_hr[$i] == 0;
      $advi++;$advonline[$advi] = "Virtual Hub Table updates $vtnode_hr[$i] per hour $vtnode_ct[$i] agents";
      $advcode[$advi] = "DATAHEALTH1018W";
      $advimpact[$advi] = 90;
      $advsit[$advi] = $vtnode[$i];
   }
   $advi++;$advonline[$advi] = "Virtual Hub Table updates peak $peak_rate per second more then nominal $opt_peak_rate -  per hour [$vtnode_tot_hr] - total agents $vtnode_tot_ct";
   $advcode[$advi] = "DATAHEALTH1018W";
   $advimpact[$advi] = 90;
   $advsit[$advi] = "total";
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
   if (defined $hubi) {
      my $hub_limit = 10000;
      $hub_limit = 20000 if substr($tems_ct[$hubi],0,5) gt "06.23";

      if ($hub_tems_ct > $hub_limit){
         $advi++;$advonline[$advi] = "Hub TEMS has $hub_tems_ct managed systems which exceeds limits $hub_limit";
         $advcode[$advi] = "DATAHEALTH1005W";
         $advimpact[$advi] = 75;
         $advsit[$advi] = $hub_tems;
      }
   }


   print OH "Hub,$hub_tems,$hub_tems_ct\n";
   for (my $i=0;$i<=$temsi;$i++) {
      if ($tems_thrunode[$i] eq $tems[$i]) {
         # The following test is how a hub TEMS is distinguished from a remote TEMS
         # This checks an affinity capability flag which indicates the policy microscope
         # is available. I tried many ways and failed before finding this.
         if (substr($tems_affinities[$i],40,1) eq "O") {
            $isFTO += 1;
         }
      }
      if ($tems_ct[$i] > $remote_limit){
         $advi++;$advonline[$advi] = "TEMS has $tems_ct[$i] managed systems which exceeds limits $remote_limit";
         $advcode[$advi] = "DATAHEALTH1006W";
         $advimpact[$advi] = 75;
         $advsit[$advi] = $tems[$i];
      }
      my $poffline = "Offline";
      my $node1 = $tems[$i];
      my $nx = $nsavex{$node1};
      if (defined $nx) {
         $poffline = "Online" if $nsave_o4online[$nx] eq "Y";
      }
      print OH "TEMS,$tems[$i],$tems_ct[$i],$poffline,$tems_version[$i]\n";
   }
   print OH "\n";

   # One case had 3 TEMS in FTO mode - so check for 2 or more
   if ($isFTO >= 2){
      print OH "Fault Tolerant Option FTO enabled\n\n";
      if ($tems_ctnok[$hubi] > 0) {
         $advi++;$advonline[$advi] = "FTO hub TEMS has $tems_ctnok[$hubi] agents configured which is against FTO best practice";
         $advcode[$advi] = "DATAHEALTH1020W";
         $advimpact[$advi] = 80;
         $advsit[$advi] = $hub_tems;
      }
   }
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
      $max_impact = $advimpact[$j] if $advimpact[$j] > $max_impact;
   }
}

if ($opt_s ne "") {
   if ($max_impact > 0 ) {
        open SH, ">$opt_s";
        if (tell(SH) != -1) {
           $oneline = "REFIC ";
           $oneline .= $max_impact . " ";
           $oneline .= $tadvi . " ";
           $oneline .= "https://ibm.biz/BdFrJL";
           print SH $oneline . "\n";
           close SH;
        }
   }
}

if ($opt_vndx == 1) {
   close(NDX);
}
if ($opt_mndx == 1) {
   close(MDX);
}
if ($opt_miss == 1) {
   foreach my $f (keys %miss) {
     $f =~ /(.*) (.*)/;
     my $code = $1;
     my $obj = $2;
     die "key $f in wrong format" if !defined $1;
     die "key $f in wrong format" if !defined $2;
     if ($code eq "DATAHEALTH1003I") {
        $oneline = "DELETE FROM O4SRV.TNODELST WHERE NODETYPE='V' AND NODELIST='";
        $oneline .= $obj;
        $oneline .= "' AND SYSTEM.PARMA('QIBUSER','_CLEANUP',8) AND SYSTEM.PARMA('QIBCLASSID','5529',4);";
        print MIS "$oneline\n";
     } elsif  ($code eq "DATAHEALTH1025E") {
        $oneline = "DELETE FROM O4SRV.TOBJACCL WHERE OBJCLASS='5140' AND NODEL='";
        $oneline .= $obj;
        $oneline .= "' AND SYSTEM.PARMA('QIBUSER','_CLEANUP',8) AND SYSTEM.PARMA('QIBCLASSID','5535',4);";
        print MIS "$oneline\n";
     } elsif  ($code eq "DATAHEALTH1029E") {
        $oneline = "DELETE FROM O4SRV.TOBJACCL WHERE OBJCLASS='5140' AND NODEL='";
        $oneline .= $obj;
        $oneline .= "' AND SYSTEM.PARMA('QIBUSER','_CLEANUP',8) AND SYSTEM.PARMA('QIBCLASSID','5535',4);";
        print MIS "$oneline\n";
     } elsif  ($code eq "DATAHEALTH1030E") {
        $oneline = "DELETE FROM O4SRV.TNODELST WHERE NODETYPE='M' AND NODE='";
        $oneline .= $obj;
        $oneline .= "'  AND SYSTEM.PARMA('QIBUSER','_CLEANUP',8) AND SYSTEM.PARMA('QIBCLASSID','5529',4);";
        print MIS "$oneline\n";
     } else {
         print STDERR "Unknown advisory code $code\n";
     }
   }
   close(MIS);
}

my $exit_code = 0;
if ($advi != -1) {
   $exit_code = ($max_impact > 0);
}
exit $exit_code;

sub new_evntserver {
   my ($iid,$ilstdate,$ilstusrprf) = @_;
   $evti += 1;
   $evt[$evti] = $iid;
   $evt_lstdate[$evti] = $ilstdate;
   $evt_lstusrprf[$evti] = $ilstusrprf;
}

sub new_tgroup {
   my ($igrpclass,$iid,$igrpname) = @_;
   my $key = $igrpclass . "|" . $iid;
   my $group_detail_ref = $group{$key};

   if (!defined $group_detail_ref) {
      my %igroup = (
                      grpclass => $igrpclass,      # GRPCLASS usually 2010
                      id => $iid,                   # ID is the internal group name
                      grpname => $igrpname,        # GRPNAME is external user name
                      indirect => 0,               # when 1, included in a TGROUPI and so no distribution expected
                      count => 0,
                   );
      $group_detail_ref = \%igroup;
      $group{$key} = \%igroup;
   }
  $group_detail_ref->{count} += 1;
  $groupx{$iid} = 1;
}

sub new_tgroupi {
   my ($igrpclass,$iid,$iobjclass,$iobjname) = @_;
   my $key = $igrpclass . "|" . $iid . "|" . $iobjclass . "|" . $iobjname;
   my $groupi_detail_ref = $groupi{$key};
   if (!defined $groupi_detail_ref) {
      my %igroupi = (
                      grpclass => $igrpclass,      # GRPCLASS usually 2010
                      id => $iid,                   # ID is the internal group name
                      objclass => $iobjclass,
                      objname => $iobjname,
                      count => 0,
                   );
      $groupi_detail_ref = \%igroupi;
      $groupi{$key} = \%igroupi;
   }
  $groupi_detail_ref->{count} += 1;
  my $gkey = $igrpclass . "|" . $iid;
  my $group_ref = $group{$gkey};
  if (!defined $group_ref) {
$DB::single=2;
     $advi++;$advonline[$advi] = "TGROUPI $key unknown TGROUP ID";
     $advcode[$advi] = "DATAHEALTH1031E";
     $advimpact[$advi] = 50;
     $advsit[$advi] = $iid;
  }
  if ($groupi_detail_ref->{objclass} == 2010) {
$DB::single=2;
     my $groupref = $groupi_detail_ref->{objclass};
    $gkey = "2010" . "|" . $iid;
     my $group_ref = $group{$gkey};
     if (!defined $group_ref) {
$DB::single=2;
        $advi++;$advonline[$advi] = "TGROUPI $key unknown Group $iobjname";
        $advcode[$advi] = "DATAHEALTH1032E";
        $advimpact[$advi] = 50;
        $advsit[$advi] = $iobjname;
     } else {
$DB::single=2;
        $group_ref->{indirect} = 1;
     }
  } elsif ($groupi_detail_ref->{objclass} == 5140) {
     my $sit1 = $groupi_detail_ref->{objname};
     if (!defined $sitx{$sit1}) {
$DB::single=2;
        $advi++;$advonline[$advi] = "TGROUPI $key unknown Situation $iobjname";
        $advcode[$advi] = "DATAHEALTH1033E";
        $advimpact[$advi] = 50;
        $advsit[$advi] = $iobjname;
     }
  } else {
$DB::single=2;
     die "Unknown TGROUPI objclass $groupi_detail_ref->{objclass} working on $igrpclass $iid $iobjclass $iobjname";
  }
}

sub new_tobjaccl {
   my ($iobjclass,$iobjname,$inodel) = @_;
   my $key = $inodel . "|". $iobjclass . "|" . $iobjname;
   my $ox = $objx{$key};
   if (!defined $ox) {
      $obji += 1;

      $ox = $obji;
      $obj[$obji] = $key;
      $objx{$key} = $obji;
      $obj_objclass[$obji] = $iobjclass;
      $obj_objname[$obji] = $iobjname;
      $obj_nodel[$obji] = $inodel;
      $obj_ct[$obji] = 0;
   }
  $obj_ct[$ox] += 1;
  $tobjaccl{$iobjname} = 1;
}

sub new_tsitdesc {
   my ($isitname,$iautostart,$ipdt) = @_;
   $sx = $sitx{$isitname};
   if (!defined $sx) {
      $siti += 1;
      $sx = $siti;
      $sit[$siti] = $isitname;
      $sitx{$isitname} = $siti;
      $sit_autostart[$siti] = $iautostart;
      $sit_pdt[$siti] = $ipdt;
      $sit_ct[$siti] = 0;
   }
  $sit_ct[$sx] += 1;
}

sub new_tname {
   my ($iid,$ifullname) = @_;
   $nax = $namx{$iid};
   if (!defined $nax) {
      $nami += 1;
      $nax = $nami;
      $nam[$nami] = $iid;
      $namx{$iid} = $nami;
      $nam_fullname[$nami] = $ifullname;
      $nam_ct[$nami] = 0;
   }
   $nam_ct[$nax] += 1;
}

# Record data from the TNODESAV table. This is the disk version of [most of] the INODESTS or node status table.
# capture node name, product, version, online status


sub new_tnodesav {
   my ($inode,$iproduct,$iversion,$io4online,$ihostaddr,$ireserved,$ithrunode,$iaffinities) = @_;
   $nsx = $nsavex{$inode};
   if (!defined $nsx) {
      $nsavei++;
      $nsx = $nsavei;
      $nsave[$nsx] = $inode;
      $nsavex{$inode} = $nsx;
      $nsave_sysmsl[$nsx] = 0;
      $nsave_product[$nsx] = $iproduct;
      if ($iversion ne "") {
         my $tversion = $iversion;
         $tversion =~ s/[0-9\.]+//g;
         if ($tversion ne "") {
            $advi++;$advonline[$advi] = "Invalid agent version [$iversion] in node $inode tnodesav";
            $advcode[$advi] = "DATAHEALTH1036E";
            $advimpact[$advi] = 25;
            $advsit[$advi] = $inode;
            $iversion = "00.00.00";
         }
      }
      $nsave_version[$nsx] = $iversion;
      $nsave_ct[$nsx] = 0;
      $nsave_o4online[$nsx] = $io4online;
      if (length($ireserved) == 0) {
         $nsave_temaver[$nsx] = "";
      } else {
         my @words;
         @words = split(";",$ireserved);
         $nsave_temaver[$nsx] = "";
         # found one agent with RESERVED == A=00:ls3246;;;
         if ($#words > 0) {
            if ($words[1] ne "") {
               @words = split(":",$words[1]);
               $nsave_temaver[$nsx] = substr($words[0],2,8);
            }
         }
      }
   }
   $vtx = $vtnodex{$iproduct};
   if (defined $vtx) {
      $vtnode_ct[$vtx] += 1;
      $vtnode_tot_ct += 1;
   }
   # count number of nodes. If more then one there is a primary key duplication error
   $nsave_ct[$nsx] += 1;
   # track the TEMS and the version
   if ($iproduct eq "EM") {
      $tx = $temsx{$inode};
      if (!defined $tx) {
         $temsi += 1;
         $tx = $temsi;
         $tems[$tx] = $inode;
         $temsx{$inode} = $tx;
         $tems_hub[$tx] = 0;
         $tems_ct[$tx] = 0;
         $tems_ctnok[$tx] = 0;
         $tems_version[$tx] = $iversion;
         $tems_thrunode[$tx] = $ithrunode;
         $tems_affinities[$tx] = $iaffinities;
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

   $nlx = $nlistx{$inodelist};
   if (!defined $nlx) {
      $nlisti += 1;
      $nlx = $nlisti;
      $nlist[$nlx] = $inodelist;
      $nlistx{$inodelist} = $nlx;
   }

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
   my $ireserved;
   my $ithrunode;
   my $iaffinities;

   my @ksit_data;
   my $isitname;
   my $iautostart;
   my $ipdt;

   my @knam_data;
   my $iid;
   my $ifullname;

   my @kobj_data;
   my $iobjclass;
   my $iobjname;
   my $inodel;

   my @kgrp_data;
   my $igrpclass;
   my $igrpname;

   my @kgrpi_data;

   my @kevsr_data;
   my $ilstdate;
   my $ilstusrprf;

   open(KSAV, "< $opt_txt_tnodesav") || die("Could not open TNODESAV $opt_txt_tnodesav\n");
   @ksav_data = <KSAV>;
   close(KSAV);

   # Get data for all TNODESAV records
   $ll = 0;
   foreach $oneline (@ksav_data) {
      $ll += 1;
      next if $ll < 5;
      chop $oneline;
      $oneline .= " " x 400;
      $inode = substr($oneline,0,32);
      $inode =~ s/\s+$//;   #trim trailing whitespace
      $io4online = substr($oneline,33,1);

      # if offline with no product, ignore - maybe produce advisory later
      $iproduct = substr($oneline,42,2);
      $iproduct =~ s/\s+$//;   #trim trailing whitespace
      if ($io4online eq "N") {
         next if $iproduct eq "";
      }
      $iversion = substr($oneline,50,8);
      $iversion =~ s/\s+$//;   #trim trailing whitespace
      $ihostaddr = substr($oneline,59,256);
      $ihostaddr =~ s/\s+$//;   #trim trailing whitespace
      $ireserved = substr($oneline,315,64);
      $ireserved =~ s/\s+$//;   #trim trailing whitespace
      $ithrunode = substr($oneline,380,32);
      $ithrunode =~ s/\s+$//;   #trim trailing whitespace
      $iaffinities = substr($oneline,413,43);
      $iaffinities =~ s/\s+$//;   #trim trailing whitespace
      new_tnodesav($inode,$iproduct,$iversion,$io4online,$ihostaddr,$ireserved,$ithrunode,$iaffinities);
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
     #next if $inodetype ne "M";
      new_tnodelstm($inodetype,$inodelist,$inode);
   }

   open(KSIT, "< $opt_txt_tsitdesc") || die("Could not open TSITDESC $opt_txt_tsitdesc\n");
   @ksit_data = <KSIT>;
   close(KSIT);

   # Get data for all TSITDESC records
   $ll = 0;
   foreach $oneline (@ksit_data) {
      $ll += 1;
      next if $ll < 5;
      chop $oneline;
      $oneline .= " " x 400;
      $isitname = substr($oneline,0,32);
      $isitname =~ s/\s+$//;   #trim trailing whitespace
      $iautostart = substr($oneline,33,4);
      $iautostart =~ s/\s+$//;   #trim trailing whitespace
      $ipdt = substr($oneline,43);
      $ipdt =~ s/\s+$//;   #trim trailing whitespace
      new_tsitdesc($isitname,$iautostart,$ipdt);
   }

   open(KNAM, "< $opt_txt_tname") || die("Could not open TNAME $opt_txt_tname\n");
   @knam_data = <KNAM>;
   close(KNAM);

   # Get data for all TNAME records
   $ll = 0;
   foreach $oneline (@knam_data) {
      $ll += 1;
      next if $ll < 5;
      chop $oneline;
      $oneline .= " " x 400;
      $iid  = substr($oneline,0,32);
      $iid =~ s/\s+$//;   #trim trailing whitespace
      $ifullname = substr($oneline,33);
      $ifullname =~ s/\s+$//;   #trim trailing whitespace
      new_tname($iid,$ifullname);
   }

   open(KOBJ, "< $opt_txt_tobjaccl") || die("Could not open TOBJACCL $opt_txt_tobjaccl\n");
   @kobj_data = <KOBJ>;
   close(KOBJ);

   # Get data for all TOBJACCL records
   $ll = 0;
   foreach $oneline (@kobj_data) {
      $ll += 1;
      next if $ll < 5;
      chop $oneline;
      $oneline .= " " x 400;
      $iobjclass = substr($oneline,0,4);
      $iobjclass =~ s/\s+$//;   #trim trailing whitespace
      $iobjname = substr($oneline,9,32);
      $iobjname =~ s/\s+$//;   #trim trailing whitespace
      $inodel = substr($oneline,42,32);
      $inodel =~ s/\s+$//;   #trim trailing whitespace
      next if ($iobjclass != 5140) and ($iobjclass != 2010);
      new_tobjaccl($iobjclass,$iobjname,$inodel);
   }

   open(KGRP, "< $opt_txt_tgroup") || die("Could not open TGROUP $opt_txt_tgroup\n");
   @kgrp_data = <KGRP>;
   close(KGRP);

   # Get data for all TGROUP records
   $ll = 0;
   foreach $oneline (@kgrp_data) {
      $ll += 1;
      next if $ll < 5;
      chop $oneline;
      $oneline .= " " x 400;
      $igrpclass = substr($oneline,0,4);
      $igrpclass =~ s/\s+$//;   #trim trailing whitespace
      $iid  = substr($oneline,9,32);
      $iid =~ s/\s+$//;   #trim trailing whitespace
      $igrpname = substr($oneline,42,32);
      $igrpname =~ s/\s+$//;   #trim trailing whitespace
      new_tgroup($igrpclass,$iid,$igrpname);
   }

   open(KGRPI, "< $opt_txt_tgroupi") || die("Could not open TGROUPI $opt_txt_tgroupi\n");
   @kgrpi_data = <KGRPI>;
   close(KGRPI);

   # Get data for all TGROUPI records
   $ll = 0;
   foreach $oneline (@kgrpi_data) {
      $ll += 1;
      next if $ll < 5;
      chop $oneline;
      $oneline .= " " x 400;
      $igrpclass = substr($oneline,0,4);
      $igrpclass =~ s/\s+$//;   #trim trailing whitespace
      $iid  = substr($oneline,9,32);
      $iid =~ s/\s+$//;   #trim trailing whitespace
      $iobjclass = substr($oneline,42,4);
      $iobjclass =~ s/\s+$//;   #trim trailing whitespace
      $iobjname = substr($oneline,51,32);
      $iobjname =~ s/\s+$//;   #trim trailing whitespace
      new_tgroupi($igrpclass,$iid,$iobjclass,$iobjname);
   }

   open(KEVSR, "< $opt_txt_evntserver") || die("Could not open EVNTSERVER $opt_txt_evntserver\n");
   @kevsr_data = <KEVSR>;
   close(KEVSR);

   # Get data for all EVNTSERVER records
   $ll = 0;
   foreach $oneline (@kevsr_data) {
      $ll += 1;
      next if $ll < 5;
      chop $oneline;
      $oneline .= " " x 400;
      $iid = substr($oneline,0,3);
      $iid =~ s/\s+$//;   #trim trailing whitespace
      $ilstdate = substr($oneline,3,16);
      $ilstdate =~ s/\s+$//;   #trim trailing whitespace
      $ilstusrprf = substr($oneline,20,10);
      $ilstusrprf =~ s/\s+$//;   #trim trailing whitespace
      new_evntserver($iid,$ilstdate,$ilstusrprf);
   }

}

# There may be a better way to do this, but this was clear and worked.
# The input $lcount must be matched up to the number of columns
# SELECTED in the SQL.
# [1]  OGRP_59B815CE8A3F4403  OGRP_6F783DF5FF904988  2010  2010
sub parse_lst {
  my ($lcount,$inline) = @_;            # count of desired chunks and the input line
  my @retlist = ();                     # an array of strings to return
  my $chunk;                            # One chunk
  my $oct = 0;                          # output chunk count
  my $rest;                             # the rest of the line to process
  chop($inline);
  $inline =~ /\]\s*(.*)/;               # skip by [NNN]  field
  $rest = " " . $1 . "        ";
  my $restpos = 0;                      # postion studied in the $rest string

  # at each stage we can identify a field with values
  #         <blank>data<blank>
  # and a blank field
  #         <blank><blank>
  # for the last field, we allow imbedded blanks and logic not needed
  while ($oct < $lcount) {         # stop when output chunk met
     $oct += 1;
     if ($oct < $lcount) {
        if (substr($rest,$restpos,2) eq "  ") {               # null string case
           $chunk = "";
           $restpos += 2;
        } else {
           my $nextpos = index($rest," ",$restpos+1);
           $chunk = substr($rest,$restpos+1,$nextpos-$restpos -1);
           $restpos = $nextpos + 1;
        }
     } else {
        $chunk = substr($rest,$restpos+1);
        $chunk =~ s/\s+$//;                    # strip trailing blanks
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
   my $ireserved;
   my $ithrunode;
   my $iaffinities;

   my @ksit_data;
   my $isitname;
   my $iautostart;
   my $ipdt;

   my @knam_data;
   my $iid;
   my $ifullname;

   my @kevsr_data;
   my $ilstdate;
   my $ilstusrprf;

   # Parsing the KfwSQLClient output has some challenges. For example
   #      [1]  OGRP_59B815CE8A3F4403  2010  Test Group 1
   # Using the blank delimiter is OK for columns that are never blank or have no embedded blanks.
   # In this case the GRPNAME column is "Test Group 1". To manage this the SQL is arranged so
   # that a column with embedded blanks always placed at the end. The one table TSITDESC which has
   # two such columns can be retrieved with two separate SQLs.
   #

   open(KSAV, "< $opt_lst_tnodesav") || die("Could not open TNODESAV $opt_lst_tnodesav\n");
   @ksav_data = <KSAV>;
   close(KSAV);

   # Get data for all TNODESAV records
   $ll = 0;
   foreach $oneline (@ksav_data) {
      $ll += 1;
      next if $ll < 2;
      ($inode,$iproduct,$iversion,$io4online,$ihostaddr,$ireserved,$ithrunode,$iaffinities) = parse_lst(8,$oneline);
      $inode =~ s/\s+$//;   #trim trailing whitespace
      $iproduct =~ s/\s+$//;   #trim trailing whitespace
      $iversion =~ s/\s+$//;   #trim trailing whitespace
      $io4online =~ s/\s+$//;   #trim trailing whitespace
      $ihostaddr =~ s/\s+$//;   #trim trailing whitespace
      $ireserved =~ s/\s+$//;   #trim trailing whitespace
      $ithrunode =~ s/\s+$//;   #trim trailing whitespace
      $iaffinities =~ s/\s+$//;   #trim trailing whitespace
      new_tnodesav($inode,$iproduct,$iversion,$io4online,$ihostaddr,$ireserved,$ithrunode,$iaffinities);
   }

   open(KLST, "<$opt_lst_tnodelst") || die("Could not open TNODELST $opt_lst_tnodelst\n");
   @klst_data = <KLST>;
   close(KLST);

   # Get data for all TNODELST type V records
   $ll = 0;
   foreach $oneline (@klst_data) {
      $ll += 1;
      next if $ll < 2;
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
      ($inode,$inodetype,$inodelist) = parse_lst(3,$oneline);
      $inodelist =~ s/\s+$//;   #trim trailing whitespace
      $inode =~ s/\s+$//;   #trim trailing whitespace
      if (($inodetype eq "") and ($inodelist eq "*HUB")) {    # *HUB has blank NODETYPE. Set to M for this calculation
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
   open(KSIT, "< $opt_lst_tsitdesc") || die("Could not open TSITDESC $opt_lst_tsitdesc\n");
   @ksit_data = <KSIT>;
   close(KSIT);

   # Get data for all TSITDESC records
   $ll = 0;
   foreach $oneline (@ksav_data) {
      $ll += 1;
      next if $ll < 2;
      ($isitname,$iautostart,$ipdt) = parse_lst(3,$oneline);
      $isitname =~ s/\s+$//;   #trim trailing whitespace
      $iautostart =~ s/\s+$//;   #trim trailing whitespace
      $ipdt = substr($oneline,33,1);
      new_tsitdesc($isitname,$ipdt);
   }

   open(KNAM, "< $opt_lst_tname") || die("Could not open TNAME $opt_lst_tname\n");
   @knam_data = <KNAM>;
   close(KNAM);

   # Get data for all TNAME
   $ll = 0;
   foreach $oneline (@ksav_data) {
      $ll += 1;
      next if $ll < 2;
      chop $oneline;
      ($iid,$ifullname) = parse_lst(2,$oneline);
      new_tname($iid,$ifullname);
   }

   open(KEVSR, "< $opt_lst_evntserver") || die("Could not open EVNTSERVER $opt_lst_evntserver\n");
   @kevsr_data = <KEVSR>;
   close(KEVSR);

   # Get data for all EVNTSERVER records
   $ll = 0;
   foreach $oneline (@kevsr_data) {
      $ll += 1;
      next if $ll < 2;
      chop $oneline;
      ($iid,$ilstdate,$ilstusrprf) = parse_lst(2,$oneline);
      new_evntserver($iid,$ilstdate,$ilstusrprf);
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
      } elsif ( $ARGV[0] eq "-hub") {
         shift(@ARGV);
         $opt_hub = shift(@ARGV);
         die "option -hub with no following hub specification\n" if !defined $opt_hub;
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
      } elsif ( $ARGV[0] eq "-s") {
         shift(@ARGV);
         $opt_s = shift(@ARGV);
         die "option -s with no following output file specification\n" if !defined $opt_s;
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
      } elsif ( $ARGV[0] eq "-s") {
         shift(@ARGV);
         $opt_s = shift(@ARGV);
         die "option -s with no following debuglevel specification\n" if !defined $opt_s;
      } elsif ( $ARGV[0] eq "-subpc") {
         shift(@ARGV);
         $opt_subpc_warn = shift(@ARGV);
         die "option -subpc with no following per cent specification\n" if !defined $opt_subpc_warn;
      } elsif ( $ARGV[0] eq "-vndx") {
         shift(@ARGV);
         $opt_vndx = 1;
      } elsif ( $ARGV[0] eq "-mndx") {
         shift(@ARGV);
         $opt_mndx = 1;
      } elsif ( $ARGV[0] eq "-miss") {
         shift(@ARGV);
         $opt_miss = 1;
      } elsif ( $ARGV[0] eq "-nodist") {
         shift(@ARGV);
         $opt_nodist = shift(@ARGV);
         die "option -nodist with no following name specification\n" if !defined $opt_nodist;
      } else {
         print STDERR "SITAUDIT001E Unrecognized command line option - $ARGV[0]\n";
         exit 1;
      }
   }

   # Following are command line only defaults. All others can be set from the ini file

   if (!defined $opt_ini) {$opt_ini = "datahealth.ini";}         # default control file if not specified
   if ($opt_h) {&GiveHelp;}  # GiveHelp and exit program
   if (!defined $opt_debuglevel) {$opt_debuglevel=90;}         # debug logging level - low number means fewer messages
   if (!defined $opt_debug) {$opt_debug=0;}                    # debug - turn on rare error cases
   if (!defined $opt_nodist) {$opt_nodist="";}                  # don't skip objects

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
            elsif ($words[0] eq "s") {$opt_s = $words[1];}
            elsif ($words[0] eq "workpath") {$opt_workpath = $words[1];}
            elsif ($words[0] eq "subpc") {$opt_subpc_warn = $words[1];}
            elsif ($words[0] eq "peak_rate") {$opt_peak_rate = $words[1];}
            elsif ($words[0] eq "hub") {$opt_hub = $words[1];}
            else {
               print STDERR "SITAUDIT005E ini file $l - unknown control $oneline\n"; # kill process after current phase
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
   if (!defined $opt_o) {$opt_o="datahealth.csv";}             # default report file
   if (!defined $opt_s) {$opt_s="datahealth.txt";}             # default summary line
   if (!defined $opt_workpath) {$opt_workpath="";}             # default is current directory
   if (!defined $opt_txt) {$opt_txt = 0;}                      # default no txt input
   if (!defined $opt_lst) {$opt_lst = 0;}                      # default no lst input
   if (!defined $opt_subpc_warn) {$opt_subpc_warn=90;}         # default warn on 90% of maximum subnode list
   if (!defined $opt_peak_rate) {$opt_peak_rate=32;}           # default warn on 32 virtual hub table updates per second
   if (!defined $opt_vndx) {$opt_vndx=0;}                      # default vndx off
   if (!defined $opt_mndx) {$opt_mndx=0;}                      # default mndx off
   if (!defined $opt_miss) {$opt_miss=0;}                      # default mndx off
   if (!defined $opt_hub)  {$opt_hub = "";}                    # external hub nodeid not supplied

   $opt_workpath =~ s/\\/\//g;                                 # convert to standard perl forward slashes
   if ($opt_workpath ne "") {
      $opt_workpath .= "\/" if substr($opt_workpath,length($opt_workpath)-1,1) ne "\/";
   }
   if (defined $opt_txt) {
      $opt_txt_tnodelst = $opt_workpath . "QA1CNODL.DB.TXT";
      $opt_txt_tnodesav = $opt_workpath . "QA1DNSAV.DB.TXT";
      $opt_txt_tsitdesc = $opt_workpath . "QA1CSITF.DB.TXT";
      $opt_txt_tname    = $opt_workpath . "QA1DNAME.DB.TXT";
      $opt_txt_tobjaccl = $opt_workpath . "QA1DOBJA.DB.TXT";
      $opt_txt_tgroup   = $opt_workpath . "QA1DGRPA.DB.TXT";
      $opt_txt_tgroupi  = $opt_workpath . "QA1DGRPI.DB.TXT";
      $opt_txt_evntserver = $opt_workpath . "QA1DEVSR.DB.TXT";
   }
   if (defined $opt_lst) {
      $opt_lst_tnodesav  = $opt_workpath . "QA1DNSAV.DB.LST";
      $opt_lst_tnodelst  = $opt_workpath . "QA1CNODL.DB.LST";
      $opt_lst_tsitdesc  = $opt_workpath . "QA1CSITF.DB.LST";
      $opt_lst_tname     = $opt_workpath . "QA1DNAME.DB.LST";
      $opt_lst_tobjaccl  = $opt_workpath . "QA1DOBJA.DB.LST";
      $opt_lst_tgroup   = $opt_workpath . "QA1DGRPA.DB.LST";
      $opt_lst_tgroupi  = $opt_workpath . "QA1DGRPI.DB.LST";
      $opt_lst_evntserver = $opt_workpath . "QA1DEVSR.DB.LST";
   }
   $opt_vndx_fn = $opt_workpath . "QA1DNSAV.DB.VNDX";
   $opt_mndx_fn = $opt_workpath . "QA1DNSAV.DB.MNDX";
   $opt_miss_fn = $opt_workpath . "MISSING.SQL";


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
# 0.73000  : Handle duplicate hostaddr with null thrunode better
# 0.75000  : Advisory on invalid nodes and nodelist names
# 0.80000  : Advisory on virtual hub table update agents
#          : Add summary line txt file for caller
#          : Support workpath better
# 0.81000  : Add advisory on TEMA 6.1 level
# 0.82000  : Alert when FTO and agents connect directly to hub TEMS
# 0.83000  : Identify valid agent endings
# 0.84000  : add more known agent MSLs
# 0.85000  : Add TSITDESC and TNAME checking
#          : Handle z/OS no extension agents
#          : Add TNODESAV product to the "might be truncated" messages
#          : make -lst option work
# 0.86000  : Check for TNODELIST NODETYPE=V thrunode missing from TNODESAV
# 0.87000  : Add TOBJACCL, TGROUP. TGROUPI checking first stage
# 0.88000  : Identify TEMA version < Agent version, adjust impacts, add more missing tests, change some impacts
# 0.89000  : record TEMS version number
# 0.90000  : detect case where *HUB is missing from TNODELST NODETYPE=M records
# 0.91000  : Check EVNTSERVR for blank LSTDATE and LSTUSRPRF
# 0.92000  : Check Virtual Hub Table counts against TSITDESC UADVISOR AUTOSTART settings
