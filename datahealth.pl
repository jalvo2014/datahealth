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
#    # remember debug breakpoint
# $DB::single=2;   # remember debug breakpoint

## todos
#  QA1DAPPL     TAPPLPROPS  ??
#  QA1CSPRD     TUSER       ??
#  STSH - multi-row events... 001->998
# The pure event situation of the Extended Oracle Database agent does not fire on the subnode where the subnode ID is longer than or equal to 25 characters.
# https://eclient.lenexa.ibm.com:9445/search/?fetch=source/TechNote/1430630
# Identify cases where TEMA 32 bit *NE TEMA 64 bit level at a system

#use warnings::unused; # debug used to check for unused variables
use strict;
use warnings;

# See short history at end of module

my $gVersion = "1.43000";
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
my $tlstdate;                            # tomorrow date expressed in ITM Stamp
my $top20;

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
sub valid_lstdate;                       # validate the LSTDATE
sub get_epoch;                           # convert from ITM timestamp to epoch seconds
sub sitgroup_get_sits;                   # calculate situations associated with Situation Group

my @grp;
my %grpx = ();
my @grp_sit = ();
my @grp_grp = ();
my @grp_name = ();
my %sum_sits;
my $gx;
my $grpi = -1;

my %ipx;

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
my @nlistv_lstdate = ();                # last update date

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
my @mlist_ct = ();
my @mlist_nodelist = ();
my @mlist_node = ();
my @mlist_lstdate = ();

my $nlx;
my $nlisti = -1;
my @nlist = ();
my %nlistx = ();
my @nlist_agents = ();


# TNODESAV record data                  Disk copy of INODESTS [mostly]
my $nsx;
my $nsavei = -1;
my @nsave = ();
my %nsavex = ();
my @nsave_product = ();
my @nsave_version = ();
my @nsave_subversion = ();
my @nsave_hostaddr = ();
my @nsave_hostinfo = ();
my @nsave_sysmsl = ();
my @nsave_ct = ();
my @nsave_o4online = ();
my @nsave_affinities = ();
my @nsave_temaver = ();
my @nsave_common = ();

my $nsave_online = 0;
my $nsave_offline = 0;

# TNODESAV HOSTADDR duplications
my $hsx;
my $hsavei = -1;
my @hsave = ();
my %hsavex = ();
my @hsave_sav = ();
my @hsave_ndx = ();
my @hsave_ct = ();
my @hsave_thrundx = ();

my %sysnamex = ();

# TOBJACCL data
my %tobjaccl = ();
my $obji = -1;
my @obj = ();
my %objx = ();
my @obj_objclass = ();
my @obj_objname = ();
my @obj_nodel = ();
my @obj_ct = ();
my @obj_lstdate = ();


my $tx;                                  # TEMS information
my $temsi = -1;                          # count of TEMS
my @tems = ();                           # Array of TEMS names
my %temsx = ();                          # Hash to TEMS index
my @tems_hub = ();                       # When 1, is the hub TEMS
my @tems_ct = ();                        # Count of managed systems
my @tems_ctnok = ();                     # Count of managed systems excluding OK at FTO hub TEMS
my @tems_version = ();                   # TEMS version number
my @tems_arch = ();                      # TEMS architecture
my @tems_thrunode = ();                  # TEMS THRUNODE, when NODE=THRUNODE that is a hub TEMS
my @tems_affinities = ();                # TEMS AFFINITIES
my @tems_sampload = ();                  # Sampled Situaton dataserver load
my @tems_sampsit = ();                   # Sampled Situation Count
my @tems_puresit = ();                   # Pure Situation Count
my @tems_sits = ();                      # Situations hash
my $hub_tems = "";                       # hub TEMS nodeid
my $hub_tems_version = "";               # hub TEMS version
my $hub_tems_no_tnodesav = 0;            # hub TEMS nodeid missing from TNODESAV
my $hub_tems_ct = 0;                     # total agents managed by a hub TEMS

my %tepsx;
my $tepsi = -1;
my @teps = ();
my @teps_version = ();
my @teps_arch = ();

my %ka4x;
my $ka4i = -1;
my @ka4 = ();
my @ka4_product = ();
my @ka4_version = ();
my @ka4_version_count = ();

my $mx;                                  # index
my $magenti = -1;                        # count of managing agents
my @magent = ();                         # name of managing agent
my %magentx = ();                        # hash from managing agent name to index
my @magent_subct = ();                   # count of subnode agents
my @magent_sublen = ();                  # length of subnode agent list
my @magent_tems_version = ();            # version of managing agent TEMS
my @magent_tems = ();                    # TEMS name where managing agent reports

my %pcx;                                 # Product Summary hash

# allow user to set impact
my %advcx = (
              "DATAHEALTH1001E" => "100",
              "DATAHEALTH1002E" => "90",
              "DATAHEALTH1003I" => "0",
              "DATAHEALTH1004I" => "0",
              "DATAHEALTH1005W" => "75",
              "DATAHEALTH1006W" => "75",
              "DATAHEALTH1007E" => "105",
              "DATAHEALTH1008E" => "105",
              "DATAHEALTH1009E" => "105",
              "DATAHEALTH1010W" => "80",
              "DATAHEALTH1011E" => "105",
              "DATAHEALTH1012E" => "105",
              "DATAHEALTH1013W" => "10",
              "DATAHEALTH1014W" => "10",
              "DATAHEALTH1015W" => "9",
              "DATAHEALTH1016E" => "50",
              "DATAHEALTH1017E" => "50",
              "DATAHEALTH1018W" => "90",
              "DATAHEALTH1019W" => "10",
              "DATAHEALTH1020W" => "80",
              "DATAHEALTH1021E" => "105",
              "DATAHEALTH1022E" => "105",
              "DATAHEALTH1023W" => "00",
              "DATAHEALTH1024E" => "90",
              "DATAHEALTH1025E" => "0",
              "DATAHEALTH1026E" => "50",
              "DATAHEALTH1027E" => "50",
              "DATAHEALTH1028E" => "105",
              "DATAHEALTH1029W" => "0",
              "DATAHEALTH1030W" => "0",
              "DATAHEALTH1031E" => "50",
              "DATAHEALTH1032E" => "50",
              "DATAHEALTH1033E" => "50",
              "DATAHEALTH1034W" => "10",
              "DATAHEALTH1035W" => "0",
              "DATAHEALTH1036E" => "25",
              "DATAHEALTH1037W" => "25",
              "DATAHEALTH1038E" => "105",
              "DATAHEALTH1039E" => "100",
              "DATAHEALTH1040E" => "100",
              "DATAHEALTH1041W" => "10",
              "DATAHEALTH1042E" => "90",
              "DATAHEALTH1043E" => "100",
              "DATAHEALTH1044E" => "100",
              "DATAHEALTH1045E" => "100",
              "DATAHEALTH1046W" => "90",
              "DATAHEALTH1047E" => "20",
              "DATAHEALTH1048E" => "110",
              "DATAHEALTH1049W" => "25",
              "DATAHEALTH1050W" => "25",
              "DATAHEALTH1051W" => "25",
              "DATAHEALTH1052W" => "25",
              "DATAHEALTH1053E" => "20",
              "DATAHEALTH1054E" => "105",
              "DATAHEALTH1055E" => "10",
              "DATAHEALTH1056E" => "100",
              "DATAHEALTH1057E" => "100",
              "DATAHEALTH1058E" => "105",
              "DATAHEALTH1059E" => "105",
              "DATAHEALTH1060E" => "20",
              "DATAHEALTH1061E" => "75",
              "DATAHEALTH1062E" => "75",
              "DATAHEALTH1063W" => "10",
              "DATAHEALTH1064W" => "50",
              "DATAHEALTH1065W" => "10",
              "DATAHEALTH1066W" => "10",
              "DATAHEALTH1067E" => "110",
              "DATAHEALTH1068E" => "90",
              "DATAHEALTH1069E" => "100",
              "DATAHEALTH1070W" => "50",
              "DATAHEALTH1071W" => "20",
              "DATAHEALTH1072W" => "20",
              "DATAHEALTH1073W" => "25",
              "DATAHEALTH1074W" => "90",
              "DATAHEALTH1075W" => "60",
              "DATAHEALTH1076W" => "50",
              "DATAHEALTH1077E" => "100",
              "DATAHEALTH1078E" => "100",
              "DATAHEALTH1079E" => "50",
              "DATAHEALTH1080W" => "95",
              "DATAHEALTH1081W" => "75",
              "DATAHEALTH1082W" => "55",
              "DATAHEALTH1083W" => "75",
              "DATAHEALTH1084W" => "55",
              "DATAHEALTH1085W" => "95",
              "DATAHEALTH1086W" => "90",
              "DATAHEALTH1087E" => "100",
              "DATAHEALTH1088W" => "100",
              "DATAHEALTH1089E" => "100",
              "DATAHEALTH1090W" => "80",
              "DATAHEALTH1091W" => "95",
              "DATAHEALTH1092W" => "85",
              "DATAHEALTH1093W" => "75",
              "DATAHEALTH1094W" => "95",
              "DATAHEALTH1095W" => "100",
              "DATAHEALTH1096W" => "60",
              "DATAHEALTH1097W" => "50",
              "DATAHEALTH1098E" => "100",
              "DATAHEALTH1099W" => "25",
              "DATAHEALTH1100W" => "25",
              "DATAHEALTH1101E" => "95",
              "DATAHEALTH1102W" => "10",
            );

my %advtextx = ();
my $advkey = "";
my $advtext = "";
my $advline;
my %advgotx = ();

my $advi = -1;
my @advonline = ();
my @advsit = ();
my @advimpact = ();
my @advcode = ();
my %advx = ();
my $hubi;
my $max_impact = 0;
my $isFTO = 0;
my %FTOver = ();

my $test_node;
my $invalid_node;
my $invalid_affinities;


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

# Following is a hard calculated collection  of how many TEMA apars are at each maintenance level.
#
# The goal is to identify how far behind a particular customer site is compare with latest maintenance levels.

# date: Date maintenance level published
# days: Number of days since 1 Jan 1900
# apars: array of TEMA APAR fixes included

my %mhash= (
            '06.30.07' => {date=>'01/07/2017',days=>42742,apars=>['IV78703','IV81217'],},
            '06.30.06' => {date=>'12/10/2016',days=>42346,apars=>['IV66841','IV69144','IV70115','IV73766','IV76109','IV79364'],},
            '06.30.05' => {date=>'06/30/2015',days=>42183,apars=>['IV64897','IV65775','IV67576','IV69027'],},
            '06.30.04' => {date=>'12/12/2014',days=>41983,apars=>['IV44811','IV53859','IV54581','IV56194','IV56578','IV62139','IV62138','IV60851'],},
            '06.30.03' => {date=>'08/07/2014',days=>41856,apars=>['IV62667'],},
            '06.30.02' => {date=>'09/13/2013',days=>41528,apars=>['IV39406','IV47538','IV47540','IV47585','IV47590','IV47591','IV47592'],},
            '06.30.01' => {date=>'05/16/2013',days=>41408,apars=>['IV39778','IV39779'],},
            '06.30.00' => {date=>'03/08/2013',days=>41339,apars=>[],},
            '06.23.05' => {date=>'04/30/2014',days=>41757,apars=>['IV43114','IV46993','IV47201','IV47775','IV31825','IV52643'],},
            '06.23.04' => {date=>'10/21/2013',days=>41566,apars=>['IV43489','IV43787','IV44858','IV40015'],},
            '06.23.03' => {date=>'04/26/2013',days=>41388,apars=>['IV21954','IV24409','IV27955','IV32358'],},
            '06.23.02' => {date=>'10/11/2012',days=>41191,apars=>['IV16083','IV22060','IV23043','IV23784'],},
            '06.23.01' => {date=>'03/09/2012',days=>40975,apars=>['IV16476','IV16531','IV16532','IV10402','IV08621'],},
            '06.23.00' => {date=>'08/18/2011',days=>40771,apars=>[],},
            '06.22.09' => {date=>'06/29/2012',days=>41087,apars=>['IV10164','IV12849','IV00362'],},
            '06.22.08' => {date=>'03/30/2012',days=>40996,apars=>['IV07041','IV08621','IV09296','IV10402','IV18016'],},
            '06.22.07' => {date=>'12/15/2011',days=>40890,apars=>['IV03676','IV03943','IV04585','IV04683','IV06261','IZ96898'],},
            '06.22.06' => {date=>'09/30/2011',days=>40844,apars=>['IV00146','IV00655','IV00722','IV01532','IV03216','IZ98187','IV06896'],},
            '06.22.05' => {date=>'07/08/2011',days=>40730,apars=>['IZ84879','IZ89970','IZ95923','IZ96148','IZ97197','IV01708','IZ87796'],},
            '06.22.04' => {date=>'04/07/2011',days=>40638,apars=>['IZ81476','IZ85796','IZ89282','IZ93258','IZ84397'],},
            '06.22.03' => {date=>'09/28/2010',days=>40447,apars=>['IZ76410'],},
            '06.22.02' => {date=>'05/21/2010',days=>40317,apars=>['IZ45531','IZ75244'],},
            '06.22.01' => {date=>'11/20/2009',days=>40135,apars=>[],},
            '06.22.00' => {date=>'09/10/2009',days=>40062,apars=>[],},
            '06.21.04' => {date=>'12/17/2010',days=>40547,apars=>['IZ77554','IZ77981','IZ80179'],},
            '06.21.03' => {date=>'07/21/2010',days=>40378,apars=>['IZ70928','IZ73109','IZ73633','IZ76984'],},
            '06.21.02' => {date=>'04/16/2010',days=>40282,apars=>['IZ54269','IZ54895','IZ56686','IZ63949','IZ65337'],},
            '06.21.01' => {date=>'12/10/2009',days=>40155,apars=>['IZ60115'],},
            '06.21.00' => {date=>'11/10/2008',days=>39768,apars=>[],},
            '06.20.03' => {date=>'05/15/2009',days=>39946,apars=>['IZ41189','IZ42154','IZ42185'],},
            '06.20.02' => {date=>'10/30/2008',days=>39749,apars=>['IZ24933'],},
            '06.20.01' => {date=>'05/16/2008',days=>39582,apars=>['IZ60115'],},
            '06.20.00' => {date=>'12/14/2007',days=>39428,apars=>[],},
            '06.10.07' => {date=>'05/20/2008',days=>39586,apars=>['IY93399','IZ00591','IZ02165','IZ16659'],},
            '06.10.06' => {date=>'11/02/2007',days=>39386,apars=>['IZ02246','IY87701','IY96423','IY95964','IY98649','IY99106','IZ07221','IZ07224'],},
            '06.10.05' => {date=>'05/11/2007',days=>39211,apars=>['IY88519','IY92830','IY95114','IY95363','IY97983','IY97984','IY97993'],},
            '06.10.04' => {date=>'12/14/2006',days=>39063,apars=>['IY89899','IY90352'],},
            '06.10.03' => {date=>'08/18/2006',days=>38945,apars=>['IY90352','IY91296'],},
            '06.10.02' => {date=>'06/30/2006',days=>38896,apars=>['IY81984','IY84853','IY85392'],},
            '06.10.01' => {date=>'03/31/2006',days=>38805,apars=>['IY82424','IY82431','IY82785'],},
            '06.10.00' => {date=>'10/25/2005',days=>38648,apars=>[],},
        );

my %levelx = ();
my %klevelx = ( '06.30' => 1,
                '06.23' => 1,
                '06.22' => 1,
                '06.21' => 1,
                '06.20' => 1,
                '06.10' => 1,
              );

my %eoslevelx = ( '06.22' => {date=>'04/28/2018',count=>0,future=>1},
                  '06.21' => {date=>'09/30/2015',count=>0,future=>0},
                  '06.20' => {date=>'09/30/2015',count=>0,future=>0},
                  '06.10' => {date=>'04/30/2012',count=>0,future=>0},
                );

my $tema_total_count = 0;
my $tema_total_good_count = 0;
my $tema_total_post_count = 0;
my $tema_total_deficit_count = 0;
my $tema_total_deficit_percent = 0;
my $tema_total_apars = 0;
my $tema_total_days = 0;
my $tema_total_max_days = 0;
my $tema_total_max_apars = 0;
my $tema_total_eos = 0;


my $tems_packages = 0;
my $tems_packages_nominal = 500;




# Situation Group related data
my %group = ();                            # situation group base data, hash of hashes
my %groupi = ();                           # situation group item data, hash of hashes
my %groupx = ();


# Situation related data

my $sit_bad_time = 4*24*60*60;             # dangerous sampling interval

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
my @sit_lstdate = ();

my $sit_autostart_total = 0;
my $sit_tems_alert = 0;
my $sit_tems_alert_run = 0;
my $sit_tems_alert_dist = 0;

my $nax;
my $nami = -1;                             # count of fullname indexes
my @nam = ();                              # array of index
my %namx = ();                             # Index from index name to index
my @nam_fullname = ();                     # array of fullnames
my @nam_ct = ();                           # count of tname references
my @nam_lstdate = ();                      # last update times

my $evti = -1;                             # event destination data
my @evt = ();
my @evt_lstdate = ();
my @evt_lstusrprf = ();

my $ccti = -1;
my @cct = ();
my @cct_lstdate = ();
my @cct_name = ();

my $evmapi = -1;
my @evmap = ();
my @evmap_lstdate = ();
my @evmap_map  = ();

my %pcyx = ();

my $cali = -1;
my @cal = ();
my %calx = ();
my @cal_count = ();
my @cal_lstdate = ();
my @cal_name = ();

my $tcai = -1;
my @tca = ();
my %tcax = ();
my @tca_count = ();
my @tca_lstdate = ();
my @tca_sitname = ();

my $tcii = -1;
my @tci = ();
my %tcix = ();
my @tci_count = ();
my @tci_lstdate = ();
my @tci_id = ();
my @tci_calid = ();

my %eibnodex = ();

my $hdonline = 0;
my $uadhist = 0;

my %eventx = ();
my $eventx_start = -1;
my $eventx_last = -1;
my $eventx_dur;

my %epochx;

while (<main::DATA>)
{
  $advline = $_;
  if ($advkey eq "") {
     chomp $advline;
     $advkey = $advline;
     next;
  }
  if (length($advline) >= 15) {
     if (substr($advline,0,10) eq "DATAHEALTH") {
        $advtextx{$advkey} = $advtext;
        chomp $advline;
        $advkey = $advline;
        $advtext = "";
        next;
     }
  }
  $advtext .= $advline;
}
$advtextx{$advkey} = $advtext;

# option and ini file variables variables

my $opt_txt;                    # input from .txt files
my $opt_txt_tnodelst;           # TNODELST txt file
my $opt_txt_tnodesav;           # TNODESAV txt file
my $opt_txt_tsitdesc;           # TSITDESC txt file
my $opt_txt_tname;              # TNAME txt file
my $opt_txt_tobjaccl;           # TOBJACCL txt file
my $opt_txt_tgroup;             # TGROUP txt file
my $opt_txt_tgroupi;            # TGROUPI txt file
my $opt_txt_evntserver;         # EVNTSERVER txt file
my $opt_txt_package;            # PACKAGE txt file
my $opt_txt_cct;                # CCT txt file
my $opt_txt_evntmap;            # EVNTMAP txt file
my $opt_txt_tpcydesc;           # TPCYDESC txt file
my $opt_txt_tactypcy;           # TACTYPCY txt file
my $opt_txt_tcalendar;          # TCALENDAR txt file
my $opt_txt_toverride;          # TOVERRIDE txt file
my $opt_txt_toveritem;          # TOVERITEM txt file
my $opt_txt_teiblogt;           # TEIBLOGT txt file
my $opt_txt_tsitstsh;           # TSITSTSH txt file
my $opt_txt_tcheckpt;           # TCHECKPT txt file
my $opt_lst;                    # input from .lst files
my $opt_lst_tnodesav;           # TNODESAV lst file
my $opt_lst_tnodelst;           # TNODELST lst file
my $opt_lst_tsitdesc;           # TSITDESC lst file
my $opt_lst_tname;              # TNAME lst file
my $opt_lst_tobjaccl;           # TOBJACCL lst file
my $opt_lst_tgroup;             # TGROUP lst file
my $opt_lst_tgroupi;            # TGROUPI lst file
my $opt_lst_evntserver;         # EVNTSERVER lst file
my $opt_lst_cct;                # CCT lst file
my $opt_lst_evntmap;            # EVNTMAP lst file
my $opt_lst_tpcydesc;           # TPCYDESC lst file
my $opt_lst_tactypcy;           # TACTYPCY lst file
my $opt_lst_tcalendar;          # TCALENDAR lst file
my $opt_lst_toverride;          # TOVERRIDE lst file
my $opt_lst_toveritem;          # TOVERITEM lst file
my $opt_lst_teiblogt;           # TEIBLOGT lst file
my $opt_lst_tsitstsh;           # TSITSTSH lst file
my $opt_lst_tcheckpt;           # TCHECKPT txt file
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
my $opt_event;                  # When 1, create event reports
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
my $opt_nodist;                 # TGROUP names which are planned as non-distributed
my $opt_fto = "";               # HUB or MIRROR

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

my $tema_maxlevel = "";
foreach my $f (sort { $b cmp $a } keys %mhash) {
   $tema_maxlevel = $f;
   last;
}

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
   $advimpact[$advi] = $advcx{$advcode[$advi]};
   $advsit[$advi] = $hub_tems;
}

if ($nlistvi == -1) {
   $advi++;$advonline[$advi] = "No TNODELST NODETYPE=V records";
   $advcode[$advi] = "DATAHEALTH1012E";
   $advimpact[$advi] = $advcx{$advcode[$advi]};
   $advsit[$advi] = $hub_tems;
   $hub_tems_no_tnodesav = 1;
}

# following produces a report of how many agents connect to a TEMS.

$hub_tems = $opt_hub if $hub_tems eq "";
if ($hub_tems_no_tnodesav == 0) {
   # following is a rare case where the TNODELST *HUB entry is missing.
   # for analysis work, that can be supplied by a -hub <nodeid> parameter
   if ($hub_tems eq "") {
      $advi++;$advonline[$advi] = "*HUB node missing from TNODELST Type M records";
      $advcode[$advi] = "DATAHEALTH1038E";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
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
         # Calculate TEMA APAR Deficit numbers
         my $agtlevel = substr($nsave_temaver[$nx],0,8);
         next if $agtlevel eq "";
         my $temslevel = $tems_version[$tx];

         if (($agtlevel ne "") and ($temslevel ne "")) {
            $tema_total_count += 1;
            if (substr($temslevel,0,5) lt substr($agtlevel,0,5)) {
               $advi++;$advonline[$advi] = "Agent with TEMA at [$agtlevel] later than TEMS $tems1 at [$temslevel]";
               $advcode[$advi] = "DATAHEALTH1043E";
               $advimpact[$advi] = $advcx{$advcode[$advi]};
               $advsit[$advi] = $node1;
            }
            my $aref = $mhash{$agtlevel};
            if (!defined $aref) {
               if ($nsave_product[$nx] eq "A4") {
                  next if $agtlevel eq "06.20.20";
               }
               $advi++;$advonline[$advi] = "Agent with unknown TEMA level [$agtlevel]";
               $advcode[$advi] = "DATAHEALTH1044E";
               $advimpact[$advi] = $advcx{$advcode[$advi]};
               $advsit[$advi] = $node1;
               next;
            }
            my $tref = $mhash{$temslevel};
            if (!defined $tref) {
               $advi++;$advonline[$advi] = "TEMS with unknown version [$temslevel]";
               $advcode[$advi] = "DATAHEALTH1045E";
               $advimpact[$advi] = $advcx{$advcode[$advi]};
               $advsit[$advi] = $tems1;
               next;
            }
            if ($temslevel eq $agtlevel) {
               $tema_total_good_count += 1;
            } elsif ($temslevel gt $agtlevel) {
               $tema_total_deficit_count += 1;
            } else {
               $tema_total_post_count += 1;
            }
            my $tlevelref = $eoslevelx{substr($agtlevel,0,5)};
            if (defined $tlevelref) {
               $tlevelref->{count} += 1;
               $tema_total_eos += 1;
            }
            my $key = $temslevel . "|" . $agtlevel;
            my $level_ref = $levelx{$key};
            if (!defined $level_ref) {
               my %aparref = ();
               my %levelref = (
                                 days => 0,
                                 apars => 0,
                                 aparh => \%aparref,
                              );
               $levelx{$key} = \%levelref;
               $level_ref    = \%levelref;
               foreach my $f (sort { $a cmp $b } keys %mhash) {
                  next if $f le $agtlevel;
                  last if $f gt $temslevel;
                  foreach my $h ( @{$mhash{$f}->{apars}}) {
                       next if defined $level_ref->{aparh}{$h};
                       $level_ref->{aparh}{$h} = 1;
                       $level_ref->{apars} += 1;
                       $level_ref->{days}  += $mhash{$temslevel}->{days} - $mhash{$agtlevel}->{days};
                  }
               }
            }
            $tema_total_days += $level_ref->{days};
            $tema_total_apars += $level_ref->{apars};
         }
#        print "working on $node1 $agtlevel\n";
         $temslevel = $tema_maxlevel;
         $key = $temslevel . "|" . $agtlevel;
         my $level_ref = $levelx{$key};
         if (!defined $level_ref) {
            my %aparref = ();
            my %levelref = (
                              days => 0,
                              apars => 0,
                              aparh => \%aparref,
                           );
            $levelx{$key} = \%levelref;
            $level_ref    = \%levelref;
            foreach my $f (sort { $a cmp $b } keys %mhash) {
               next if $f le $agtlevel;
               last if $f gt $temslevel;
               foreach my $h ( @{$mhash{$f}->{apars}}) {
                    next if defined $level_ref->{aparh}{$h};
                    $level_ref->{aparh}{$h} = 1;
                    $level_ref->{apars} += 1;
                    $level_ref->{days}  += $mhash{$temslevel}->{days} - $mhash{$agtlevel}->{days};
               }
            }
         }
         $tema_total_max_days +=  $level_ref->{days};
         $tema_total_max_apars += $level_ref->{apars};
#        print "adding $level_ref->{apars} for $node1 $agtlevel\n";
      }
   }
}

# calculate Agent Summary Report Section
my $npc_ct = 0;
for ($i=0; $i<=$nsavei; $i++) {
   my $node1 = $nsave[$i];
   my $npc = $nsave_product[$i];
   next if $npc eq "";
   my $nversion = $nsave_version[$i];
   $nversion .= "." . $nsave_subversion[$i] if $nsave_subversion[$i] ne "";
   my $ntema = $nsave_temaver[$i];
   my $ninfo = $nsave_hostinfo[$i];
   $npc_ct += 1;
   my $pc_ref = $pcx{$npc};
   if (!defined $pc_ref) {
      my %pcref = (
                      count => 0,
                      versions => {},
                      temas => {},
                      info => {},
                  );
      $pc_ref = \%pcref;
      $pcx{$npc} = \%pcref;
   }
   $pc_ref->{count} += 1;

   # Calculate Agent versions
   if ($nversion ne "") {
      my $version_ref = $pc_ref->{versions}{$nversion};
      if (!defined $version_ref) {
         my %versionref = (
                             count => 0,
                          );
        $version_ref = \%versionref;
        $pc_ref->{versions}{$nversion} = \%versionref;
      }
      $pc_ref->{versions}{$nversion}->{count} += 1;
   }

   # Calculate Agent TEMA versions
   if ($ntema ne "") {
      my $tema_ref = $pc_ref->{temas}{$ntema};
      if (!defined $tema_ref) {
         my %temaref = (
                          count => 0,
                       );
        $tema_ref = \%temaref;
        $pc_ref->{temas}{$ntema} = \%temaref;
      }
      $pc_ref->{temas}{$ntema}->{count} += 1;
   }

   # Calculate Agent HOSTINFO versions
   if ($ninfo ne "") {
      my $info_ref = $pc_ref->{info}{$ninfo};
      if (!defined $info_ref) {
         my %inforef = (
                          count => 0,
                       );
        $info_ref = \%inforef;
        $pc_ref->{info}{$ninfo} = \%inforef;
      }
      $pc_ref->{info}{$ninfo}->{count} += 1;
   }
}

for (my $i=0;$i<=$temsi;$i++) {
   if ($tems_thrunode[$i] eq $tems[$i]) {
      # The following test is how a hub TEMS is distinguished from a remote TEMS
      # This checks an affinity capability flag which indicates the policy microscope
      # is available. I tried many ways and failed before finding this.
      if (substr($tems_affinities[$i],40,1) eq "O") {
         $isFTO += 1;
         $FTOver{$tems[$i]} = $tems_version[$i];
      }
   }
}

my $FTO_diff = 0;
if ($isFTO >= 2) {
   my %reverse;
   my $pftover = "";
   while (my ($key, $value) = each %FTOver) {
      push @{$reverse{$value}}, $key;
      $pftover .= $key . "=" . $value . ";";
   }
   if (scalar (keys %reverse) > 1) {
      $advi++;$advonline[$advi] = "FTO hub TEMS have different version levels [$pftover]";
      $advcode[$advi] = "DATAHEALTH1069E";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = "FTO";
   }
   my $pFTO_ct = scalar (keys %FTOver);
   if ($pFTO_ct > 2) {
      $advi++;$advonline[$advi] = "There are $pFTO_ct hub TEMS [$pftover]";
      $advcode[$advi] = "DATAHEALTH1070W";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = "FTO";
   }
}


if ($tems_packages > $tems_packages_nominal) {
   $advi++;$advonline[$advi] = "Total TEMS Packages [.cat files] count [$tems_packages] exceeds nominal [$tems_packages_nominal]";
   $advcode[$advi] = "DATAHEALTH1046W";
   $advimpact[$advi] = $advcx{$advcode[$advi]};
   $advsit[$advi] = "Package.cat";
}

if ($tems_packages > 510) {
   $advi++;$advonline[$advi] = "Total TEMS Packages [.cat files] count [$tems_packages] close to TEMS failure point of 513";
   $advcode[$advi] = "DATAHEALTH1048E";
   $advimpact[$advi] = $advcx{$advcode[$advi]};
   $advsit[$advi] = "Package.cat";
}

for ($i=0; $i<=$nsavei; $i++) {
   my $node1 = $nsave[$i];
   next if $nsave_product[$i] eq "EM";
   if (index($node1,"::CONFIG") !=  -1) {
      $nsx = $nlistvx{$node1};
      if (defined $nsx) {
         my $thrunode1 = $nlistv_thrunode[$nsx];
         if (defined $thrunode1) {
            my $tx = $temsx{$thrunode1};
            if (defined $tx) {
               if ($thrunode1 ne $hub_tems) {
                  $advi++;$advonline[$advi] = "CF Agent connected to $thrunode1 which is not the hub TEMS";
                  $advcode[$advi] = "DATAHEALTH1076W";
                  $advimpact[$advi] = $advcx{$advcode[$advi]};
                  $advsit[$advi] = $node1;
               } else {
                  if ($isFTO >= 2) {
                     $advi++;$advonline[$advi] = "CF Agent not supported in FTO mode";
                     $advcode[$advi] = "DATAHEALTH1077E";
                     $advimpact[$advi] = $advcx{$advcode[$advi]};
                     $advsit[$advi] = $node1;
                 }
               }
            }
         }
      }
   }

   next if $nsave_product[$i] eq "CF";      # TEMS Configuration Managed System does not have TEMA - skip most tests
   if ($nsave_product[$i] eq "HD") {        # WPA should only connect to hub TEMS
      $hdonline += 1;
      $nsx = $nlistvx{$node1};
      if (defined $nsx) {
         my $thrunode1 = $nlistv_thrunode[$nsx];
         if (defined $thrunode1) {
            my $tx = $temsx{$thrunode1};
            if (defined $tx) {
               if ($thrunode1 ne $hub_tems) {
                  $advi++;$advonline[$advi] = "WPA connected to $thrunode1 which is not the hub TEMS";
                  $advcode[$advi] = "DATAHEALTH1078E";
                  $advimpact[$advi] = $advcx{$advcode[$advi]};
                  $advsit[$advi] = $node1;
               }
            }
         }
      }
   }
   if (index($node1,"::MQ") !=  -1) {
      $advi++;$advonline[$advi] = "MQ Agent name has missing hostname qualifier";
      $advcode[$advi] = "DATAHEALTH1073W";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = $node1;
   }
   $nsx = $nlistvx{$node1};
   next if defined $nsx;
   if (index($node1,":") !=  -1) {
      $advi++;$advonline[$advi] = "Node present in node status but missing in TNODELST Type V records";
      $advcode[$advi] = "DATAHEALTH1001E";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
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
         $advimpact[$advi] = $advcx{$advcode[$advi]};
         $advsit[$advi] = $node1;
      } else {
         next if length($node1) < 31;
         $advi++;$advonline[$advi] = "Subnode Name at 31/32 characters and might be truncated - product[$product1]";
         $advcode[$advi] = "DATAHEALTH1014W";
         $advimpact[$advi] = $advcx{$advcode[$advi]};
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
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = $onemagent;
   }
}

for ($i=0; $i<=$evti;$i++) {
   valid_lstdate("EVNSERVER",$evt_lstdate[$i],$evt[$i],"ID=$evt[$i]");
   my $oneid = $evt[$i];
}

for ($i=0; $i<=$evmapi;$i++) {
   valid_lstdate("EVNTMAP",$evmap_lstdate[$i],$evmap[$i],"ID=$evmap[$i]");
   my $onemap = $evmap_map[$i];
   #<situation name="kph_actvmem_xuxc_epf" mapAllAttributes="Y" ><class name="ITM_Unix_Memory" /></situation>
   $onemap =~ /\"(\S+)\"/;
   my $onesit = $1;
   if (!defined $onemap){
      $advi++;$advonline[$advi] = "EVNTMAP Situation reference missing";
      $advcode[$advi] = "DATAHEALTH1053E";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = $evmap[$i];
   } else {
      $onesit =~ s/\s+$//;   #trim trailing whitespace
      if (!defined $sitx{$onesit}){
         $advi++;$advonline[$advi] = "EVNTMAP ID[$evmap[$i]] Unknown Situation in mapping - $onesit";
         $advcode[$advi] = "DATAHEALTH1047E";
         $advimpact[$advi] = $advcx{$advcode[$advi]};
         $advsit[$advi] = $evmap[$i];
      }
   }

}

for ($i=0; $i<=$ccti;$i++) {
   valid_lstdate("CCT",$cct_lstdate[$i],$cct[$i],"ID=$cct[$i]");
}

# Following logic cross checks the LSTDATE field. There is a big distinction between FTO mode and not.
# In FTO mode condition cause actual problems while otherwise they are potential problems. That is why
# there are 4 advisories.
#
# LSTDATE blank - causes a failure to FTO synchronize. If not FTO - a potential problem for the future.
# LSTDATE in future - cause breakage to FTO synchronize process. If not FTO - a potential problem for the future.
# LSTDATE in future and ITM 630 FP3 or later, no problem because of TEMS logic change
# LSTDATE in future and before ITM 630 FP3, causes invalid "high water mark" at backup hub TEMS and thus update to be ignored.

sub valid_lstdate {
   my ($itable,$ilstdate,$iname,$icomment) = @_;
   if ($isFTO >= 2){
      if ($ilstdate eq "") {
         $advi++;$advonline[$advi] = "$itable LSTDATE is blank and will not synchronize in FTO configuration";
         $advcode[$advi] = "DATAHEALTH1039E";
         $advimpact[$advi] = $advcx{$advcode[$advi]};
         $advsit[$advi] = $iname;
      } elsif ($ilstdate gt $tlstdate) {
         if (defined $hubi) {
            if ($tems_version[$hubi]  lt "06.30.03") {
               $advi++;$advonline[$advi] = "LSTDATE for [$icomment] value in the future $ilstdate";
               $advcode[$advi] = "DATAHEALTH1040E";
               $advimpact[$advi] = $advcx{$advcode[$advi]};
               $advsit[$advi] = "$itable";
            }
         }
      }
   } else {
      if ($ilstdate eq "") {
         $advi++;$advonline[$advi] = "$itable LSTDATE is blank and will not synchronize in FTO configuration";
         $advcode[$advi] = "DATAHEALTH1063W";
         $advimpact[$advi] = $advcx{$advcode[$advi]};
         $advsit[$advi] = $iname;
      } elsif ($ilstdate gt $tlstdate) {
         if (defined $hubi) {
            if ($tems_version[$hubi]  lt "06.30.03") {
               $advi++;$advonline[$advi] = "LSTDATE for [$icomment] value in the future $ilstdate";
               $advcode[$advi] = "DATAHEALTH1041W";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
     $advimpact[$advi] = $advcx{$advcode[$advi]};
               $advimpact[$advi] = $advcx{$advcode[$advi]};
               $advsit[$advi] = "$itable";
            }
         }
      }
   }
}


for ($i=0; $i<=$cali; $i++) {
   valid_lstdate("TCALENDAR",$cal_lstdate[$i],$cal_name[$i],"NAME=$cal_name[$i]");
   if ($cal_count[$i] > 1) {
      $advi++;$advonline[$advi] = "TCALENDAR duplicate key ID";
      $advcode[$advi] = "DATAHEALTH1058E";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = $cal[$i];
   }
}

for ($i=0; $i<=$tcai; $i++) {
   valid_lstdate("TOVERRIDE",$tca_lstdate[$i],$tca[$i],"ID=$tca[$i]");
   if ($tca_count[$i] > 1) {
      $advi++;$advonline[$advi] = "TOVERRIDE duplicate key ID";
      $advcode[$advi] = "DATAHEALTH1059E";
      $advsit[$advi] = $tca[$i];
   }
   my $onesit = $tca_sitname[$i];
   if (!defined $sitx{$onesit}){
      $advi++;$advonline[$advi] = "TOVERRIDE Unknown Situation [$onesit] in override";
      $advcode[$advi] = "DATAHEALTH1060E";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = $tca[$i];
   }
}

for ($i=0; $i<=$tcii; $i++) {
   if ($tci_calid[$i] ne "") {
      my $onecal = $tci_calid[$i];
      if (!defined $calx{$onecal}){
         $advi++;$advonline[$advi] = "TOVERITEM Unknown Calendar ID $onecal";
         $advcode[$advi] = "DATAHEALTH1061E";
         $advimpact[$advi] = $advcx{$advcode[$advi]};
         $advsit[$advi] = $tci[$i];
      }
      my $oneid = $tci_id[$i];
      if (!defined $tcax{$oneid}){
         $advi++;$advonline[$advi] = "TOVERITEM Unknown TOVERRIDE ID $oneid";
         $advcode[$advi] = "DATAHEALTH1062E";
         $advimpact[$advi] = $advcx{$advcode[$advi]};
         $advsit[$advi] = $tci[$i];
      }
   }
}

for ($i=0; $i<=$nsavei; $i++) {
   next if $nsave_sysmsl[$i] == 1;
   next if $nsave_product[$i] eq "EM";
   next if $nsave_product[$i] eq "CF";      # TEMS Configuration Managed System does not have TEMA - skip most tests
   my $node1 = $nsave[$i];
   $vlx = $nlistvx{$node1};
   if (defined $vlx) {
      next if $nlistv_thrunode[$vlx] ne $nlistv_tems[$vlx];
   }
   if (index($node1,":") !=  -1) {
      $advi++;$advonline[$advi] = "Node without a system generated MSL in TNODELST Type M records";
      $advcode[$advi] = "DATAHEALTH1002E";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = $node1;
      next if $opt_mndx == 0;
      print MDX "$node1\n";
   }
}
for ($i=0; $i<=$nlistmi; $i++) {
   my $node1 = $nlistm[$i];
   my $nnx = $nsavex{$node1};
   next if !defined $nnx;
   next if $nsave_product[$nnx] eq "CF";      # TEMS Configuration Managed System does not have TEMA - skip most tests
   if ($nlistm_miss[$i] != 0) {
      $advi++;$advonline[$advi] = "Node present in TNODELST Type M records but missing in Node Status";
      $advcode[$advi] = "DATAHEALTH1003I";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = $node1;
     if ($opt_miss == 1) {
         my $key = "DATAHEALTH1003I" . " " . $node1;
         $miss{$key} = 1;
      }
   }
   if ($nlistm_nov[$i] != 0) {
      $advi++;$advonline[$advi] = "Node present in TNODELST Type M records but missing TNODELST Type V records";
      $advcode[$advi] = "DATAHEALTH1004I";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = $node1;
  }
}

foreach my $f (keys %group) {
   my $group_detail_ref = $group{$f};
   valid_lstdate("TGROUP",$group_detail_ref->{lstdate},$f,"KEY=$f");
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
            $advimpact[$advi] = $advcx{$advcode[$advi]};
            $advsit[$advi] = $group_detail_ref->{grpname};
         }
      }
   }
}

foreach my $f (sort { $a cmp $b } keys %pcyx) {
   my $pcy_ref = $pcyx{$f};
   valid_lstdate("TPCYDESCR",$pcy_ref->{lstdate},$f,"PCYNAME=$f");
   if ($pcy_ref->{count} > 1) {
      $advi++;$advonline[$advi] = "TPCYDESC duplicate key PCYNAME";
      $advcode[$advi] = "DATAHEALTH1054E";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = $f;
   }
   foreach my $g (sort { $a cmp $b } keys %{$pcy_ref->{sit}}) {
      my $onesit = $g;
      if (!defined $sitx{$onesit}) {
         if ($pcy_ref->{autostart} eq "*YES") {
            $advi++;$advonline[$advi] = "TPCYDESC Wait on SIT or Sit reset - unknown situation $g";
            $advcode[$advi] = "DATAHEALTH1056E";
            $advimpact[$advi] = $advcx{$advcode[$advi]};
            $advsit[$advi] = $f;
         } else {
            $advi++;$advonline[$advi] = "TPCYDESC Wait on SIT or Sit reset - unknown situation $g but policy not autostarted";
            $advcode[$advi] = "DATAHEALTH1065W";
            $advimpact[$advi] = $advcx{$advcode[$advi]};
            $advsit[$advi] = $f;
         }
      }
   }
   foreach my $g (sort { $a cmp $b } keys %{$pcy_ref->{eval}}) {
      my $onesit = $g;
      if (!defined $sitx{$onesit}) {
         if ($pcy_ref->{autostart} eq "*YES") {
            $advi++;$advonline[$advi] = "TPCYDESC Evaluate Sit Now - unknown situation $g";
            $advcode[$advi] = "DATAHEALTH1057E";
            $advimpact[$advi] = $advcx{$advcode[$advi]};
            $advsit[$advi] = $f;
         } else {
            $advi++;$advonline[$advi] = "TPCYDESC Evaluate Sit Now - unknown situation $g but policy not autostarted";
            $advcode[$advi] = "DATAHEALTH1066W";
            $advimpact[$advi] = $advcx{$advcode[$advi]};
            $advsit[$advi] = $f;
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
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = $nsave[$i];
   }

   if (index($nsave[$i]," ") != -1) {
      $advi++;$advonline[$advi] = "TNODESAV node name with embedded blank";
      $advcode[$advi] = "DATAHEALTH1049W";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = $nsave[$i];
   }
   $invalid_affinities = 0;
   # first check on dynamic affinities
   # dynamicAffinityRule = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_. "
   if ((substr($nsave_affinities[$i],0,1) eq "%") or (substr($nsave_affinities[$i],0,1) eq "%")) {
      if (substr($nsave_affinities[$i],1) =~ tr/ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_\. //c) {
         $invalid_affinities = 1;
      }
   # second check on static affinities
   # affinityRule = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789#*"
   } else {
      if ($nsave_affinities[$i] =~ tr/ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789#\*//c) {
         $invalid_affinities = 1;
      }
   }
   if ($invalid_affinities == 1) {
      $advi++;$advonline[$advi] = "TNODESAV invalid affinities [$nsave_affinities[$i]] for node";
      $advcode[$advi] = "DATAHEALTH1079E";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = $nsave[$i];
   }
   next if $nsave_ct[$i] == 1;
   $advi++;$advonline[$advi] = "TNODESAV duplicate nodes";
   $advcode[$advi] = "DATAHEALTH1007E";
   $advimpact[$advi] = $advcx{$advcode[$advi]};
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
      if ($sit_autostart[$i] eq "*SYN") {            # count Uadvisor historical sits
            $uadhist += 1 if index($sit_pdt[$i],"TRIGGER") != -1;
      }
   }
   next if $sit_ct[$i] == 1;
   $advi++;$advonline[$advi] = "TSITDESC duplicate nodes";
   $advcode[$advi] = "DATAHEALTH1021E";
   $advimpact[$advi] = $advcx{$advcode[$advi]};
   $advsit[$advi] = $sit[$i];
}

for ($i=0;$i<=$nami;$i++) {
   next if $nam_ct[$i] == 1;
   $advi++;$advonline[$advi] = "TNAME duplicate nodes";
   $advcode[$advi] = "DATAHEALTH1022E";
   $advimpact[$advi] = $advcx{$advcode[$advi]};
   $advsit[$advi] = $nam[$i];
}

for ($i=0;$i<=$nami;$i++) {
   valid_lstdate("TNAME",$nam_lstdate[$i],$nam[$i],"ID=$nam[$i]");
   next if defined $sitx{$nam[$i]};
   next if substr($nam[$i],0,8) eq "UADVISOR";
   $advi++;$advonline[$advi] = "TNAME ID index missing in TSITDESC";
   $advcode[$advi] = "DATAHEALTH1023W";
   $advimpact[$advi] = $advcx{$advcode[$advi]};
   $advsit[$advi] = $nam[$i];
}

my  $ms_offline_kds_hour = 0;
my  $ms_offline_sitmon_hour = 0;
my  $kds_per_sec = 0;
my  $sitmon_per_sec = 0;

for ($i=0;$i<=$siti;$i++) {
   valid_lstdate("TSITDESC",$sit_lstdate[$i],$sit[$i],"SITNAME=$sit[$i]");
   my $pdtone = $sit_pdt[$i];
   my $mysit;
   while($pdtone =~ m/.*?\*SIT (\S+) /g) {
      $mysit = $1;
      next if defined $sitx{$mysit};
      $advi++;$advonline[$advi] = "Situation Formula *SIT [$mysit] Missing from TSITDESC table";
      $advcode[$advi] = "DATAHEALTH1024E";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = $sit[$i];
   }
   if ($sit_reeval[$i] - $sit_bad_time gt 0) {
      $advi++;$advonline[$advi] = "Situation Sampling Interval $sit_reeval[$i] seconds - higher then danger level $sit_bad_time";
      $advcode[$advi] = "DATAHEALTH1064W";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = $sit[$i];
   }
   if (index($sit_pdt[$i],"ManagedSystem.Status") != -1) {
      if($sit[$i] ne "TEMS_Busy") {
         if ($sit_autostart[$i] eq "*YES") {
            $ms_offline_kds_hour += 3600/$sit_reeval[$i];
            $ms_offline_sitmon_hour += 3600/$sit_reeval[$i] if $sit_persist[$i] > 1;
         }
      }
   }
   $sit_autostart_total += 1 if $sit_autostart[$i] eq "*YES";
}
if ($nsave_online > 0){
   my $sit_ratio_percent = int(($sit_autostart_total*100)/$nsave_online);
   if ($sit_ratio_percent > 100) {
      $advi++;$advonline[$advi] = "Autostarted Situation to Online Agent ratio[$sit_ratio_percent%] - dangerously high";
      $advcode[$advi] = "DATAHEALTH1091W";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = "Situations_High";
   }
}
if ($ms_offline_kds_hour > 0) {
   my $nsave_total = $nsave_online + $nsave_offline;
   $kds_per_sec = ($ms_offline_kds_hour * $nsave_total)/3600;
   $sitmon_per_sec = ($ms_offline_sitmon_hour * $nsave_offline)/3600;
}

if ($ms_offline_sitmon_hour > 0) {
   my $nsave_total = $nsave_online + $nsave_offline;
   $sitmon_per_sec = ($ms_offline_sitmon_hour * $nsave_total)/3600;
}

if ($kds_per_sec > 30) {
   if ($kds_per_sec > 200) {
      $advi++;$advonline[$advi] = "MS_Offline dataserver evaluation rate $kds_per_sec dangerously high";
      $advcode[$advi] = "DATAHEALTH1087E";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = "MS_Offline";
   } else {
      $advi++;$advonline[$advi] = "MS_Offline dataserver evaluation rate $kds_per_sec somewhat high";
      $advcode[$advi] = "DATAHEALTH1086W";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = "MS_Offline";
   }
}

if ($sitmon_per_sec > 30) {
   if ($sitmon_per_sec > 100) {
      $advi++;$advonline[$advi] = "MS_Offline SITMON evaluation rate $sitmon_per_sec dangerously high";
      $advcode[$advi] = "DATAHEALTH1089E";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = "MS_Offline";
   } else {
      $advi++;$advonline[$advi] = "MS_Offline SITMON evaluation rate $kds_per_sec somewhat high";
      $advcode[$advi] = "DATAHEALTH1088W";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = "MS_Offline";
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
   $advimpact[$advi] = $advcx{$advcode[$advi]};
   $advsit[$advi] = $hsave[$i];
}

foreach my $f (keys %sysnamex) {
   my $sysname_ref = $sysnamex{$f};
   next if $sysname_ref->{ipcount} == 1;
   my $pagents = "";
   foreach my $g (keys %{$sysname_ref->{sysipx}}) {
      my $sysip_ref = $sysname_ref->{sysipx}{$g};
      foreach my $h (keys %{$sysip_ref->{instance}}) {
         my $sysname_node_ref = $sysip_ref->{instance}{$h};
         $pagents .= $h . "|";
         $pagents .= $sysname_node_ref->{thrunode} . "|";
         $pagents .= $sysname_node_ref->{hostaddr} . ",";
      }
   }
   $advi++;$advonline[$advi] = "TNODESAV duplicate $sysname_ref->{ipcount} SYSTEM_NAMEs in [$pagents]";
   $advcode[$advi] = "DATAHEALTH1075W";
   $advimpact[$advi] = $advcx{$advcode[$advi]};
   $advsit[$advi] = $f;
}

my $tema_multi = 0;
foreach my $f (keys %ipx) {
   my $ip_ref =$ipx{$f};
   next if $ip_ref->{count} < 2;
   $tema_multi += 1;
}

if ($tema_multi > 0) {
   $advi++;$advonline[$advi] = "Systems [$tema_multi] running agents with multiple TEMA levels - see later report";
   $advcode[$advi] = "DATAHEALTH1096W";
   $advimpact[$advi] = $advcx{$advcode[$advi]};
   $advsit[$advi] = "TEMA";
}

for ($i=0;$i<=$nlistvi;$i++) {
   valid_lstdate("TNODELST",$nlistv_lstdate[$i],$nlistv[$i],"V NODE=$nlistv[$i] THRUNODE=$nlistv_thrunode[$i]");
   if ($nlistv_ct[$i] > 1) {
      $advi++;$advonline[$advi] = "TNODELST Type V duplicate nodes";
      $advcode[$advi] = "DATAHEALTH1008E";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = $nlistv[$i];
   }
   my $thru1 = $nlistv_thrunode[$i];
   $nsx = $nsavex{$thru1};
   if (!defined $nsx) {
      $advi++;$advonline[$advi] = "TNODELST Type V Thrunode $thru1 missing in Node Status";
      $advcode[$advi] = "DATAHEALTH1025E";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
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
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = $nlistv[$i];
   }
   if (index($nlistv[$i]," ") != -1) {
      $advi++;$advonline[$advi] = "TNODELST TYPE V node name with embedded blank";
      $advcode[$advi] = "DATAHEALTH1050W";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
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
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = $nlistv[$i];
   }
   if (index($thru1," ") != -1) {
      $advi++;$advonline[$advi] = "TNODELST TYPE V Thrunode [$thru1] with embedded blank";
      $advcode[$advi] = "DATAHEALTH1051W";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
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
      $advi++;$advonline[$advi] = "TNODELST NODETYPE=M invalid nodelist name";
      $advcode[$advi] = "DATAHEALTH1017E";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = $nlist[$i];
   }
   if (index($nlist[$i]," ") != -1) {
      $advi++;$advonline[$advi] = "TNODELST NODETYPE=M nodelist with embedded blank";
      $advcode[$advi] = "DATAHEALTH1052W";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = $nlist[$i];
   }
}

# check TOBJACCL validity
for ($i=0;$i<=$obji;$i++){
   valid_lstdate("TOBJACCL",$obj_lstdate[$i],$obj_objname[$i],"NODEL=$obj_nodel[$i] OBJCLASS=$obj_objclass[$i] OBJNAME=$obj_objname[$i]");
   if ($obj_ct[$i] > 1) {
      $advi++;$advonline[$advi] = "TOBJACCL duplicate nodes";
      $advcode[$advi] = "DATAHEALTH1028E";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = $obj[$i];
   }
   my $objname1 = $obj_objname[$i];
   my $nodel1 = $obj_nodel[$i];
   my $class1 = $obj_objclass[$i];
   $sx = $sitx{$objname1};
   if (defined $sx) {
      next if $sit_autostart[$sx] eq "*NO";
   }
   $mx = $nlistx{$nodel1};
   $nsx = $nsavex{$nodel1};
   if ($class1 == 5140) {
      if (defined $mx) {                        # MSL defined
         if (!defined $sx) {                    # Sit not defined
            if (substr($objname1,0,3) ne "_Z_"){
               $advi++;$advonline[$advi] = "TOBJACCL Unknown Situation with a known MSL $nodel1 distribution";
               $advcode[$advi] = "DATAHEALTH1099W";
               $advimpact[$advi] = $advcx{$advcode[$advi]};
               $advsit[$advi] = $objname1;
            }
         }
      } elsif (defined $nsx) {                  # MSN defined
         if (!defined $sx) {                    # Sit not defined
            if (substr($objname1,0,3) ne "_Z_"){
                  $advi++;$advonline[$advi] = "TOBJACCL Unknown Situation with a known MSN $nodel1 distribution";
                  $advcode[$advi] = "DATAHEALTH1100W";
                  $advimpact[$advi] = $advcx{$advcode[$advi]};
                  $advsit[$advi] = $objname1;
            }
         }
      } else {                                  # Neither MSL nor MSN defined
         if (defined $sx) {                     # Sit is defined
            if (substr($nodel1,0,1) ne "*") {
               $advi++;$advonline[$advi] = "TOBJACCL known Situation with a unknown MSN/MSL $nodel1 distribution";
               $advcode[$advi] = "DATAHEALTH1101E";
               $advimpact[$advi] = $advcx{$advcode[$advi]};
               $advsit[$advi] = $objname1;
            } else {
               $advi++;$advonline[$advi] = "TOBJACCL known Situation with a unknown system generated MSL $nodel1";
               $advcode[$advi] = "DATAHEALTH1102W";
               $advimpact[$advi] = $advcx{$advcode[$advi]};
               $advsit[$advi] = $objname1;
            }
         } else {                               # Sit not defined
            if (substr($objname1,0,3) ne "_Z_"){
               $advi++;$advonline[$advi] = "TOBJACCL unknown Situation with a unknown MSN/MSL $nodel1 distribution";
               $advcode[$advi] = "DATAHEALTH1030W";
               $advimpact[$advi] = $advcx{$advcode[$advi]};
               $advsit[$advi] = $objname1;
            }
         }
      }
      next if defined $mx;         # if known as a MSL, no check for node status
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
         $advi++;$advonline[$advi] = "TOBJACCL Nodel $nodel1 System Generated MSL but missing from TNODELST";
         $advcode[$advi] = "DATAHEALTH1029W";
         $advimpact[$advi] = $advcx{$advcode[$advi]};
         $advsit[$advi] = $obj[$i];
         if ($opt_miss == 1) {
            my $pick = $obj[$i];
            $pick =~ /.*\|.*\|(.*)/;
            my $key = "DATAHEALTH1029W" . " " . $1;
            $miss{$key} = 1;
         }
         next;
      }
      if ($opt_miss == 1) {
         my $pick = $obj[$i];
         $pick =~ /.*\|.*\|(.*)/;
         my $key = "DATAHEALTH1030W" . " " . $1;
         $miss{$key} = 1;
      }
   } elsif ($class1 == 2010) {
      next if defined $groupx{$objname1};       # if item being distributed is known as a situation group, good
      $advi++;$advonline[$advi] = "TOBJACCL Group name missing in Situation Group";
      $advcode[$advi] = "DATAHEALTH1035W";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = $nodel1;
      if ($opt_miss == 1) {
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
   $advimpact[$advi] = $advcx{$advcode[$advi]};
   $advsit[$advi] = $nsave[$i];
}
## Check for TEMA level below Agent version
for ($i=0;$i<=$nsavei;$i++) {
   next if $nsave_temaver[$i] eq "";
   next if !defined $klevelx{substr($nsave_version[$i],0,5)};
   next if substr($nsave_temaver[$i],0,2) ne substr($nsave_version[$i],0,2);
   next if substr($nsave_version[$i],0,5) gt substr($tema_maxlevel,0,5);
   next if substr($nsave_temaver[$i],0,5) ge substr($nsave_version[$i],0,5);
   $advi++;$advonline[$advi] = "Agent at version [$nsave_version[$i]] using TEMA at lower release version [$nsave_temaver[$i]]";
   $advcode[$advi] = "DATAHEALTH1037W";
   $advimpact[$advi] = $advcx{$advcode[$advi]};
   $advsit[$advi] = $nsave[$i];
}

## Check for TEMA level in danger zones
my $danger_IZ76410 = 0;
my $danger_IV18016 = 0;
my $danger_IV30473 = 0;
for ($i=0;$i<=$nsavei;$i++) {
   next if $nsave_temaver[$i] eq "";
   if ( (substr($nsave_temaver[$i],0,8) ge "06.21.00") and (substr($nsave_temaver[$i],0,8) lt "06.21.03") or
        (substr($nsave_temaver[$i],0,8) ge "06.22.00") and (substr($nsave_temaver[$i],0,8) lt "06.22.03")) {
      $danger_IZ76410 += 1 if $nsave_product[$i] ne "VA";
   }
   if ( (substr($nsave_temaver[$i],0,8) eq "06.22.07") or (substr($nsave_temaver[$i],0,8) eq "06.23.01")) {
      $danger_IV18016 += 1;
   }
   if ( ((substr($nsave_temaver[$i],0,8) ge "06.22.07") and (substr($nsave_temaver[$i],0,8) le "06.22.09")) or
        ((substr($nsave_temaver[$i],0,8) ge "06.23.00") and (substr($nsave_temaver[$i],0,8) le "06.23.02"))) {
      $danger_IV30473 += 1;
   }

}

if ($danger_IZ76410 > 0) {
   $advi++;$advonline[$advi] = "Agents[$danger_IZ76410] using TEMA in IZ76410 danger zone - see following report";
   $advcode[$advi] = "DATAHEALTH1042E";
   $advimpact[$advi] = $advcx{$advcode[$advi]};
   $advsit[$advi] = "APAR";
}

if ($danger_IV18016 > 0) {
   $advi++;$advonline[$advi] = "Agents[$danger_IV18016] using TEMA in IV18016 danger zone - see following report";
   $advcode[$advi] = "DATAHEALTH1090W";
   $advimpact[$advi] = $advcx{$advcode[$advi]};
   $advsit[$advi] = "APAR";
}

if ($danger_IV30473 > 0) {
   $advi++;$advonline[$advi] = "Agents[$danger_IV30473] using TEMA in IV30473 danger zone - see following report";
   $advcode[$advi] = "DATAHEALTH1093W";
   $advimpact[$advi] = $advcx{$advcode[$advi]};
   $advsit[$advi] = "APAR";
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
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = $vtnode[$i];
   }
   $advi++;$advonline[$advi] = "Virtual Hub Table updates peak $peak_rate per second more then nominal $opt_peak_rate -  per hour [$vtnode_tot_hr] - total agents $vtnode_tot_ct";
   $advcode[$advi] = "DATAHEALTH1018W";
   $advimpact[$advi] = $advcx{$advcode[$advi]};
   $advsit[$advi] = "total";
}

for ($i=0;$i<=$mlisti;$i++) {
   valid_lstdate("TNODELST",$mlist_lstdate[$i],$mlist_node[$i],"M NODE=$mlist_node[$i] NODELST=$mlist_nodelist[$i]");
   next if $mlist_ct[$i] == 1;
   $advi++;$advonline[$advi] = "TNODELST Type M duplicate NODE/NODELIST";
   $advcode[$advi] = "DATAHEALTH1009E";
   $advimpact[$advi] = $advcx{$advcode[$advi]};
   $advsit[$advi] = $mlist[$i];
}

# Following logic estimates the dataserver load per TEMS based on number of situations.
# Load Step 1: calculate the situation distribution
# Load Step 2: Calculate the dataserver load
# Load Step 3: Produce advisory messages
# A post advisory report is created based on this calculated data.

# look through each TOBJACCL row
for ($i=0;$i<=$obji;$i++) {
   next if ($obj_objclass[$i] ne "5140") and ($obj_objclass[$i] ne "2010");         # ignore if not situation or sitgroup distribution
   my $sitone = $obj_objname[$i];               # situation being looked at or Sitgroup

   next if substr($sitone,0,8) eq "UADVISOR";
   next if substr($sitone,0,3) eq "_Z_";
   my $node1 = $obj_nodel[$i];                  # distribution
   $sx = $sitx{$sitone};
   $gx = $grpx{$sitone};
   $nlx = $nlistx{$node1};
   # For each agent in found, determine thrunode/TEMS. Add to thrunode count, sampled count, pure count, sampled impact
   # handle subnode agents via the managing agent
   my $thru = "";
   if (defined $sx) {             # Situation name
      if (defined $nlx) {         # a MSL distribution
         # read out the agents associated with this MSL
         foreach my $f (keys %{$nlist_agents[$nlx]}) {
            $mx = $magentx{$f};    # is this a subnode agent
            if (defined $mx) {
               $thru = $magent_tems[$mx];
            } else {
               $vlx = $nlistvx{$f};
               if (defined $vlx) {
                  $thru = $nlistv_tems[$vlx];
               }
            }
            if ($thru ne "") {
               $tx = $temsx{$thru};
               if (defined $tx) {
                  if (!defined $tems_sits[$tx]{$sitone}) {
                     $tems_sits[$tx]{$sitone} = 1;
                     if ($sit_reeval[$sx] == 0) {
                        $tems_puresit[$tx] += 1;
                     } else {
                        $tems_sampsit[$tx] += 1;
                        $tems_sampload[$tx] += (3600)/$sit_reeval[$sx];
                     }
                  }
               }
            }
         }
      } else {                    # a MSN distribution
         $mx = $magentx{$node1};    # is this a subnode agent
         if (defined $mx) {
            $thru = $magent_tems[$mx];
         } else {
            $vlx = $nlistvx{$node1};
            if (defined $vlx) {
               $thru = $nlistv_tems[$vlx];
            }
         }
         if ($thru ne "") {
            $tx = $temsx{$thru};
            if (defined $tx) {
               if (!defined $tems_sits[$tx]{$sitone}) {
                  $tems_sits[$tx]{$sitone} = 1;
                  if (defined $tx) {
                     if ($sit_reeval[$sx] == 0) {
                        $tems_puresit[$tx] += 1;
                     } else {
                        $tems_sampsit[$tx] += 1;
                        $tems_sampload[$tx] += (3600)/$sit_reeval[$sx];
                     }
                  }
               }
            }
         }
      }
   } elsif (defined $gx) {        # Sitgroup Identification
      # determine the associated situations
      %sum_sits = ();
      sitgroup_get_sits($gx);
      if (defined $nlx) {         # a MSL distribution
         # read out the agents associated with this MSL
         foreach my $f (keys %{$nlist_agents[$nlx]}) {
            $mx = $magentx{$f};    # is this a subnode agent
            if (defined $mx) {
$DB::single=2;
               $thru = $magent_tems[$mx];
            } else {
               $vlx = $nlistvx{$f};
               if (defined $vlx) {
                  $thru = $nlistv_tems[$vlx];
               }
            }
            if ($thru ne "") {
               $tx = $temsx{$thru};
               if (defined $tx) {
                  foreach my $s (keys %sum_sits) {
                     $sx =  $sitx{$s};
                     next if !defined $sx;
                     if (!defined $tems_sits[$tx]{$s}) {
                        $tems_sits[$tx]{$s} = 1;
                        if ($sit_reeval[$sx] == 0) {
                           $tems_puresit[$tx] += 1;
                        } else {
                           $tems_sampsit[$tx] += 1;
                           $tems_sampload[$tx] += (3600)/$sit_reeval[$sx];
                        }
                     }
                  }
               }
            }
         }
      } else {                    # a MSN distribution
         $mx = $magentx{$node1};    # is this a subnode agent
         if (defined $mx) {
            $thru = $magent_tems[$mx];
         } else {
            $vlx = $nlistvx{$node1};
            if (defined $vlx) {
               $thru = $nlistv_tems[$vlx];
            }
         }
         if ($thru ne "") {
            $tx = $temsx{$thru};
            if (defined $tx) {
               foreach my $s (keys %sum_sits) {
                  $sx =  $sitx{$s};
                  next if !defined $sx;
                  if (!defined $tems_sits[$tx]{$s}) {
                     $tems_sits[$tx]{$s} = 1;
                     if ($sit_reeval[$sx] == 0) {
                        $tems_puresit[$tx] += 1;
                     } else {
                        $tems_sampsit[$tx] += 1;
                        $tems_sampload[$tx] += (3600)/$sit_reeval[$sx];
                     }
                  }
               }
            }
         }
      }
   }
}


if ($opt_nohdr == 0) {
   print OH "ITM Database Health Report $gVersion\n";
   print OH "\n";
}

   my $remote_limit = 1500;
if ($hub_tems_no_tnodesav == 0) {
   if (defined $hubi) {
      my $hub_limit = 10000;
      $hub_limit = 20000 if substr($tems_version[$hubi],0,5) gt "06.23";

      if ($hub_tems_ct > $hub_limit){
         $advi++;$advonline[$advi] = "Hub TEMS has $hub_tems_ct managed systems which exceeds limits $hub_limit";
         $advcode[$advi] = "DATAHEALTH1005W";
         $advimpact[$advi] = $advcx{$advcode[$advi]};
         $advsit[$advi] = $hub_tems;
      }
      if ($tems_version[$hubi]  eq "06.30.02") {
         $advi++;$advonline[$advi] = "Danger of TEMS crash sending events to receiver APAR IV50167";
         $advcode[$advi] = "DATAHEALTH1067E";
         $advimpact[$advi] = $advcx{$advcode[$advi]};
         $advsit[$advi] = $hub_tems;
      }
   }


   print OH "Hub,$hub_tems,$hub_tems_ct\n";
   for (my $i=0;$i<=$temsi;$i++) {
      if ($tems_ct[$i] > $remote_limit){
         $advi++;$advonline[$advi] = "TEMS has $tems_ct[$i] managed systems which exceeds limits $remote_limit";
         $advcode[$advi] = "DATAHEALTH1006W";
         $advimpact[$advi] = $advcx{$advcode[$advi]};
         $advsit[$advi] = $tems[$i];
      }
      my $tlevel = substr($tems_version[$i],0,5);
      my $tlevel_ref = $eoslevelx{$tlevel};
      if (defined $tlevel_ref) {
         if ($tlevel_ref->{future} == 0) {
            $advi++;$advonline[$advi] = "End of Service TEMS $tems[$i] maint[$tems_version[$i]] date[$tlevel_ref->{date}]";
            $advcode[$advi] = "DATAHEALTH1083W";
            $advimpact[$advi] = $advcx{$advcode[$advi]};
            $advsit[$advi] = "eos";
         } else {
            $advi++;$advonline[$advi] = "Future End of Service TEMS tems[$i] maint[$tems_version[$i]] date[$tlevel_ref->{date}]";
            $advcode[$advi] = "DATAHEALTH1084W";
            $advimpact[$advi] = $advcx{$advcode[$advi]};
            $advsit[$advi] = "eos";
         }
      }
      if ($tems[$i] ne $hub_tems) {
         if (substr($tems_version[$i],0,5) gt substr($hub_tems_version,0,5)) {
            $advi++;$advonline[$advi] = "Remote TEMS $tems[$i] maint[$tems_version[$i]] is later level than Hub TEMS $hub_tems maint[$hub_tems_version]";
            $advcode[$advi] = "DATAHEALTH1097W";
            $advimpact[$advi] = $advcx{$advcode[$advi]};
            $advsit[$advi] = "TEMS";
         }
      }
      my $poffline = "Offline";
      my $node1 = $tems[$i];
      my $nx = $nsavex{$node1};
      if (defined $nx) {
         $poffline = "Online" if $nsave_o4online[$nx] eq "Y";
      }
      my $sit_rate = $tems_sampload[$i]/3600;
      my $psit_rate = sprintf("%.2f",$sit_rate);
      if ($sit_rate > 4) {
         $advi++;$advonline[$advi] = "TEMS Dataserver SQL Situation Load $psit_rate per second more than 4.00/second";
         $advcode[$advi] = "DATAHEALTH1092W";
         $advimpact[$advi] = $advcx{$advcode[$advi]};
         $advsit[$advi] = "$tems[$i]";
      }
      my $sit_total = $tems_sampsit[$i] + $tems_puresit[$i];
      if ($sit_total > 2000) {
         if ($tems[$i] eq $hub_tems) {
            $advi++;$advonline[$advi] = "HUB TEMS Dataserver SQL Situation Startup total $sit_total more than 2000";
            $advcode[$advi] = "DATAHEALTH1095W";
         } else {
            $advi++;$advonline[$advi] = "TEMS Dataserver SQL Situation Startup total $sit_total more than 2000";
            $advcode[$advi] = "DATAHEALTH1094W";
        }
         $advimpact[$advi] = $advcx{$advcode[$advi]};
         $advsit[$advi] = "$tems[$i]";
      }
      print OH "TEMS,$tems[$i],$tems_ct[$i],$poffline,$tems_version[$i],$tems_arch[$i],\n";
   }
   for (my $i=0;$i<=$tepsi;$i++) {
      my $poffline = "Offline";
      my $node1 = $teps[$i];
      my $nx = $nsavex{$node1};
      if (defined $nx) {
         $poffline = "Online" if $nsave_o4online[$nx] eq "Y";
      }
      print OH "TEPS,$teps[$i],,$poffline,$teps_version[$i],$teps_arch[$i],\n";
   }
   print OH "\n";

   print OH "i/5 Agent Level report\n";
   foreach my $f (sort { $a cmp $b } keys %ka4x) {
      my $i = $ka4x{$f};
      my $ka4_ct = $ka4_version_count[$ka4x{$f}];
      print OH $ka4_product[$i] . "," . $ka4_version[$i] . "," . $ka4_version_count[$i] . ",\n";
   }
   print OH "\n";


   # One case had 3 TEMS in FTO mode - so check for 2 or more
   if ($isFTO >= 2){
      print OH "Fault Tolerant Option FTO enabled Status[$opt_fto]\n\n";
      if ($tems_ctnok[$hubi] > 0) {
         $advi++;$advonline[$advi] = "FTO hub TEMS has $tems_ctnok[$hubi] agents configured which is against FTO best practice";
         $advcode[$advi] = "DATAHEALTH1020W";
         $advimpact[$advi] = $advcx{$advcode[$advi]};
         $advsit[$advi] = $hub_tems;
      }
   }
}

my $fraction;
my $pfraction;

if ($tema_total_eos > 0) {
   foreach my $f (sort { $a cmp $b } keys %eoslevelx) {
      my $tlevel_ref = $eoslevelx{$f};
      next if $tlevel_ref->{count} == 0;
      if ($tlevel_ref->{future} == 0) {
         $advi++;$advonline[$advi] = "End of Service agents maint[$f] count[$tlevel_ref->{count}] date[$tlevel_ref->{date}]";
         $advcode[$advi] = "DATAHEALTH1081W";
         $advimpact[$advi] = $advcx{$advcode[$advi]};
         $advsit[$advi] = "eos";
      } else {
         $advi++;$advonline[$advi] = "Future End of Service agents maint[$f] count[$tlevel_ref->{count}] date[$tlevel_ref->{date}]";
         $advcode[$advi] = "DATAHEALTH1082W";
         $advimpact[$advi] = $advcx{$advcode[$advi]};
         $advsit[$advi] = "eos";
      }
   }
}


# check on case with historical data collection but no WPAs running
if ($uadhist > 0) {
   if ($hdonline == 0) {
      $advi++;$advonline[$advi] = "UADVISOR Historical Situations enabled [$uadhist] but no online WPAs seen";
      $advcode[$advi] = "DATAHEALTH1098E";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = "TEMS";
   }
}

# Calculate for same agent inserted into TNODELST multiple times the mode [most common frequency]
my %online_count = ();
my $online_mode = 0;
foreach my $f (keys %eibnodex) {
   $online_count{$eibnodex{$f}->{count}} += 1;
}

for my $k (sort {$online_count{$b} <=> $online_count{$a}} keys %online_count) {
   $online_mode = $k;
   last;
}

# Calculate advisories for same agent inserted into TNODELST multiple times more then most common
# This is an important signal about identically named agents on different systems.
$top20 = 0;
foreach my $f (sort { $eibnodex{$b}->{count} <=> $eibnodex{$a}->{count} ||
                      $a cmp $b
                    } keys %eibnodex) {
   last if $eibnodex{$f}->{count} <= $online_mode;
   $top20 += 1;
   if ($eibnodex{$f}->{count} > 2) {
      $advi++;$advonline[$advi] = "Agent registering $eibnodex{$f}->{count} times: possible duplicate agent names";
      $advcode[$advi] = "DATAHEALTH1068E";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = $f;
   }
   last if $top20 > 19;
}

my $event_ct = keys %eventx;

$top20 = 0;
$eventx_dur = 0;
if ($event_ct > 0) {
   foreach my $f (sort { $eventx{$b}->{count} <=> $eventx{$a}->{count} ||
                         $a cmp $b
                       } keys %eventx) {
      $top20 += 1;
      last if $top20 > 20;
      my $ncount = keys %{$eventx{$f}->{origin}};
      my $sit_start = $eventx{$f}->{start};
      my $sit_last = $eventx{$f}->{last};
      my $sit_dur = get_epoch($sit_last) - get_epoch($sit_start) + 1;
      my $sit_rate = ($eventx{$f}->{count}*60)/$sit_dur;
      my $psit_rate = sprintf("%.2f",$sit_rate);
      if ($sit_rate > 3) {
         my $pnodes;
         for my $g (keys %{$eventx{$f}->{nodes}}) {
            $pnodes .= $g . " ";
         }
         $advi++;$advonline[$advi] = "Situation Event arriving $psit_rate per minute in $sit_dur second(s) from nodes[$pnodes] Atomize[$eventx{$f}->{atomize}]";
         $advcode[$advi] = "DATAHEALTH1074W";
         $advimpact[$advi] = $advcx{$advcode[$advi]};
         $advsit[$advi] = $eventx{$f}->{sitname};
      }
   }
}
$eventx_dur = 1;
if ($eventx_last != -1) {
   $eventx_dur = get_epoch($eventx_last) - get_epoch($eventx_start);
}
if ($top20 != 0) {
   print OH "Total,$eventx_dur seconds,\n";
}

# check for ghost situation event status
foreach my $f (sort { $eventx{$b}->{count} <=> $eventx{$a}->{count} ||
                      $a cmp $b
                    } keys %eventx) {
   next if defined $sitx{$eventx{$f}->{sitname}};
   my $pnodes;
   for my $g (keys %{$eventx{$f}->{nodes}}) {
      $pnodes .= $g . " ";
   }

   $advi++;$advonline[$advi] = "Situation undefined but Events arriving from nodes[$pnodes]";
   $advcode[$advi] = "DATAHEALTH1085W";
   $advimpact[$advi] = $advcx{$advcode[$advi]};
   $advsit[$advi] = $f;
}

my $tadvi = 0;
my $eventx_ct = 0;
foreach my $f (sort { $eventx{$b}->{count} <=> $eventx{$a}->{count} ||
                      $a cmp $b
                    } keys %eventx) {
   $eventx_ct += $eventx{$f}->{count};
}
if ($eventx_ct > 0) {
   if ($eventx_dur >1) {
      my $sit_rate = ($eventx_ct*60)/$eventx_dur;
      my $psit_rate = sprintf("%.2f",$sit_rate);
      if ($sit_rate > 60) {
         $advi++;$advonline[$advi] = "Situation Status Events arriving $psit_rate per minute";
         $advcode[$advi] = "DATAHEALTH1080W";
         $advimpact[$advi] = $advcx{$advcode[$advi]};
         $advsit[$advi] = "sitrate";
      }
   }
}

$tadvi = $advi + 1;
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

      print OH "$advimpact[$j],$advcode[$j],$advsit[$j],$advonline[$j]\n";
      $max_impact = $advimpact[$j] if $advimpact[$j] > $max_impact;
      $advgotx{$advcode[$j]} = $advimpact[$j];
   }
}


print OH "\n";
print OH "Top 20 most recently added or changed Situations\n";
print OH "LSTDATE,Situation,Formula\n";
$top20 = 0;
foreach my $f ( sort { $sit_lstdate[$sitx{$b}] cmp $sit_lstdate[$sitx{$a}]} keys %sitx) {
   $top20 += 1;
   my $j = $sitx{$f};
   print OH "=\"$sit_lstdate[$j]\",$sit_psit[$j],$sit_pdt[$j],\n";
   last if $top20 >= 20;
}

if ($tema_total_count > 0 ){
   print OH "\n";
   print OH "TEMA Deficit Report Summary - 132 TEMA APARs to latest maintenance ITM 630 FP6\n";
   $oneline = $tema_total_count . ",Agents with TEMA,";
   print OH "$oneline\n";
   $oneline = $tema_total_good_count . ",Agents with TEMA version same as TEMS version,";
   print OH "$oneline\n";
   $oneline = $tema_total_deficit_count . ",Agents with TEMA version lower than TEMS version,";
   print OH "$oneline\n";
   $oneline = $tema_total_post_count . ",Agents with TEMA version higher than TEMS version,";
   print OH "$oneline\n";
   $fraction = ($tema_total_deficit_count*100) / $tema_total_count;
   $pfraction = sprintf( "%.2f", $fraction);
   $oneline = $pfraction . "%,Per cent TEMAs less than TEMS version,";
   $tema_total_deficit_percent = $pfraction;
   print OH "$oneline\n";
   $oneline = $tema_total_days . ",Total Days TEMA version less than TEMS version,";
   print OH "$oneline\n";
   $fraction = 0;
   $fraction = ($tema_total_days) / $tema_total_apars if $tema_total_apars > 0;
   $oneline = sprintf( "%.0f", $fraction) . ",Average days/APAR TEMA version less than TEMS version,";
   print OH "$oneline\n";
   $oneline = $tema_total_apars . ",Total APARS TEMA version less than TEMS version,";
   print OH "$oneline\n";
   $fraction = ($tema_total_apars) / $tema_total_count;
   $oneline = sprintf( "%.0f", $fraction) . ",Average APARS TEMA version less than TEMS version,";
   print OH "$oneline\n";
   $oneline = $tema_total_max_days . ",Total Days TEMA version less than latest TEMS version,";
   print OH "$oneline\n";
   $fraction = 0;
   $fraction = ($tema_total_max_days) / $tema_total_max_apars if $tema_total_max_apars > 0;
   $oneline = sprintf( "%.0f", $fraction) . ",Average days/APAR TEMA version less than latest TEMS version,";
   print OH "$oneline\n";
   $oneline = $tema_total_max_apars . ",Total APARS TEMA version less than latest TEMS version,";
   print OH "$oneline\n";
   $fraction = ($tema_total_max_apars) / $tema_total_count;
   $oneline = sprintf( "%.0f", $fraction) . ",Average APARS TEMA version less than latest TEMS version,";
   print OH "$oneline\n";
}

if ($npc_ct > 0 ) {
   print OH "\n";
   print OH "Product Summary Report\n";
   print OH "Product[Agent],Count,Versions,TEMAs,\n";
   foreach my $f (sort { $a cmp $b } keys %pcx) {
      my $pc_ref = $pcx{$f};
      $oneline = $f . "," . $pc_ref->{count} . ",";

      my $pversions = "";
      foreach my $g  (sort { $a cmp $b } keys %{$pc_ref->{versions}}) {
         my $version_ref = $pc_ref->{versions}{$g};
         $pversions .= $g . "(" . $version_ref->{count} . ") ";
      }
      $pversions = substr($pversions,0,-1) if $pversions ne "";
      $oneline .= "Versions[" . $pversions . "],";

      my $ptemas = "";
      foreach my $g  (sort { $a cmp $b } keys %{$pc_ref->{temas}}) {
         my $tema_ref = $pc_ref->{temas}{$g};
         $ptemas .= $g . "(" . $tema_ref->{count} . ") ";
      }
      $ptemas = substr($ptemas,0,-1) if $ptemas ne "";
      $oneline .= "TEMAs[" . $ptemas . "],";

      my $pinfo = "";
      foreach my $g  (sort { $a cmp $b } keys %{$pc_ref->{info}}) {
         my $info_ref = $pc_ref->{info}{$g};
         $pinfo .= $g . "(" . $info_ref->{count} . ") ";
      }
      $pinfo = substr($pinfo,0,-1) if $pinfo ne "";
      $oneline .= "INFOs[" . $pinfo . "],";
      print OH "$oneline\n";
   }

}


if ($opt_event == 1){
   print OH "\n";
   print OH "Flapper Situation Report\n";
   print OH "Situation,Atomize,Count,Open,Close,Node,Thrunode,Interval\n";
   foreach my $f (sort { $eventx{$b}->{count} <=> $eventx{$a}->{count} ||
                         $a cmp $b
                        } keys %eventx) {
      foreach my $g (sort {$a cmp $b} keys  %{$eventx{$f}->{origin}}) {
         next if $eventx{$f}->{reeval} == 0;                                    # ignore pure events for this report
         next if $eventx{$f}->{origin}{$g}->{count} == 1;             # ignore single cases
         my $diff = abs($eventx{$f}->{origin}{$g}->{open}-$eventx{$f}->{origin}{$g}->{close});
         next if $diff < 2;
         $oneline = $eventx{$f}->{sitname} . ",";
         $oneline .= $eventx{$f}->{atomize} . ",";
         $oneline .=  $eventx{$f}->{origin}{$g}->{count} . ",";
         $oneline .=  $eventx{$f}->{origin}{$g}->{open} . ",";
         $oneline .=  $eventx{$f}->{origin}{$g}->{close} . ",";
         $oneline .=  $eventx{$f}->{origin}{$g}->{node} . ",";
         $oneline .=  $eventx{$f}->{origin}{$g}->{thrunode} . ",";
         $oneline .=  $eventx{$f}->{reeval} . ",";
         print OH "$oneline\n";
      }
   }
   print OH "\n";

   print OH "Pure Situations with DisplayItems Report\n";
   print OH "Situation,Atomize,Count,Open,Close,Thrunode,Interval\n";
   foreach my $f (sort { $eventx{$b}->{count} <=> $eventx{$a}->{count} ||
                         $a cmp $b
                       } keys %eventx) {
      next if $eventx{$f}->{reeval} > 0;
      foreach my $g (sort {$a cmp $b} keys  %{$eventx{$f}->{origin}}) {
         $oneline = $eventx{$f}->{sitname} . ",";
         $oneline .= $eventx{$f}->{atomize} . ",";
         $oneline .=  $eventx{$f}->{origin}{$g}->{open} . ",";
         $oneline .=  $eventx{$f}->{origin}{$g}->{open} . ",";
         $oneline .=  "0,";
         $oneline .=  $eventx{$f}->{origin}{$g}->{thrunode} . ",";
#      my $ncount = keys %{$eventx{$f}->{origin}};
#      $oneline .=  $ncount . ",";
         $oneline .=  $eventx{$f}->{reeval} . ",";
         print OH "$oneline\n";
      }
   }
}

if ($tema_total_eos > 0 ) {
   print OH "\n";
   print OH "End of Service TEMAs\n";
   print OH "Node,Maint,Type,Date\n";
   for ($i=0; $i<=$nsavei; $i++) {
      my $node1 = $nsave[$i];
      my $tlevel = substr($nsave_temaver[$i],0,5);
      next if $tlevel eq "";
      my $tlevel_ref = $eoslevelx{$tlevel};
      next if !defined $tlevel_ref;
      next if $tlevel_ref->{future} == 1;
      $oneline = $node1 . ",";
      $oneline .= $nsave_temaver[$i] . ",";
      $oneline .= "EOS" . ",";
      $oneline .= $tlevel_ref->{date} . ",";
      print OH "$oneline\n";
   }
   for ($i=0; $i<=$nsavei; $i++) {
      my $node1 = $nsave[$i];
      my $tlevel = substr($nsave_temaver[$i],0,5);
      next if $tlevel eq "";
      my $tlevel_ref = $eoslevelx{$tlevel};
      next if !defined $tlevel_ref;
      next if $tlevel_ref->{future} == 0;
      $oneline = $node1 . ",";
      $oneline .= $nsave_temaver[$i] . ",";
      $oneline .= "FutureEOS" . ",";
      $oneline .= $tlevel_ref->{date} . ",";
      print OH "$oneline\n";
   }
}
print OH "\n";


# Calculate for same agent inserted into TNODELST multiple times more then most common
# This is an important signal about identically named agents on different systems.
$top20 = 0;
foreach my $f (sort { $eibnodex{$b}->{count} <=> $eibnodex{$a}->{count} ||
                      $a cmp $b
                    } keys %eibnodex) {
   last if $eibnodex{$f}->{count} <= $online_mode;
   if ($top20 == 0) {
      print OH "Maximum Top 20 agents showing online status more than $online_mode times - the most common number\n";
      print OH "OnlineCount,Node,ThrunodeCount,Thrunodes\n";
   }
   $top20 += 1;
   $oneline = $eibnodex{$f}->{count} . ",";
   $oneline .= $f . ",";
   my $pthrunode = "";
   my $pthruct = 0;
   foreach my $g (sort {$a cmp $b} keys  %{$eibnodex{$f}->{thrunode}}) {
      $pthruct += 1;
      $pthrunode .= ":" if $pthrunode ne "";
      $pthrunode .= $g;
   }
   $oneline .= $pthruct . "," . $pthrunode . ",";
   print OH "$oneline\n";
   last if $top20 > 19;
}
print OH "\n" if $top20 > 0;


$top20 = 0;
$eventx_dur = 0;
print OH "Top 20 Situation Event Report\n";
print OH "Situation,Count,Open,Close,NodeCount,Interval,Atomize,Rate,Nodes\n";
if ($event_ct > 0) {
   foreach my $f (sort { $eventx{$b}->{count} <=> $eventx{$a}->{count} ||
                         $a cmp $b
                       } keys %eventx) {
      $top20 += 1;
      last if $top20 > 20;
      $oneline = $eventx{$f}->{sitname} . ",";
      $oneline .=  $eventx{$f}->{count} . ",";
      $oneline .=  $eventx{$f}->{open} . ",";
      $oneline .=  $eventx{$f}->{close} . ",";
      my $ncount = keys %{$eventx{$f}->{origin}};
      $oneline .=  $ncount . ",";
      $oneline .=  $eventx{$f}->{reeval} . ",";
      $oneline .=  $eventx{$f}->{atomize} . ",";
      my $sit_start = $eventx{$f}->{start};
      my $sit_last = $eventx{$f}->{last};
      my $sit_dur = get_epoch($sit_last) - get_epoch($sit_start) + 1;
      my $sit_rate = ($eventx{$f}->{count}*60)/$sit_dur;
      my $psit_rate = sprintf("%.2f",$sit_rate);
      $oneline .=  $psit_rate . ",";
      my $pnodes = "";
      my $cnodes = 0;
      foreach my $g (keys %{$eventx{$f}->{origin}}) {
         $cnodes += 1;
         last if $cnodes > 3;
         my $onenode = $g;
         $onenode =~ s/\s+//g;
         $pnodes .= $onenode . ";";
      }
      $oneline .=  $pnodes . ",";
      print OH "$oneline\n";
   }
}
$eventx_dur = 1;
if ($eventx_last != -1) {
   $eventx_dur = get_epoch($eventx_last) - get_epoch($eventx_start);
}
if ($top20 != 0) {
   print OH "Total,$eventx_dur seconds,\n";
}

print OH "\n";
print OH "TEMS Situation Load Impact Report\n";
print OH "Hub,$hub_tems,$hub_tems_ct\n";
print OH ",TEMSnodeid,Count,Status,Version,Arch,SampSit,SampLoad/s,PureSit,\n";
for (my $i=0;$i<=$temsi;$i++) {
   my $poffline = "Offline";
   my $node1 = $tems[$i];
   my $nx = $nsavex{$node1};
   if (defined $nx) {
      $poffline = "Online" if $nsave_o4online[$nx] eq "Y";
   }
   my $sit_rate = $tems_sampload[$i]/3600;
   my $psit_rate = sprintf("%.2f",$sit_rate);
   print OH "TEMS,$tems[$i],$tems_ct[$i],$poffline,$tems_version[$i],$tems_arch[$i],$tems_sampsit[$i],$psit_rate,$tems_puresit[$i],\n";
}

if ($danger_IZ76410 > 0) {
   print OH "\n";
   print OH "TEMA Agent(s) in APAR IZ76410 danger\n";
   print OH "Agent,Hostaddr,TEMAver,\n";

   for ($i=0;$i<=$nsavei;$i++) {
      next if $nsave_temaver[$i] eq "";
      if ( (substr($nsave_temaver[$i],0,8) ge "06.21.00") and (substr($nsave_temaver[$i],0,8) lt "06.21.03") or
           (substr($nsave_temaver[$i],0,8) ge "06.22.00") and (substr($nsave_temaver[$i],0,8) lt "06.22.03")) {
         print OH "$nsave[$i],$nsave_hostaddr[$i],$nsave_temaver[$i],\n" if $nsave_product[$i] ne "VA";
      }
   }
}

if ($danger_IV18016 > 0) {
   print OH "\n";
   print OH "TEMA Agent(s) in APAR IV18016 danger\n";
   print OH "Agent,Hostaddr,TEMAver,\n";

   for ($i=0;$i<=$nsavei;$i++) {
      next if $nsave_temaver[$i] eq "";
      if ( (substr($nsave_temaver[$i],0,8) eq "06.22.07") or (substr($nsave_temaver[$i],0,8) eq "06.23.01")) {
         print OH "$nsave[$i],$nsave_hostaddr[$i],$nsave_temaver[$i],\n";
      }
   }
}

if ($danger_IV30473 > 0) {
   print OH "\n";
   print OH "TEMA Agent(s) in APAR IV30473 danger\n";
   print OH "Agent,Hostaddr,TEMAver,\n";
   for ($i=0;$i<=$nsavei;$i++) {
      next if $nsave_temaver[$i] eq "";
      if ( ((substr($nsave_temaver[$i],0,8) ge "06.22.07") and (substr($nsave_temaver[$i],0,8) le "06.22.09")) or
           ((substr($nsave_temaver[$i],0,8) ge "06.23.00") and (substr($nsave_temaver[$i],0,8) le "06.23.02"))) {
         print OH "$nsave[$i],$nsave_hostaddr[$i],$nsave_temaver[$i],\n";
      }
   }
}

if ($tema_multi > 0) {
   print OH "\n";
   print OH "Systems with Multiple TEMA levels\n";
   print OH "IP_Address,Agent,TEMAver,TEMAarch,\n";
   foreach my $f (keys %ipx) {
      my $ip_ref =$ipx{$f};
      next if $ip_ref->{count} < 2;
      foreach my $g (keys %{$ip_ref->{agents}}) {
         $oneline = $f . ",";
         $oneline .= $g . ",";
         $oneline .= $ip_ref->{agents}{$g} . ",";
         $oneline .= $ip_ref->{arch}{$g} . ",";
         print OH "$oneline\n";
      }
   }
}

if ($advi != -1) {
   print OH "\n";
   print OH "Advisory Trace, Meaning and Recovery suggestions follow\n\n";
   foreach my $f ( sort { $a cmp $b } keys %advgotx ) {
      print OH "Advisory code: " . $f . "\n";
      print OH "Impact:" . $advgotx{$f}  . "\n";
      if (defined $advtextx{$f}) {
         print OH $advtextx{$f};
      } else {
         print OH "No text yet!\n";
      }
   }
}

close OH;

if ($opt_s ne "") {
   if ($max_impact > 0 ) {
        open SH, ">$opt_s";
        if (tell(SH) != -1) {
           $oneline = "REFIC ";
           $oneline .= $max_impact . " ";
           $oneline .= $tadvi . " ";
           $oneline .= $tema_total_deficit_percent . "% ";
           $oneline .= $hub_tems_version . " ";
           $oneline .= $hub_tems . " ";
           $oneline .= $hub_tems_ct . " ";
           $oneline .= "FTO[$opt_fto]" . " ";
           $oneline .= "https://ibm.biz/BdFrJL" . " ";
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
     } elsif  ($code eq "DATAHEALTH1029W") {
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

# sitgroup_get_sits calculates the sum of all situations which are in this group or
# further groups in the DAG [Directed Acyclic Graph] that composes the
# situation groups. Result is returned in the global hash sum_sits which the caller manages.

# $grp_grp is an array
# $grp_grp[$base_node] is one scalar instance
# The instance is actually a hash of values, so we reference that by forcing it
#   %{$grp_grp[$base_node]} and that way the hash can be worked on.

sub sitgroup_get_sits
{
   my $base_node = shift;     # input index

   while( my ($refsit, $refval) = each %{$grp_sit[$base_node]}) {    # capture the situations into global hash.
      $sum_sits{$refsit} = 1;
   }
   while( my ($refgrp, $refval) = each %{$grp_grp[$base_node]}) {    # for groups, call recursively
      my $refgx = $grpx{$refgrp};
      next if !defined $refgx;
      sitgroup_get_sits($refgx);
   }
}

# TOVERITEM - Specifics of Situation Override detals
# Capture 4 columns from the Situation Overide Item table and store for later analysis
#  The error cases are
#    1) CALID is not blank and does not reference a known TCALENDAR ID column
#    2) ID does not reference a known TOVERRIDE ID column
#  It is normal to have multiple ID fields, so that is not checked
#  The LSTDATE is essentially unused... TOVERITEM is treated with TOVERRIDE in FTO
#  so the TOVERRIDE LSTDATE is the field to check.

sub new_toveritem {
   my ($iid,$ilstdate,$iitemid,$icalid) = @_;
   my $tcx = $tcix{$iitemid};
   if (!defined $tcx) {
      $tcii += 1;
      $tcx = $tcii;
      $tci[$tcx] = $iitemid;
      $tcix{$iitemid} = $tcx;
      $tci_count[$tcx] = 0;
      $tci_lstdate[$tcx] = $ilstdate;
      $tci_id[$tcx] = $iid;
      $tci_calid[$tcx] = $icalid;
   }
   $tci_count[$tcx] += 1;
}
# TOVERRIDE - Situation Override definition
# Capture 3 columns from the Situation Overide table and store for later analysis
#  The error cases are
#    1) LSTDATE is blank and cannot be FTO synchronized
#    2) LSTDATE is in future and will sabotage FTO synchronization before ITM 630 FP3
#    3) SITNAME does not reference a known TSITDESC SITNAME column
#    4) ID field is present more then once - duplicate keys

sub new_toverride {
   my ($iid,$ilstdate,$isitname) = @_;
   my $tcx = $calx{$iid};
   if (!defined $tcx) {
      $tcai += 1;
      $tcx = $tcai;
      $tca[$tcx] = $iid;
      $tcax{$iid} = $tcx;
      $tca_count[$tcx] = 0;
      $tca_lstdate[$tcx] = $ilstdate;
      $tca_sitname[$tcx] = $isitname;
   }
   $tca_count[$tcx] += 1;
}

sub new_tcalendar {
   my ($iid,$ilstdate,$iname) = @_;
   my $tcx = $calx{$iid};
   if (!defined $tcx) {
      $cali += 1;
      $tcx = $cali;
      $cal[$tcx] = $iid;
      $calx{$iid} = $tcx;
      $cal_count[$tcx] = 0;
      $cal_lstdate[$tcx] = $ilstdate;
      $cal_name[$tcx] = $iname;
   }
   $cal_count[$tcx] += 1;
}

sub new_tactypcy {
   my ($iactname,$ipcyname,$ilstdate,$itypestr,$iactinfo) = @_;
   my $pcy_ref = $pcyx{$ipcyname};
   if (!defined $pcy_ref) {
      $advi++;$advonline[$advi] = "Policy Activity [ACTNAME=$iactname] Unknown policy name";
      $advcode[$advi] = "DATAHEALTH1055E";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = $ipcyname;
   } else {
      if ($itypestr eq "*WAIT_ON_SITUATION") {
         $pcyx{$ipcyname}->{sit}{$iactinfo} = 1;
      } elsif ($itypestr eq "Evaluate_Situation") {
         $pcyx{$ipcyname}->{eval}{$iactinfo} = 1;
      } elsif ($itypestr eq "Wait_For_Sit_Reset") {
         $pcyx{$ipcyname}->{sit}{$iactinfo} = 1;
      }
   }
}

sub new_tpcydesc {
   my ($ipcyname,$ilstdate,$iautostart) = @_;
   my $pcy_ref = $pcyx{$ipcyname};
   if (!defined $pcy_ref) {
      my %pcy_sit = ();
      my %pcy_eval = ();
      my %pcyref = (
                      count => 0,           # count of PCYNAMEs - looking for duplicates
                      lstdate => $ilstdate, # last update date
                      sit  => \%pcy_sit,    # hash of Wait on Sits
                      eval => \%pcy_eval,   # hash of Evaluation Sit
                      autostart => $iautostart, # is policy operational
                   );
      $pcyx{$ipcyname} = \%pcyref;
      $pcy_ref = \%pcyref;
   }
   $pcy_ref->{count} += 1;
}

sub new_evntmap {
   my ($iid,$ilstdate,$imap) = @_;
   $evmapi += 1;
   $evmap[$evmapi] = $iid;
   $evmap_lstdate[$evmapi] = $ilstdate;
   $evmap_map[$evmapi] = $imap;
}

sub new_cct {
   my ($ikey,$ilstdate,$iname) = @_;
   $ccti += 1;
   $cct[$ccti] = $ikey;
   $cct_lstdate[$ccti] = $ilstdate;
   $cct_name[$ccti] = $iname;
}

sub new_evntserver {
   my ($iid,$ilstdate,$ilstusrprf) = @_;
   $evti += 1;
   $evt[$evti] = $iid;
   $evt_lstdate[$evti] = $ilstdate;
   $evt_lstusrprf[$evti] = $ilstusrprf;
}

sub new_tgroup {
   my ($igrpclass,$iid,$ilstdate,$igrpname) = @_;
   my $key = $igrpclass . "|" . $iid;
   my $group_detail_ref = $group{$key};

   if (!defined $group_detail_ref) {
      my %igroup = (
                      grpclass => $igrpclass,      # GRPCLASS usually 2010
                      id => $iid,                   # ID is the internal group name
                      grpname => $igrpname,        # GRPNAME is external user name
                      indirect => 0,               # when 1, included in a TGROUPI and so no distribution expected
                      count => 0,
                      lstdate => $ilstdate,
                   );
      $group_detail_ref = \%igroup;
      $group{$key} = \%igroup;
   }
   $group_detail_ref->{count} += 1;
   $groupx{$iid} = 1;
   if ($igrpclass eq '2010') {
      $gx = $grpx{$iid};
      if (!defined $gx) {
         $grpi++;
         $gx = $grpi;
         $grp[$gx] = $iid;
         $grpx{$iid} = $gx;
         $grp_name[$gx] = $igrpname;
         $grp_sit[$gx] = {};
         $grp_grp[$gx] = {};
      }
   }
}

sub new_tgroupi {
   my ($igrpclass,$iid,$ilstdate,$iobjclass,$iobjname) = @_;
   my $key = $igrpclass . "|" . $iid . "|" . $iobjclass . "|" . $iobjname;
   my $groupi_detail_ref = $groupi{$key};
   if (!defined $groupi_detail_ref) {
      my %igroupi = (
                      grpclass => $igrpclass,      # GRPCLASS usually 2010
                      id => $iid,                   # ID is the internal group name
                      objclass => $iobjclass,
                      objname => $iobjname,
                      count => 0,
                      lstdate => $ilstdate,
                   );
      $groupi_detail_ref = \%igroupi;
      $groupi{$key} = \%igroupi;
   }
   $groupi_detail_ref->{count} += 1;
   my $gkey = $igrpclass . "|" . $iid;
   my $group_ref = $group{$gkey};
   if (!defined $group_ref) {
      $advi++;$advonline[$advi] = "TGROUPI $key unknown TGROUP ID";
      $advcode[$advi] = "DATAHEALTH1031E";
      $advimpact[$advi] = $advcx{$advcode[$advi]};
      $advsit[$advi] = $iid;
   }
   if ($groupi_detail_ref->{objclass} == 2010) {
      my $groupref = $groupi_detail_ref->{objclass};
      $gkey = "2010" . "|" . $iid;
      my $group_ref = $group{$gkey};
      if (!defined $group_ref) {
         $advi++;$advonline[$advi] = "TGROUPI $key unknown Group $iobjname";
         $advcode[$advi] = "DATAHEALTH1032E";
         $advimpact[$advi] = $advcx{$advcode[$advi]};
         $advsit[$advi] = $iobjname;
      } else {
         $group_ref->{indirect} = 1;
      }
   } elsif ($groupi_detail_ref->{objclass} == 5140) {
      my $sit1 = $groupi_detail_ref->{objname};
      if (!defined $sitx{$sit1}) {
         $advi++;$advonline[$advi] = "TGROUPI $key unknown Situation $iobjname";
         $advcode[$advi] = "DATAHEALTH1033E";
         $advimpact[$advi] = $advcx{$advcode[$advi]};
         $advsit[$advi] = $iobjname;
      }
   } else {
       die "Unknown TGROUPI objclass $groupi_detail_ref->{objclass} working on $igrpclass $iid $iobjclass $iobjname";
   }
   if ($igrpclass eq '2010') {
      if (($iobjclass eq '5140') or ($iobjclass eq '2010')) {
         $gx = $grpx{$iid};
         if (defined $gx) {
            $grp_sit[$gx]->{$iobjname} = 1 if $iobjclass eq '5140';
            $grp_grp[$gx]->{$iobjname} = 1 if $iobjclass eq '2010';
         }
      }
   }
}

sub new_tobjaccl {
   my ($iobjclass,$iobjname,$inodel,$ilstdate) = @_;
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
      $obj_lstdate[$obji] = $ilstdate;
   }
  $obj_ct[$ox] += 1;
  $tobjaccl{$iobjname} = 1;
}

sub new_tsitdesc {
   my ($isitname,$iautostart,$ilstdate,$ireev_days,$ireev_time,$isitinfo,$ipdt) = @_;
   $sx = $sitx{$isitname};
   if (!defined $sx) {
      $siti += 1;
      $sx = $siti;
      $sit[$siti] = $isitname;
      $sitx{$isitname} = $siti;
      $sit_autostart[$siti] = $iautostart;
      $sit_persist[$siti] = 1;
      $sit_pdt[$siti] = $ipdt;
      $sit_ct[$siti] = 0;
      $sit_lstdate[$siti] = $ilstdate;
      $sit_reeval[$siti] = 1;
      $sit_fullname[$siti] = "";
      $sit_psit[$siti] = $isitname;
      if ((length($ireev_days) == 0) or (length($ireev_days) > 3)) {
         $advi++;$advonline[$advi] = "Situation with invalid sampling days [$ireev_days]";
         $advcode[$advi] = "DATAHEALTH1071W";
         $advimpact[$advi] = $advcx{$advcode[$advi]};
         $advsit[$advi] = $isitname;
      }
      if (length($ireev_time) != 6){
         if ($ireev_time ne "0") {
            $advi++;$advonline[$advi] = "Situation with invalid sampling time [$ireev_time]";
            $advcode[$advi] = "DATAHEALTH1072W";
            $advimpact[$advi] = $advcx{$advcode[$advi]};
            $advsit[$advi] = $isitname;
         }
      }
      if ((length($ireev_days) >= 1) and (length($ireev_days) <= 3) ) {
         if ((length($ireev_time) >= 1) and (length($ireev_time) <= 6)) {
            $ireev_days += 0;
            $ireev_time .= "000000";                 # found some old situations with sample time "0000" so auto-extend
            $ireev_time = substr($ireev_time,0,6);
            my $reev_time_hh = 0;
            my $reev_time_mm = 0;
            my $reev_time_ss = 0;
            if ($ireev_time ne "0") {
               $reev_time_hh = substr($ireev_time,0,2);
               $reev_time_mm = substr($ireev_time,2,2);
               $reev_time_ss = substr($ireev_time,4,2);
            }
            $sit_reeval[$siti] = $ireev_days*86400 + $reev_time_hh*3600 + $reev_time_mm*60 + $reev_time_ss;   # sampling interval in seconds
         }
      }
      $isitinfo =~ /COUNT=(\d+)/;
      $sit_persist[$siti] = $1 if defined $1;
   }
  $sit_ct[$sx] += 1;
}

sub new_tname {
   my ($iid,$ilstdate,$ifullname) = @_;
   $nax = $namx{$iid};
   if (!defined $nax) {
      $nami += 1;
      $nax = $nami;
      $nam[$nami] = $iid;
      $namx{$iid} = $nami;
      $nam_fullname[$nami] = $ifullname;
      $nam_ct[$nami] = 0;
      $nam_lstdate[$nami] = $ilstdate;
   }
   $nam_ct[$nax] += 1;
   $sx = $sitx{$iid};
   if (defined $sx) {
      $sit_fullname[$sx] = $ifullname;
      $sit_psit[$sx] = $ifullname;
   }
}

# Record data from the TNODESAV table. This is the disk version of [most of] the INODESTS or node status table.
# capture node name, product, version, online status


sub new_tnodesav {
   my ($inode,$iproduct,$iversion,$io4online,$ihostaddr,$ireserved,$ithrunode,$ihostinfo,$iaffinities) = @_;
   $nsx = $nsavex{$inode};
   if (!defined $nsx) {
      $nsavei++;
      $nsx = $nsavei;
      $nsave[$nsx] = $inode;
      $nsavex{$inode} = $nsx;
      $nsave_sysmsl[$nsx] = 0;
      $nsave_product[$nsx] = $iproduct;
      $nsave_affinities[$nsx] = $iaffinities;
      if ($iversion ne "") {
         my $tversion = $iversion;
         $tversion =~ s/[0-9\.]+//g;
         if ($tversion ne "") {
            $advi++;$advonline[$advi] = "Invalid agent version [$iversion] in node $inode tnodesav";
            $advcode[$advi] = "DATAHEALTH1036E";
            $advimpact[$advi] = $advcx{$advcode[$advi]};
            $advsit[$advi] = $inode;
            $iversion = "00.00.00";
         }
      }
      $nsave_version[$nsx] = $iversion;
      $nsave_subversion[$nsx] = "";
      $nsave_hostaddr[$nsx] = $ihostaddr;
      $nsave_hostinfo[$nsx] = $ihostinfo;
      $nsave_ct[$nsx] = 0;
      $nsave_o4online[$nsx] = $io4online;
      $nsave_common[$nsx] = "";
      if (length($ireserved) == 0) {
         $nsave_temaver[$nsx] = "";
      } else {
         my @words;
         @words = split(";",$ireserved);
         $nsave_temaver[$nsx] = "";
         $nsave_common[$nsx] = "";
         # found one agent with RESERVED == A=00:ls3246;;;
         if ($#words > 0) {
            if ($words[0] ne "") {
               $nsave_subversion[$nsx] = substr($words[0],2,2);
            }
            if ($words[1] ne "") {
               $nsave_common[$nsx] = substr($words[1],2);
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
         my $arch = "";
         $ireserved =~ /:(.*?)\;/;
         $arch = $1 if defined $1;
         $tems[$tx] = $inode;
         $temsx{$inode} = $tx;
         $tems_hub[$tx] = 0;
         $tems_ct[$tx] = 0;
         $tems_ctnok[$tx] = 0;
         $tems_version[$tx] = $iversion;
         $tems_arch[$tx] = $arch;
         $tems_thrunode[$tx] = $ithrunode;
         $tems_affinities[$tx] = $iaffinities;
         $tems_sampload[$tx] = 0;
         $tems_sampsit[$tx] = 0;
         $tems_puresit[$tx] = 0;
      }
   }
   my $arch = "";
   $ireserved =~ /:(.*?)\;/;
   $arch = $1 if defined $1;
   # track the TEPS and the version
   if ($iproduct eq "CQ") {
      $tx = $tepsx{$inode};
      if (!defined $tx) {
         $tepsi += 1;
         $tx = $tepsi;
         $teps[$tx] = $inode;
         $tepsx{$inode} = $tx;
         $teps_version[$tx] = $iversion;
         $teps_arch[$tx] = $arch;
      }
   }
   # track the i/5 OS Agent and the version
   if ($arch eq "i5os") {
      my $sub_level = "00";
      $ireserved =~ /A=(\d+):/;
      $sub_level = $1 if defined $1;
      my $agt_version = $iversion . "." . $sub_level;
      my $key = $iproduct . $agt_version;
      $tx = $ka4x{$key};
      if (!defined $tx) {
         $ka4i += 1;
         $tx = $ka4i;
         $ka4[$tx] = $key;
         $ka4x{$key} = $tx;
         $ka4_product[$tx] = $iproduct;
         $ka4_version[$tx] = $agt_version;
         $ka4_version_count[$tx] = 0;
      }
      $ka4_version_count[$tx] += 1;
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

         # track uses of duplicate SYSTEM_NAME across different IP addresses
         # which can mess up Portal Client Navigator displays badly
         # ip.pipe:#172.17.117.34[10055]<NM>CNWDC4AHMAAA</NM>
         if (index($ihostaddr,"[") != -1) {
            $ihostaddr =~ /(\S+?)\[(.*)/;
#           $ihostaddr =~ /\((\S+?)\)\[(.*)/ if !defined $1;   # IPV6 style
            my $isysip = $1;
            my $hrest = $2;
            if (defined $isysip) {
               if (defined $hrest) {
                  if (index($hrest,"<NM") != -1) {
                     $hrest =~ /\<NM\>(\S+)\</;
                    my $isysname = $1;
                     if (defined $isysname) {
                        my $sysname_ref = $sysnamex{$isysname};
                        if (!defined $sysname_ref) {
                           my %sysnameref = (
                                               count => 0,
                                               ipcount => 0,
                                               sysipx => {},
                                            );
                           $sysnamex{$isysname} = \%sysnameref;
                           $sysname_ref = \%sysnameref;
                        }
                        $sysname_ref->{count} += 1;
                        my $sysip_ref = $sysname_ref->{sysipx}{$isysip};
                        if (!defined $sysip_ref) {
                           my %sysipref = (
                                             count => 0,
                                             instance => {},
                                          );
                           $sysname_ref->{sysipx}{$isysip} = \%sysipref;
                           $sysip_ref = \%sysipref;
                           $sysname_ref->{ipcount} += 1;
                        }
                        $sysip_ref->{count} += 1;
                        my %sysip_node_ref = (
                                                hostaddr => $ihostaddr,
                                                thrunode => $ithrunode,
                                                affinities => $iaffinities,
                                            );
                        $sysip_ref->{instance}{$inode} = \%sysip_node_ref;
                     }
                  }
               }
               my $ip_ref = $ipx{$isysip};
               if (!defined $ip_ref) {
                  my %ipref = (
                                 count => 0,
                                 level => {},
                                 agents => {},
                                 arch => {},
                              );
                  $ip_ref = \%ipref;
                  $ipx{$isysip}  = \%ipref;
               }
               if ($nsave_common[$nsx] ne "") {
                  my $tema_level = $nsave_common[$nsx];
                  $tema_level =~ /(\S+):(\S+)/;
                  $tema_level = $1;
                  my $tema_arch = $2;
                  if (defined $tema_level) {
                     if (!defined $ip_ref->{level}{$tema_level}) {
                        $ip_ref->{count} += 1;
                        $ip_ref->{level}{$tema_level} = 1;
                        $ip_ref->{agents}{$inode} = $tema_level;
                        $ip_ref->{arch}{$inode} = $tema_arch;
                     }
                  }
               }
            }
         }
      }
   }
}

# Record data from the TNODELST NODETYPE=V table. This is the ALIVE data which captures the thrunode

sub new_tnodelstv {
   my ($inodetype,$inodelist,$inode,$ilstdate) = @_;
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
      $nlistv_lstdate[$vlx] = $ilstdate;
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
         $magent_tems[$mx] = "";
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
       $magent_tems[$mx] = $mthrunode;
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
my ($inodetype,$inodelist,$inode,$ilstdate) = @_;
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
      $mlist_lstdate[$mlx] = $ilstdate;
      $mlist_nodelist[$mlx] = $inodelist;
      $mlist_node[$mlx] = $inode;
   }
   $mlist_ct[$mlx] += 1;

   $nlx = $nlistx{$inodelist};
   if (!defined $nlx) {
      $nlisti += 1;
      $nlx = $nlisti;
      $nlist[$nlx] = $inodelist;
      $nlistx{$inodelist} = $nlx;
   }
   $nlist_agents[$nlx]{$inode} = 1;

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


# Record data from the TEIBLOGT table.

sub new_teiblogt {
my ($igbltmstmp,$iobjname,$operation,$itable) = @_;
   my $inode = substr($iobjname,0,32);
   $inode =~ s/\s+$//;   #trim trailing whitespace
   my $ithrunode = substr($iobjname,32,32);
   $ithrunode =~ s/\s+$//;   #trim trailing whitespace

   # There are two cases we want to track
   #  $inode = managed system list, $ithrunode = system generated managed system TNODELST M type records
   #  $inode and $ithrunode = managed system    TNODELST V type records

   my $doit = 0;
   if (defined $nlistx{$inode}) {
      if ((substr($inode,0,1) eq "*") and (defined $nsavex{$ithrunode})) {
          ($inode,$ithrunode) = ($ithrunode,$inode);
          $doit = 1;
      }
   } elsif ((defined $nsavex{$inode}) and (defined $nsavex{$ithrunode})) {
       $doit = 1;
   }
   if ($doit == 1) {
      my $node_ref = $eibnodex{$inode};
      if (!defined $node_ref) {
         my %thrunoderef = ();
         my %noderef = ( count => 0,
                         thrunode => \%thrunoderef,
                       );
         $node_ref = \%noderef;
         $eibnodex{$inode} = \%noderef;
      }
      $eibnodex{$inode}->{count} += 1;
      my $thrunode_ref = $eibnodex{$inode}->{thrunode}{$ithrunode};
      if (!defined $thrunode_ref) {
         my %thrunoderef = ( count => 0,
                             gbltmstmp => [],
                           );
         $thrunode_ref = \%thrunoderef;
         $eibnodex{$inode}->{thrunode}{$ithrunode} = \%thrunoderef;
      }
      $eibnodex{$inode}->{thrunode}{$ithrunode}->{count} += 1;
      push (@{$eibnodex{$inode}->{thrunode}{$ithrunode}->{gbltmstmp}},$igbltmstmp);
   }
}


sub new_tsitstsh {
   my ($igbltmstmp,$ideltastat,$isitname,$inode,$ioriginnode,$iatomize) = @_;
   return if ($ideltastat ne "Y") and ($ideltastat ne "N");
   my $sitkey = $isitname . "|" . $iatomize;
   my $sit_ref = $eventx{$sitkey};
   if (!defined $sit_ref) {
      my %originref = ();
      my %sitref = (
                      sitname => $isitname,
                      atomize => $iatomize,
                      nodes => {},
                      count => 0,
                      open  => 0,
                      close => 0,
                      reeval => 0,                      # 0 for sampled, >0 for pure
                      start => $igbltmstmp,
                      last  => $igbltmstmp,
                      origin => \%originref,
                   );
      $sit_ref = \%sitref;
      $eventx{$sitkey} = \%sitref;
      my $sx = $sitx{$isitname};
      $sit_ref->{reeval} = $sit_reeval[$sx] if defined $sx;
   }
   $sit_ref->{nodes}{$ioriginnode} = 1;
   $sit_ref->{count} += 1;
   $sit_ref->{open} += 1 if $ideltastat eq "Y";
   $sit_ref->{close} += 1 if $ideltastat eq "N";

   if ($igbltmstmp < $sit_ref->{start}) {
      $sit_ref->{start} = $igbltmstmp;
   }
   if ($igbltmstmp > $sit_ref->{last}) {
      $sit_ref->{last} = $igbltmstmp;
   }
    if ($eventx_start == -1) {
       $eventx_start = $igbltmstmp;
       $eventx_last = $igbltmstmp;
    }
    if ($igbltmstmp < $eventx_start) {
       $eventx_start = $igbltmstmp;
    }
    if ($igbltmstmp > $eventx_last) {
       $eventx_last = $igbltmstmp;
    }
    my $okey = $ioriginnode . "|" . $inode;
    my $origin_ref =  $sit_ref->{origin}{$okey};
    if (!defined $origin_ref) {
       my %originref = (
                          node => $ioriginnode,
                          thrunode => $inode,
                          count => 0,
                          open  => 0,
                          close => 0,
                          atomize => 0,
                          start => $igbltmstmp,
                          last  => $igbltmstmp,
                       );
       $origin_ref = \%originref;
       $eventx{$sitkey}->{origin}{$okey} = \%originref;
    }
    $origin_ref->{count} += 1;
    $origin_ref->{open} += 1 if $ideltastat eq "Y";
    $origin_ref->{close} += 1 if $ideltastat eq "N";
    $origin_ref->{atomize} += 1 if $iatomize ne "";

    if ($igbltmstmp < $origin_ref->{start}) {
       $origin_ref->{start} = $igbltmstmp;
    }
    if ($igbltmstmp > $origin_ref->{last}) {
       $origin_ref->{last} = $igbltmstmp;
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
   my $ihostinfo;
   my $ireserved;
   my $ithrunode;
   my $iaffinities;

   my @ksit_data;
   my $isitname;
   my $iautostart;
   my $ireev_days;
   my $ireev_time;
   my $ipdt;
   my $isitinfo;

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

   my @kdsca_data;

   my @kcct_data;
   my $ikey;
   my $iname;

   my @kevmp_data;
   my $imap;

   my @kpcyf_data;
   my $ipcyname;

   my @kactp_data;
   my $itypestr;
   my $iactname;
   my $iactinfo;

   my @kcale_data;

   my @kovrd_data;

   my @kovri_data;
   my $iitemid;
   my $icalid;

   my @keibl_data;
   my $igbltmstmp;
   my $ioperation;
   my $itable;

   my @kstsh_data;
   my $ideltastat;
   my $ioriginnode;
   my $iatomize;

   my @kckpt_data;

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
      $nsave_offline += ($io4online eq "N");
      $nsave_online += ($io4online eq "Y");
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
      $ihostinfo = substr($oneline,413,16);
      $ihostinfo =~ s/\s+$//;   #trim trailing whitespace
      $iaffinities = substr($oneline,430,43);
      $iaffinities =~ s/\s+$//;   #trim trailing whitespace
      new_tnodesav($inode,$iproduct,$iversion,$io4online,$ihostaddr,$ireserved,$ithrunode,$ihostinfo,$iaffinities);
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
      $inode = substr($oneline,0,32);
      $inode =~ s/\s+$//;   #trim trailing whitespace
      $inodetype = substr($oneline,33,1);
      $inodelist = substr($oneline,42,32);
      $inodelist =~ s/\s+$//;   #trim trailing whitespace
      if ($inodelist eq "*HUB") {
         $inodetype = "V" if $inodetype eq " ";
         $inodelist = $inode;
      }
      next if $inodetype ne "V";
      $ilstdate = substr($oneline,75,16);
      $ilstdate =~ s/\s+$//;   #trim trailing whitespace
      new_tnodelstv($inodetype,$inodelist,$inode,$ilstdate);
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
      $ilstdate = substr($oneline,75,16);
      $ilstdate =~ s/\s+$//;   #trim trailing whitespace
      if (($inodetype eq " ") and ($inodelist eq "*HUB")) {    # *HUB has blank NODETYPE. Set to M for this calculation
         $inodetype = "M";
         $tx = $temsx{$inode};
         if (defined $tx) {
            $tems_hub[$tx] = 1;
            $hub_tems = $inode;
            $hub_tems_version = $tems_version[$tx];
         } else {
            $hub_tems_no_tnodesav = 1;
            $hub_tems = $inode;
            $hub_tems_version = "";
         }
      }
      next if $inodetype ne "M";
      new_tnodelstm($inodetype,$inodelist,$inode,$ilstdate);
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
      $ilstdate = substr($oneline,38,16);
      $ilstdate =~ s/\s+$//;   #trim trailing whitespace
      $ireev_days = substr($oneline,55,3);
      $ireev_days =~ s/\s+$//;   #trim trailing whitespace
      $ireev_time = substr($oneline,59,6);
      $ireev_time =~ s/\s+$//;   #trim trailing whitespace
      $isitinfo = substr($oneline,68,128);
      $isitinfo =~ s/\s+$//;   #trim trailing whitespace
      $ipdt = substr($oneline,197);
      $ipdt =~ s/\s+$//;   #trim trailing whitespace
      new_tsitdesc($isitname,$iautostart,$ilstdate,$ireev_days,$ireev_time,$isitinfo,$ipdt);
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
      $ilstdate = substr($oneline,33,16);
      $ilstdate =~ s/\s+$//;   #trim trailing whitespace
      $ifullname = substr($oneline,50);
      $ifullname =~ s/\s+$//;   #trim trailing whitespace
      new_tname($iid,$ilstdate,$ifullname);
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
      $ilstdate = substr($oneline,75,16);
      $ilstdate =~ s/\s+$//;   #trim trailing whitespace
      next if ($iobjclass != 5140) and ($iobjclass != 2010);
      new_tobjaccl($iobjclass,$iobjname,$inodel,$ilstdate);
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
      $ilstdate  = substr($oneline,42,16);
      $ilstdate =~ s/\s+$//;   #trim trailing whitespace
      $igrpname = substr($oneline,59);
      $igrpname =~ s/\s+$//;   #trim trailing whitespace
      new_tgroup($igrpclass,$iid,$ilstdate,$igrpname);
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
      $ilstdate  = substr($oneline,42,16);
      $ilstdate =~ s/\s+$//;   #trim trailing whitespace
      $iobjclass = substr($oneline,59,4);
      $iobjclass =~ s/\s+$//;   #trim trailing whitespace
      $iobjname = substr($oneline,68,32);
      $iobjname =~ s/\s+$//;   #trim trailing whitespace
      new_tgroupi($igrpclass,$iid,$ilstdate,$iobjclass,$iobjname);
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

   open(KDSCA, "< $opt_txt_package") || die("Could not open PACKAGE $opt_txt_package\n");
   @kdsca_data = <KDSCA>;
   close(KDSCA);

   # Count entries in PACKAGE file
   $ll = 0;
   foreach $oneline (@kdsca_data) {
      $ll += 1;
      next if $ll < 5;
      $tems_packages += 1;
   }

   open(KCCT, "< $opt_txt_cct") || die("Could not open CCT $opt_txt_cct\n");
   @kcct_data = <KCCT>;
   close(KCCT);

   # Get data for all CCT records
   $ll = 0;
   foreach $oneline (@kcct_data) {
      $ll += 1;
      next if $ll < 5;
      chop $oneline;
      $oneline .= " " x 400;
      $ikey = substr($oneline,0,32);
      $ikey =~ s/\s+$//;   #trim trailing whitespace
      $ilstdate = substr($oneline,32,16);
      $ilstdate =~ s/\s+$//;   #trim trailing whitespace
      $iname = substr($oneline,50,128);
      $iname =~ s/\s+$//;   #trim trailing whitespace
      new_cct($ikey,$ilstdate,$iname);
   }

   open(KEVMP, "< $opt_txt_evntmap") || die("Could not open EVNTMAP $opt_txt_evntmap\n");
   @kevmp_data = <KEVMP>;
   close(KEVMP);

   # Get data for all EVNTMAP records
   $ll = 0;
   foreach $oneline (@kevmp_data) {
      $ll += 1;
      next if $ll < 5;
      chop $oneline;
      $oneline .= " " x 400;
      $iid = substr($oneline,0,32);
      $iid =~ s/\s+$//;   #trim trailing whitespace
      $ilstdate = substr($oneline,32,16);
      $ilstdate =~ s/\s+$//;   #trim trailing whitespace
      $imap = substr($oneline,50,128);
      $imap =~ s/\s+$//;   #trim trailing whitespace
      new_evntmap($iid,$ilstdate,$imap);
   }

   open(KPCYF, "< $opt_txt_tpcydesc") || die("Could not open TPCYDESC $opt_txt_tpcydesc\n");
   @kpcyf_data = <KPCYF>;
   close(KPCYF);

   # Get data for all TPCYDESC records
   $ll = 0;
   foreach $oneline (@kpcyf_data) {
      $ll += 1;
      next if $ll < 5;
      chop $oneline;
      $oneline .= " " x 400;
      $ipcyname = substr($oneline,0,32);
      $ipcyname =~ s/\s+$//;   #trim trailing whitespace
      $ilstdate = substr($oneline,32,16);
      $ilstdate =~ s/\s+$//;   #trim trailing whitespace
      $iautostart = substr($oneline,50,4);
      $iautostart =~ s/\s+$//;   #trim trailing whitespace
      new_tpcydesc($ipcyname,$ilstdate,$iautostart);
   }

   open(KACTP, "< $opt_txt_tactypcy") || die("Could not open TACTYPCY $opt_txt_tactypcy\n");
   @kactp_data = <KACTP>;
   close(KACTP);

   # Get data for all TACTYPCY records
   $ll = 0;
   foreach $oneline (@kactp_data) {
      $ll += 1;
      next if $ll < 5;
      chop $oneline;
      $oneline .= " " x 400;
      $iactname = substr($oneline,0,32);
      $iactname =~ s/\s+$//;   #trim trailing whitespace
      $ipcyname = substr($oneline,33,32);
      $ipcyname =~ s/\s+$//;   #trim trailing whitespace
      $ilstdate = substr($oneline,66,16);
      $ilstdate =~ s/\s+$//;   #trim trailing whitespace
      $itypestr = substr($oneline,83,32);
      $itypestr =~ s/\s+$//;   #trim trailing whitespace
      $iactinfo = substr($oneline,116,252);
      $iactinfo =~ s/\s+$//;   #trim trailing whitespace
      new_tactypcy($iactname,$ipcyname,$ilstdate,$itypestr,$iactinfo);
   }

   open(KCALE, "< $opt_txt_tcalendar") || die("Could not open TCALENDAR $opt_txt_tcalendar\n");
   @kcale_data = <KCALE>;
   close(KCALE);
   # Get data for all TCALENDAR records
   $ll = 0;
   foreach $oneline (@kcale_data) {
      $ll += 1;
      next if $ll < 5;
      chop $oneline;
      $oneline .= " " x 400;
      $iid = substr($oneline,0,32);
      $iid =~ s/\s+$//;   #trim trailing whitespace
      $ilstdate = substr($oneline,33,16);
      $ilstdate =~ s/\s+$//;   #trim trailing whitespace
      $iname = substr($oneline,50,256);
      $iname =~ s/\s+$//;   #trim trailing whitespace
      new_tcalendar($iid,$ilstdate,$iname);
   }

   open(KOVRD, "< $opt_txt_toverride") || die("Could not open TOVERRIDE $opt_txt_toverride\n");
   @kovrd_data = <KOVRD>;
   close(KOVRD);
   # Get data for all TOVERRIDE records
   $ll = 0;
   foreach $oneline (@kovrd_data) {
      $ll += 1;
      next if $ll < 5;
      chop $oneline;
      $oneline .= " " x 400;
      $iid = substr($oneline,0,32);
      $iid =~ s/\s+$//;   #trim trailing whitespace
      $ilstdate = substr($oneline,33,16);
      $ilstdate =~ s/\s+$//;   #trim trailing whitespace
      $isitname = substr($oneline,50,32);
      $isitname =~ s/\s+$//;   #trim trailing whitespace
      new_toverride($iid,$ilstdate,$isitname);
   }

   open(KOVRI, "< $opt_txt_toveritem") || die("Could not open TOVERITEM $opt_txt_toveritem\n");
   @kovri_data = <KOVRI>;
   close(KOVRI);
   # Get data for all TOVERITEM records
   $ll = 0;
   foreach $oneline (@kovri_data) {
      $ll += 1;
      next if $ll < 5;
      chop $oneline;
      $oneline .= " " x 400;
      $iid = substr($oneline,0,32);
      $iid =~ s/\s+$//;   #trim trailing whitespace
      $ilstdate = substr($oneline,33,16);
      $ilstdate =~ s/\s+$//;   #trim trailing whitespace
      $iitemid = substr($oneline,50,32);
      $iitemid =~ s/\s+$//;   #trim trailing whitespace
      $icalid  = substr($oneline,83,32);
      $icalid  =~ s/\s+$//;   #trim trailing whitespace
      new_toveritem($iid,$ilstdate,$iitemid,$icalid);
   }

   open(KEIBL, "< $opt_txt_teiblogt") || die("Could not open TEIBLOGT $opt_txt_teiblogt\n");
   @keibl_data = <KEIBL>;
   close(KEIBL);
   # Get data for all TEIBLOGT records
   $ll = 0;
   foreach $oneline (@keibl_data) {
      $ll += 1;
      next if $ll < 5;
      chop $oneline;
      $oneline .= " " x 400;
      $igbltmstmp = substr($oneline,0,16);
      $igbltmstmp =~ s/\s+$//;   #trim trailing whitespace
      $iobjname = substr($oneline,17,160);
      $iobjname =~ s/\s+$//;   #trim trailing whitespace
      $ioperation = substr($oneline,178,1);
      $ioperation =~ s/\s+$//;   #trim trailing whitespace
      $itable = substr($oneline,188,4);
      $itable =~ s/\s+$//;   #trim trailing whitespace
      next if $ioperation ne "I";
      next if $itable ne "5529";
      new_teiblogt($igbltmstmp,$iobjname,$ioperation,$itable);
   }

   open(KSTSH, "< $opt_txt_tsitstsh") || die("Could not open TSITSTSH $opt_txt_tsitstsh\n");
   @kstsh_data = <KSTSH>;
   close(KSTSH);
   # Get data for all TSITSTSH records
   $ll = 0;
   foreach $oneline (@kstsh_data) {
      $ll += 1;
      next if $ll < 5;
#print STDERR "working on line $ll\n";
      chop $oneline;
      $oneline .= " " x 400;
      $igbltmstmp = substr($oneline,0,16);
      $igbltmstmp =~ s/\s+$//;   #trim trailing whitespace
      next if substr($igbltmstmp,0,1) ne "1";
      $ideltastat = substr($oneline,17,1);
      $ideltastat =~ s/\s+$//;   #trim trailing whitespace
      $isitname = substr($oneline,19,32);
      $isitname =~ s/\s+$//;   #trim trailing whitespace
      $inode = substr($oneline,52,32);
      $inode =~ s/\s+$//;   #trim trailing whitespace
      $ioriginnode = substr($oneline,85,32);
      $ioriginnode =~ s/\s+$//;   #trim trailing whitespace
      $iatomize = substr($oneline,118,128);
      $iatomize =~ s/\s+$//;   #trim trailing whitespace
      new_tsitstsh($igbltmstmp,$ideltastat,$isitname,$inode,$ioriginnode,$iatomize);
   }

   open(KCKPT, "< $opt_txt_tcheckpt") || die("Could not open TCKPT $opt_txt_tcheckpt\n");
   @kckpt_data = <KCKPT>;
   close(KCKPT);
   # Get data for all TCKPT records
   $ll = 0;
   foreach $oneline (@kckpt_data) {
      $ll += 1;
      next if $ll < 4;
      chop $oneline;
      $oneline .= " " x 400;
      $iname = substr($oneline,0,32);
      $ireserved = substr($oneline,33,48);
      $iname =~ s/\s+$//;   #trim trailing whitespace
      $ireserved =~ s/\s+$//;   #trim trailing whitespace
      next if $iname ne "M:STAGEII";
      $opt_fto = $ireserved;
   }

}

# There may be a better way to do this, but this was clear and worked.
# The input $lcount must be matched up to the number of columns
# SELECTED in the SQL.
# [1]  OGRP_59B815CE8A3F4403  OGRP_6F783DF5FF904988  2010  2010

# Parse for KfwSQLClient SQL capture version 0.95000

sub parse_lst {
  my ($lcount,$inline,$cref) = @_;            # count of desired chunks and the input line
  my @retlist = ();                     # an array of strings to return
  my $chunk = "";                       # One chunk
  my $oct = 1;                          # output chunk count
  my $rest;                             # the rest of the line to process
  $inline =~ /\]\s*(.*)/;               # skip by [NNN]  field
  $rest = " " . $1 . "        ";
  my $fixed;
  my $lenrest = length($rest);          # length of $rest string
  my $restpos = 0;                      # postion studied in the $rest string
  my $nextpos = 0;                      # floating next position in $rest string

  # KwfSQLClient logic wraps each column with a leading and trailing blank
  # simple case:  <blank>data<blank><blank>data1<blank>
  # data with embedded blank: <blank>data<blank>data<blank><data1>data1<blank>
  #     every separator is always at least two blanks, so a single blank is always embedded
  # data with trailing blank: <blank>data<blank><blank><blank>data1<blank>
  #     given the rules has to be leading or trailing blank and chose trailing on data
  # data followed by a null data item: <blank>data<blank><blank><blank><blank>
  #                                                            ||
  # data with longer then two blanks embedded must be placed on end, or handled with a cref hash.
  #
  # $restpos always points within the string, always on the blank delimiter at the end
  #
  # The %cref hash specifies chunks that are of guaranteed fixed size... passed in by caller
  while ($restpos < $lenrest) {
     $fixed = $cref->{$oct};                   #
     if (defined $fixed) {
        $chunk = substr($rest,$restpos+1,$fixed);
        push @retlist, $chunk;                 # record null data chunk
        $restpos += 2 + $fixed;
        $chunk = "";
        $oct += 1;
        next;
     }
     if ($oct >= $lcount) {                                   # handle last item
        $chunk = substr($rest,$restpos+1);
        $chunk =~ s/\s+$//;                    # strip trailing blanks
        push @retlist, $chunk;                 # record last data chunk
        last;
     }
     if ((substr($rest,$restpos,3) eq "   ") and (substr($rest,$restpos+3,1) ne " ")) {          # following null entry
        $chunk = "";
        $oct += 1;
        push @retlist, $chunk;                 # record null data chunk
        $restpos += 2;
        next;
     }
     if ((substr($rest,$restpos,2) eq "  ") and (substr($rest,$restpos+2,1) ne " ")) {            # trailing blank on previous chunk so ignore
        $restpos += 1;
        next;
     }

     $nextpos = index($rest," ",$restpos+1);
     if (substr($rest,$nextpos,2) eq "  ") {
        $chunk .= substr($rest,$restpos+1,$nextpos-$restpos-1);
        push @retlist, $chunk;                 # record new chunk
        $chunk = "";                           # prepare for new chunk
        $oct += 1;
        $restpos = $nextpos + 1;
     } else {
        $chunk .= substr($rest,$restpos+1,$nextpos-$restpos); # record new chunk fragment
        $restpos = $nextpos;
     }
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
   my $ihostinfo;
   my $io4online;
   my $ireserved;
   my $ithrunode;
   my $iaffinities;

   my @ksit_data;
   my $isitname;
   my $iautostart;
   my $ireev_days;
   my $ireev_time;
   my $isitinfo;
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

   my @kcct_data;
   my $ikey;
   my $iname;

   my @kevmp_data;
   my $imap;

   my @kpcyf_data;
   my $ipcyname;

   my @kactp_data;
   my $itypestr;
   my $iactname;
   my $iactinfo;

   my @kcale_data;

   my @kovrd_data;

   my @kovri_data;
   my $iitemid;
   my $icalid;

   my @keibl_data;
   my $igbltmstmp;
   my $ioperation;
   my $itable;

   my @kstsh_data;
   my $ideltastat;
   my $ioriginnode;
   my $iatomize;

   my @kckpt_data;

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
      next if substr($oneline,0,1) ne "[";                    # Look for starting point
      chop $oneline;
      # KfwSQLClient /e "SELECT NODE,O4ONLINE,PRODUCT,VERSION,HOSTADDR,RESERVED,THRUNODE,AFFINITIES FROM O4SRV.TNODESAV" >QA1DNSAV.DB.LST
      #[1]  BNSF:TOIFVCTR2PW:VM  Y  VM  06.22.01  ip.spipe:#10.121.54.28[11853]<NM>TOIFVCTR2PW</NM>  A=00:WIX64;C=06.22.09.00:WIX64;G=06.22.09.00:WINNT;  REMOTE_catrste050bnsxa  000100000000000000000000000000000G0003yw0a7
      ($inode,$io4online,$iproduct,$iversion,$ihostaddr,$ireserved,$ithrunode,$ihostinfo,$iaffinities) = parse_lst(9,$oneline);
      $inode =~ s/\s+$//;   #trim trailing whitespace
      $iproduct =~ s/\s+$//;   #trim trailing whitespace
      $iversion =~ s/\s+$//;   #trim trailing whitespace
      $io4online =~ s/\s+$//;   #trim trailing whitespace
      $ihostaddr =~ s/\s+$//;   #trim trailing whitespace
      $ireserved =~ s/\s+$//;   #trim trailing whitespace
      $ithrunode =~ s/\s+$//;   #trim trailing whitespace
      $ihostinfo =~ s/\s+$//;   #trim trailing whitespace
      $iaffinities =~ s/\s+$//;   #trim trailing whitespace
      $nsave_offline += ($io4online eq "N");
      $nsave_online += ($io4online eq "Y");
      new_tnodesav($inode,$iproduct,$iversion,$io4online,$ihostaddr,$ireserved,$ithrunode,$ihostinfo,$iaffinities);
   }

   open(KLST, "<$opt_lst_tnodelst") || die("Could not open TNODELST $opt_lst_tnodelst\n");
   @klst_data = <KLST>;
   close(KLST);

   # Get data for all TNODELST type V records
   $ll = 0;
   foreach $oneline (@klst_data) {
      $ll += 1;
      next if substr($oneline,0,1) ne "[";                    # Look for starting point
      chop $oneline;
      # KfwSQLClient /e "SELECT NODE,NODETYPE,NODELIST,LSTDATE FROM O4SRV.TNODELST" >QA1CNODL.DB.LST
      ($inode,$inodetype,$inodelist,$ilstdate) = parse_lst(4,$oneline);
      next if $inodetype ne "V";
      new_tnodelstv($inodetype,$inodelist,$inode,$ilstdate);
   }
   fill_tnodelstv();

   # Get data for all TNODELST type M records
   $ll = 0;
   foreach $oneline (@klst_data) {
      $ll += 1;
      next if substr($oneline,0,1) ne "[";                    # Look for starting point
      chop $oneline;
      # KfwSQLClient /e "SELECT NODE,NODETYPE,NODELIST,LSTDATE FROM O4SRV.TNODELST" >QA1CNODL.DB.LST
      ($inode,$inodetype,$inodelist,$ilstdate) = parse_lst(4,$oneline);
      $inodelist =~ s/\s+$//;   #trim trailing whitespace
      $inode =~ s/\s+$//;   #trim trailing whitespace
      if (($inodetype eq "") and ($inodelist eq "*HUB")) {    # *HUB has blank NODETYPE. Set to M for this calculation
         $inodetype = "M";
         $tx = $temsx{$inode};
         if (defined $tx) {
            $tems_hub[$tx] = 1;
            $hub_tems = $inode;
            $hub_tems_version = $tems_version[$tx];
         } else {
            $hub_tems_no_tnodesav = 1;
            $hub_tems = $inode;
            $hub_tems_version = "";
         }
      }
      next if $inodetype ne "M";
      new_tnodelstm($inodetype,$inodelist,$inode,$ilstdate);
   }
   open(KSIT, "< $opt_lst_tsitdesc") || die("Could not open TSITDESC $opt_lst_tsitdesc\n");
   @ksit_data = <KSIT>;
   close(KSIT);

   # Get data for all TSITDESC records
   $ll = 0;
   foreach $oneline (@ksit_data) {
      $ll += 1;
      next if substr($oneline,0,1) ne "[";                    # Look for starting point
      chop $oneline;
      # KfwSQLClient /e "SELECT SITNAME,AUTOSTART,LSTDATE,REEV_DAYS,REEV_TIME,SITINFO,PDT FROM O4SRV.TSITDESC" >QA1CSITF.DB.LST
$DB::single=2;
      ($isitname,$iautostart,$ilstdate,$ireev_days,$ireev_time,$isitinfo,$ipdt) = parse_lst(7,$oneline);
      $isitname =~ s/\s+$//;   #trim trailing whitespace
      $iautostart =~ s/\s+$//;   #trim trailing whitespace
$DB::single=2;
      $isitinfo =~ s/\s+$//;   #trim trailing whitespace
      $ipdt = substr($oneline,33,1);  #???#
      new_tsitdesc($isitname,$iautostart,$ilstdate,$ireev_days,$ireev_time,$isitinfo,$ipdt);
   }

   open(KNAM, "< $opt_lst_tname") || die("Could not open TNAME $opt_lst_tname\n");
   @knam_data = <KNAM>;
   close(KNAM);

   # Get data for all TNAME
   $ll = 0;
   foreach $oneline (@knam_data) {
      $ll += 1;
      next if substr($oneline,0,1) ne "[";                    # Look for starting point
      chop $oneline;
      # KfwSQLClient /e "SELECT ID,LSTDATE,FULLNAME FROM O4SRV.TNAME" >QA1DNAME.DB.LST
      ($iid,$ilstdate,$ifullname) = parse_lst(3,$oneline);
      new_tname($iid,$ilstdate,$ifullname);
   }

   open(KOBJ, "< $opt_lst_tobjaccl") || die("Could not open TOBJACCL $opt_lst_tobjaccl\n");
   @kobj_data = <KOBJ>;
   close(KOBJ);

   # Get data for all TOBJACCL records
   $ll = 0;
   foreach $oneline (@kobj_data) {
      $ll += 1;
      next if substr($oneline,0,1) ne "[";                    # Look for starting point
      chop $oneline;
      # KfwSQLClient /e "SELECT OBJCLASS,OBJNAME,NODEL,LSTDATE FROM O4SRV.TOBJACCL" >QA1DOBJA.DB.LST
      ($iobjclass,$iobjname,$inodel,$ilstdate) = parse_lst(4,$oneline);
      next if ($iobjclass != 5140) and ($iobjclass != 2010);
      new_tobjaccl($iobjclass,$iobjname,$inodel,$ilstdate);
   }

   open(KGRP, "< $opt_lst_tgroup") || die("Could not open TGROUP $opt_lst_tgroup\n");
   @kgrp_data = <KGRP>;
   close(KGRP);

   # Get data for all TGROUP records
   $ll = 0;
   foreach $oneline (@kgrp_data) {
      $ll += 1;
      next if substr($oneline,0,1) ne "[";                    # Look for starting point
      chop $oneline;
      # KfwSQLClient /e "SELECT GRPCLASS,ID,LSTDATE,GRPNAME FROM O4SRV.TGROUP" >QA1DGRPA.DB.LST
      ($igrpclass,$iid,$ilstdate,$igrpname) = parse_lst(4,$oneline);
      new_tgroup($igrpclass,$iid,$ilstdate,$igrpname);
   }

   open(KGRPI, "< $opt_lst_tgroupi") || die("Could not open TGROUPI $opt_lst_tgroupi\n");
   @kgrpi_data = <KGRPI>;
   close(KGRPI);

   # Get data for all TGROUPI records
   $ll = 0;
   foreach $oneline (@kgrpi_data) {
      $ll += 1;
      next if substr($oneline,0,1) ne "[";                    # Look for starting point
      chop $oneline;
      # KfwSQLClient /e "SELECT GRPCLASS,ID,LSTDATE,OBJCLASS,OBJNAME FROM O4SRV.TGROUPI" >QA1DGRPI.DB.LST
      ($igrpclass,$iid,$ilstdate,$iobjclass,$iobjname) = parse_lst(5,$oneline);
      new_tgroupi($igrpclass,$iid,$ilstdate,$iobjclass,$iobjname);
   }

   open(KEVSR, "< $opt_lst_evntserver") || die("Could not open EVNTSERVER $opt_lst_evntserver\n");
   @kevsr_data = <KEVSR>;
   close(KEVSR);

   # Get data for all EVNTSERVER records
   $ll = 0;
   foreach $oneline (@kevsr_data) {
      $ll += 1;
      next if substr($oneline,0,1) ne "[";                    # Look for starting point
      chop $oneline;
      # KfwSQLClient /e "SELECT ID,LSTDATE,LSTUSRPRF FROM O4SRV.EVNTSERVER" >QA1DEVSR.DB.LST
      ($iid,$ilstdate,$ilstusrprf) = parse_lst(3,$oneline);
      new_evntserver($iid,$ilstdate,$ilstusrprf);
   }

#   open(KDSCA, "< $opt_lst_package") || die("Could not open PACKAGE $opt_lst_package\n");
#   @kdsca_data = <KDSCA>;
#   close(KDSCA);

   # Count entries in PACKAGE file
   # for LST type files set $tems_packages set to zero since otherwise unknown
   # leave logic in case it can be performed later

   $tems_packages = 0;

#  open(KDSCA, "< $opt_lst_package") || die("Could not open PACKAGE $opt_lst_package\n");
#  @kdsca_data = <KDSCA>;
#  close(KDSCA);
#
#  # Count entries in PACKAGE file
#  $ll = 0;
#  foreach $oneline (@kdsca_data) {
#     $ll += 1;
#     next if substr($oneline,0,10) eq "KCIIN0187I";      # A Linux/Unix first line
#     $tems_packages += 1;
#  }

   open(KCCT, "< $opt_lst_cct") || die("Could not open CCT $opt_lst_cct\n");
   @kcct_data = <KCCT>;
   close(KCCT);

   $ll = 0;
   foreach $oneline (@kcct_data) {
      $ll += 1;
      next if substr($oneline,0,1) ne "[";                    # Look for starting point
      chop $oneline;
      # KfwSQLClient /e "SELECT KEY,LSTDATE,NAME FROM O4SRV.CCT" >QA1DCCT.DB.LST
      ($ikey,$ilstdate,$iname) = parse_lst(3,$oneline);
      new_cct($ikey,$ilstdate,$iname);
   }

   open(KEVMP, "< $opt_lst_evntmap") || die("Could not open EVNTMAP $opt_lst_evntmap\n");
   @kevmp_data = <KEVMP>;
   close(KEVMP);

   # Get data for all EVNTMAP records
   $ll = 0;
   foreach $oneline (@kevmp_data) {
      $ll += 1;
      next if substr($oneline,0,1) ne "[";                    # Look for starting point
      chop $oneline;
      # KfwSQLClient /e "SELECT ID,LSTDATE,MAP FROM O4SRV.EVNTMAP" >QA1DEVMP.DB.LST
      ($iid,$ilstdate,$imap) = parse_lst(3,$oneline);
      new_evntmap($iid,$ilstdate,$imap);
   }

   open(KPCYF, "< $opt_lst_tpcydesc") || die("Could not open TPCYDESC $opt_lst_tpcydesc\n");
   @kpcyf_data = <KPCYF>;
   close(KPCYF);

   # Get data for all TPCYDESC records
   $ll = 0;
   foreach $oneline (@kpcyf_data) {
      $ll += 1;
      next if substr($oneline,0,1) ne "[";                    # Look for starting point
      chop $oneline;
      $oneline .= " " x 400;
      # KfwSQLClient /e "SELECT PCYNAME,LSTDATE FROM O4SRV.TPCYDESC" >QA1DPCYF.DB.LST
      ($ipcyname,$ilstdate,$iautostart) = parse_lst(3,$oneline);
      new_tpcydesc($ipcyname,$ilstdate,$iautostart);
   }

   open(KACTP, "< $opt_lst_tactypcy") || die("Could not open TACTYPCY $opt_lst_tactypcy\n");
   @kactp_data = <KACTP>;
   close(KACTP);

   # Get data for all TACTYPCY records
   $ll = 0;
   foreach $oneline (@kactp_data) {
      $ll += 1;
      next if substr($oneline,0,1) ne "[";                    # Look for starting point
      chop $oneline;
      $oneline .= " " x 400;
      # KfwSQLClient /e "SELECT ACTNAME,PCYNAME,LSTDATE,TYPESTR,ACTINFO FROM O4SRV.TACTYPCY" >QA1DACTP.DB.LST
      ($iactname,$ipcyname,$ilstdate,$itypestr,$iactinfo) = parse_lst(5,$oneline);
      new_tactypcy($iactname,$ipcyname,$ilstdate,$itypestr,$iactinfo);
   }

   open(KCALE, "< $opt_lst_tcalendar") || die("Could not open TCALENDAR $opt_lst_tcalendar\n");
   @kcale_data = <KCALE>;
   close(KCALE);
   # Get data for all TCALENDAR records
   $ll = 0;
   foreach $oneline (@kcale_data) {
      $ll += 1;
      next if substr($oneline,0,1) ne "[";                    # Look for starting point
      chop $oneline;
      $oneline .= " " x 400;
      # KfwSQLClient /e "SELECT ID,LSTDATE,NAME FROM O4SRV.TCALENDAR" >QA1DCALE.DB.LST
      ($iid,$ilstdate,$iname) = parse_lst(3,$oneline);
      new_tcalendar($iid,$ilstdate,$iname);
   }

   open(KOVRD, "< $opt_lst_toverride") || die("Could not open TOVERRIDE $opt_lst_toverride\n");
   @kovrd_data = <KOVRD>;
   close(KOVRD);
   # Get data for all TOVERRIDE records
   $ll = 0;
   foreach $oneline (@kovrd_data) {
      $ll += 1;
      next if substr($oneline,0,1) ne "[";                    # Look for starting point
      chop $oneline;
      $oneline .= " " x 400;
      # KfwSQLClient /e "SELECT ID,LSTDATE,SITNAME FROM O4SRV.TOVERRIDE" >QA1DOVRD.DB.LST
      ($iid,$ilstdate,$isitname) = parse_lst(3,$oneline);
      new_toverride($iid,$ilstdate,$isitname);
   }

   open(KOVRI, "< $opt_lst_toveritem") || die("Could not open TOVERITEM $opt_lst_toveritem\n");
   @kovri_data = <KOVRI>;
   close(KOVRI);
   # Get data for all TOVERITEM records
   $ll = 0;
   foreach $oneline (@kovri_data) {
      $ll += 1;
      next if substr($oneline,0,1) ne "[";                    # Look for starting point
      chop $oneline;
      $oneline .= " " x 400;
      # KfwSQLClient /e "SELECT ID,LSTDATE,ITEMID,CALID FROM O4SRV.TOVERITEM" >QA1DOVRI.DB.LST
      ($iid,$ilstdate,$iitemid,$icalid) = parse_lst(4,$oneline);
      new_toveritem($iid,$ilstdate,$iitemid,$icalid);
   }

   open(KEIBL, "< $opt_lst_teiblogt") || die("Could not open TEIBLOGT $opt_lst_teiblogt\n");
   @keibl_data = <KEIBL>;
   close(KEIBL);
   # Get data for all TEIBLOGT records
   $ll = 0;
   foreach $oneline (@keibl_data) {
      $ll += 1;
      next if substr($oneline,0,1) ne "[";                    # Look for starting point
      chop $oneline;
      $oneline .= " " x 400;
      ($igbltmstmp,$iobjname,$ioperation,$itable) = parse_lst(4,$oneline);
      next if $ioperation ne "I";
      next if $itable != 5529;
      new_teiblogt($igbltmstmp,$iobjname,$ioperation,$itable);
   }

   open(KSTSH, "< $opt_lst_tsitstsh") || die("Could not open TSITSTSH $opt_lst_tsitstsh\n");
   @kstsh_data = <KSTSH>;
   close(KSTSH);
   # Get data for all TSITSTSH records
   $ll = 0;
   foreach $oneline (@kstsh_data) {
      $ll += 1;
      next if substr($oneline,0,1) ne "[";                    # Look for starting point
      chop $oneline;
      $oneline .= " " x 400;
      ($igbltmstmp,$ideltastat,$isitname,$inode,$ioriginnode,$iatomize) = parse_lst(6,$oneline);
      new_tsitstsh($igbltmstmp,$ideltastat,$isitname,$inode,$ioriginnode,$iatomize);
   }

   open(KCKPT, "< $opt_lst_tcheckpt") || die("Could not open TCHECKPT $opt_lst_tcheckpt\n");
   @kckpt_data = <KCKPT>;
   close(KCKPT);
   # Get data for all TCKPT records
   $ll = 0;
   foreach $oneline (@kckpt_data) {
      $ll += 1;
      next if substr($oneline,0,1) ne "[";                    # Look for starting point
      chop $oneline;
      $oneline .= " " x 400;
      ($iname,$ireserved) = parse_lst(2,$oneline);
      $iname =~ s/\s+$//;   #trim trailing whitespace
      $ireserved =~ s/\s+$//;   #trim trailing whitespace
      next if $iname ne "M:STAGEII";
      $opt_fto = $ireserved;
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
      } elsif ( $ARGV[0] eq "-event") {
         shift(@ARGV);
         $opt_event = 1;
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
         chop $oneline;
         next if (substr($oneline,0,1) eq "#");  # skip comment line
         @words = split(" ",$oneline);
         next if $#words == -1;                  # skip blank line
          if ($#words == 0) {                         # single word parameters
            if ($words[0] eq "verbose") {$opt_v = 1;}
            if ($words[0] eq "event") {$opt_event = 1;}
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
   if (!defined $opt_event) {$opt_event=0;}                    # default event report off
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
      $opt_txt_package = $opt_workpath . "QA1CDSCA.DB.TXT";
      $opt_txt_cct     = $opt_workpath . "QA1DCCT.DB.TXT";
      $opt_txt_evntmap = $opt_workpath . "QA1DEVMP.DB.TXT";
      $opt_txt_tpcydesc = $opt_workpath . "QA1DPCYF.DB.TXT";
      $opt_txt_tactypcy = $opt_workpath . "QA1DACTP.DB.TXT";
      $opt_txt_tcalendar = $opt_workpath . "QA1DCALE.DB.TXT";
      $opt_txt_toverride = $opt_workpath . "QA1DOVRD.DB.TXT";
      $opt_txt_toveritem = $opt_workpath . "QA1DOVRI.DB.TXT";
      $opt_txt_teiblogt = $opt_workpath . "QA1CEIBL.DB.TXT";
      $opt_txt_tsitstsh = $opt_workpath . "QA1CSTSH.DB.TXT";
      $opt_txt_tcheckpt = $opt_workpath . "QA1CCKPT.DB.TXT";
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
      $opt_lst_cct = $opt_workpath . "QA1DCCT.DB.LST";
      $opt_lst_evntmap = $opt_workpath . "QA1DEVMP.DB.LST";
      $opt_lst_tpcydesc = $opt_workpath . "QA1DPCYF.DB.LST";
      $opt_lst_tactypcy = $opt_workpath . "QA1DACTP.DB.LST";
      $opt_lst_tcalendar = $opt_workpath . "QA1DCALE.DB.LST";
      $opt_lst_toverride = $opt_workpath . "QA1DOVRD.DB.LST";
      $opt_lst_toveritem = $opt_workpath . "QA1DOVRI.DB.LST";
      $opt_lst_teiblogt = $opt_workpath . "QA1CEIBL.DB.LST";
      $opt_lst_tsitstsh = $opt_workpath . "QA1CSTSH.DB.LST";
      $opt_lst_tcheckpt = $opt_workpath . "QA1CCKPT.DB.LST";
   }
   $opt_vndx_fn = $opt_workpath . "QA1DNSAV.DB.VNDX";
   $opt_mndx_fn = $opt_workpath . "QA1DNSAV.DB.MNDX";
   $opt_miss_fn = $opt_workpath . "MISSING.SQL";

my ($isec,$imin,$ihour,$imday,$imon,$iyear,$iwday,$iyday,$iisdst) = localtime(time()+86400);
   $tlstdate = "1";
   $tlstdate .= substr($iyear,-2,2);
   $imon += 1;
   $imon = "00" . $imon;
   $tlstdate .= substr($imon,-2,2);
   $imon = "00" . $imday;
   $tlstdate .= substr($imday,-2,2);
   $ihour = "00" . $ihour;
   $tlstdate .= substr($ihour,-2,2);
   $imin = "00" . $imin;
   $tlstdate .= substr($imin,-2,2);
   $isec = "00" . $isec;
   $tlstdate .= substr($isec,-2,2);
   $tlstdate .= "000";

   if ($opt_dpr == 1) {
#     my $module = "Data::Dumper";
#     eval {load $module};
#     if ($@) {
#        print STDERR "Cannot load Data::Dumper - ignoring -dpr option\n";
#        $opt_dpr = 0;
#     }
      $opt_dpr = 0;
   }

   if (($opt_txt + $opt_lst) == 0) {
      $opt_txt = 1 if -e $opt_txt_tnodelst;
      $opt_lst = 1 if -e $opt_lst_tnodelst;
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
sub get_epoch {
   use POSIX;
   my $itm_stamp = shift;
   my $unixtime = $epochx{$itm_stamp};
   if (!defined $unixtime) {
     ( my $iyy, my $imo, my $idd, my $ihh, my $imm, my $iss ) =  unpack( "A2 A2 A2 A2 A2 A2", substr( $itm_stamp, 1 ) );
      my $wday = 0;
      my $yday = 0;
      $iyy += 100;
      $unixtime = mktime ($iss, $imm, $ihh, $idd, $imo, $iyy, $wday, $yday);
   }
   return $unixtime;
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
# 0.86000  : Check for TNODELST NODETYPE=V thrunode missing from TNODESAV
# 0.87000  : Add TOBJACCL, TGROUP. TGROUPI checking first stage
# 0.88000  : Identify TEMA version < Agent version, adjust impacts, add more missing tests, change some impacts
# 0.89000  : record TEMS version number
# 0.90000  : detect case where *HUB is missing from TNODELST NODETYPE=M records
# 0.91000  : Check EVNTSERVR for blank LSTDATE and LSTUSRPRF
# 0.92000  : Check Virtual Hub Table counts against TSITDESC UADVISOR AUTOSTART settings
# 0.93000  : Check for invalid TSITDESC.LSTDATE values
# 0.94000  : Check IZ76410 TEMA problem case
# 0.95000  : Refine check for lower level TEMAs
#          : Add summary for TEMA Deficit levels, auto-detect TXT and LST options
#          : Add hub version and fraction TEMA deficit to one line summary for PMR
# 0.96000  : Add check for number of packages close to failure point
# 0.97000  : Full review of TEMA APARs and levels after ITM 6.1 FP6 readme found
# 0.98000  : Reconcile -lst logic
#          : Change 1043E warning for cases where agent is release higher then TEMS
# 0.99000  : Fix deficit% in REFIC line
# 1.00000  : Parse LST files better
#          : Add 1049W/1050W/1051W/1052W to warn of node/nodelist names with embedded blanks
# 1.01000  : Monitor LSTDATE against future dates
#          : Add checking of the rest of the FTO synchronized tables
# 1.02000  : Long sampling interval
# 1.03000  : Correct parse_lst issues versus capture SQL TNAME and TPCYDESC issues
# 1.04000  : Fix Workflow Policy checks to warn on autostart *NO at lower impact, correct TSITDESC -lst capture
# 1.05000  : Improved parse_lst logic
# 1.06000  : Add check for APAR IV50167
# 1.07000  : Improve agent/tema version check - reduce false warnings
#          : Add TEMS architecture
# 1.08000  : Improve APAR deficit calculation, ignore A4 tema version 06.20.20
# 1.09000  : Dislay Days/APAR in deficit calculations
# 1.10000  : Handle divide by zero case when no agents backlevel
# 1.11000  : Add ITM 630 FP5 APARs for TEMA deficit report
# 1.12000  : Add top 10 changed situations
# 1.13000  : record mulitple TEIBLOGT inserts of same object, same day?
# 1.14000  : for multiple inserts, report on counts >= mode of frequency
#            Add report of TEPS version and architecture
# 1.15000  : Add report for i/5 agent levels
# 1.16000  : Add general i5os reports, not just OS Agent
# 1.17000  : Detect FTO hub TEMS at different maintenance levels
#          : Alert on some sampling date/time issues
# 1.18000  : parse_lst handle null chunks correctly
#          : better report on possible duplicate agents, screen TNODELST for just M records
# 1.20000  : Report on Situation Flippers and Fireflys
# 1.21000  : Add TEMA APARs from ITM 630 FP6
# 1.22000  : Reduce some advisory impact levels
#          : correct some titles and add some event related times
# 1.23000  : Handle CF/:CONFIG differently since managed system does not use a TEMA
# 1.24000  : Correct for different Windows KfwSQLClient output formats
# 1.25000  : Handle KfwSQLClient output better
# 1.26000  : Advisory on missing MQ hostname qualifier
# 1.27000  : Calculate rate of event arrivals
#          : parse_lst 0.95000
# 1.28000  : Advisory on duplicate SYSTEM NAMES
#          : Advisory when ::CONFIG agents not connected to hub TEMS.
# 1.29000  : Advisory when CF is on remotes or in FTO environment
#          : Advisory when WPA not configured to hub TEMS
# 1.30000  : Advisory when agent has invalid affinities
# 1.31000  : Add more information on rapidly occuring situation events
# 1.32000  : Add FP7 data
# 1.33000  : end End of Service alerts and report
# 1.34000  : Add advisory for ghost situations, event status history even though deleted situation
# 1.35000  : Eliminate doubled line
#          : advisory on IV18016 case
#          : add advisory explanations to report
#          : add advisories related to too many MS_Offline type situations
#          : Do not do advisory on Sampling Time "0"
#          : Restructure report sequence so advisory comes a just after TEMS summary
# 1.36000  : Report on situation derived dataserver workload
#          : Add advisory on KDEB_INTERFACELIST APAR level issue
#          : Add two advisoreies on too many situations clogging up TEMS startup
#          : Move Agent in APAR danger details to trailing reports
#          : Add advisory on multiple TEMA levels on one system
#          : Reduce impact of DATAHEALTH1023 to 0, more annoyance than actual issue
# 1.37000  : Better logic on multiple TEMA report
# 1.38000  : Add advisory for remote TEMS higher maint level than hub TEMS
# 1.39000  : Add Product Summary Report section
# 1.40000  : Add check for historical data but no WPAs
# 1.41000  : Add tighter check for TOBJACCL checking, 1099W, 1100W, 1101W and revised 1030W
# 1.42000  : Add 1102W for known situation unknown system generated MSL - not so important
#          : Add FTO status  HUB/MIRROR in FTO message
# 1.43000  : HOSTINFO to Agent summary
# Following is the embedded "DATA" file used to explain
# advisories the the report. It replaces text in that used
# to be in TEMS Audit Users Guide.docx
__END__
DATAHEALTH1001E
Text: Node present in node status but missing in TNODELST Type V records

Check: For every NODE in TNODESAV, there must be a TNODELST
NODETYPE=V with matching TNODELST column

Meaning: This is sometimes seen after a FTO synchronization
defect. There are likely other unknown causes. A missing
type V records identifies agents where no situations will
be started and real time data may not be available. This
is a severe condition and needs rapid resolution.

There are some cases with z/OS Agents where this condition
exists but is not a problem. That research continues.

Recovery plan: Open a PMR and work with IBM Support on how
to resolve this issue. Sometimes stopping the agent, doing
a Remove Offline Entry from the Managed System List and
restarting agent works…. However that process effectively
deletes all the user defined Managed System List data.
--------------------------------------------------------------

DATAHEALTH1002E
Text: Node without a system generated MSL in TNODELST Type M records

Check: For every NODE in TNODESAV, there must a TNODELST Type M
with matching NODE and with a NODELST starting with an asterisk.

Meaning: This is sometimes seen after a FTO synchronization defect.
There are likely other unknown causes. The MSLs starting with
asterisk are system generated MSLs. For example all Windows OS
Agents should be in *NT_SYSTEM. If there are agents missing, then
situations distributed to *NT_SYSTEM will not include the missing
agents and so some situations will not run as expected. We have
seen rare cases where a customer chose to delete those records and
in so the issue can be ignored in that case.

There are some cases with z/OS Agents where this condition exists
but is not a problem. That research continues.

Recovery plan: Open a PMR and work with IBM Support on how to resolve this issue.
--------------------------------------------------------------

DATAHEALTH1003I
Text: Node present in TNODELST Type M records but missing in Node Status

Check: For every NODE in TNODELST where NODETYPE=M; there should
be a matching TNODESAV NODE.

Meaning: This is a very low severity case where the MSLs have left
over agents which are not in service any more. The adverse impact
is that if a new agent is created with the same name as the out of
service agent unexpected situations may start running.

Recovery plan: In TEP Object Editor, edit the MSLs involved and delete
the unknown agents and perhaps delete no longer used MSLs. One site
had 100,000 TNODELST rows and 35% of them represented obsolete MSLs
that should have been deleted long ago.
--------------------------------------------------------------

DATAHEALTH1004I
Text: Node present in TNODELST Type M records, but missing TNODELST Type V records

Check: For every NODE in TNODELST NODETYPE=M, there should be a
matching TNODELST NODETYPE=V NODE agent.

Meaning: This case may be related to the previous advisory code DATAHEALTH1003I.
If so, after the "missing" agents are removed  from the MSL,
this will not be an advisory. It might also be a case of missing
NODETYPE=V records DATAHEALTH1001E. After the recovery plan for
that case above is performed this will no longer show.

Recovery plan: Open a PMR and work with IBM Support on how to resolve this issue.
--------------------------------------------------------------

DATAHEALTH1005W
Text: Hub TEMS has <count> managed systems which exceeds limits $hub_limit

Check: A Hub TEMS should have no more than 10,000 agents
[ITM 623 and earlier] and no more than 20,000 agents
[ITM 630 and later].

Meaning:  The documented level in the Installation Guide TEMS
sizing section is what ITM R&D and QA have tested and stand behind.
No customer should exceed these limits. The agent count includes
both directly configured agents and also subnode agents such as
Agentless Agent for Linux subnodes. The effect of exceeding this
limit is often seen as Hub TEMS instability. Unfortunately that
is a common problem.

Recovery plan: Create new ITM Hub TEMS islands to manage more agents.
--------------------------------------------------------------

DATAHEALTH1006W
Text: Remote TEMS has <count> managed systems which exceeds limits 1,500

Check: A remote TEMS should have no more than 1,500 agents

Meaning: The count includes subnode agents which connect through a
managing agent. The documented level is what ITM R&D and QA have
tested and stand behind. No customer should exceed these limits.
Unfortunately that is a common issue.

Recovery plan: Create new ITM remote TEMS agents and keep within
the published limits. In production workloads the practical limit
may be less than 1,500 agents depending on workload. One site could
only maintain remote TEMS stability by limiting to 750 agents.
--------------------------------------------------------------

DATAHEALTH1007E
Text: TNODESAV duplicate nodes

Check: TNODESAV.NODE values must be unique.

Meaning: This always means the Index file [.IDX] is out of
sync with the data [.DB]. The one fully diagnosed case where
this was observed was when a customer unwisely replaced a .IDX
file from another TEMS and not the .DB file. It could happen
for many other reasons.

Recovery plan: Open a PMR and work with IBM Support to resolve
this issue.
--------------------------------------------------------------

DATAHEALTH1008E
Text: TNODESAV duplicate nodes

Check: TNODELST NODETYPE=V NODELST values must be unique

Meaning: This always means the Index file [.IDX] is out of
sync with the data [.DB]. It could happen for many other reasons.

Recovery plan: Open a PMR and work with IBM Support to resolve
this issue.
--------------------------------------------------------------

DATAHEALTH1009E
Text: TNODELST Type M duplicate NODE/NODELST

Check: TNODELST NODETYPE=M NODE/NODELST values must be unique.

Meaning: This likely means the Index file [.IDX] is out of sync
with the data [.DB]. It can happen for many other reasons.

Recovery plan:  Open a PMR and work with IBM Support to resolve
this issue.
--------------------------------------------------------------

DATAHEALTH1010W
Text: TNODESAV duplicate hostaddr in [$pagent]

Check: TNODESAV HOSTADDR values must be unique.

Meaning:  For most agents this contains the protocol/ip_addr/port/hostname
value. In a normal running system these will be unique. The $pagent
string shows the managed system names of the agents, the thrunode
and the online status Y or N.
Here is an example advisory

10,DATAHEALTH1010W,
  ip.pipe:#99.99.99.141[10055]<NM>ibmzp1928</NM>,
  TNODESAV duplicate hostaddr in
  [ibmzp1928:PX[REMOTE_ibmptm3c_2][Y]
   ibmzp1928:KUX[REMOTE_ibmptm3c_2][Y] ]

This value ,ip.pipe:#99.99.99.141[10055] names the protocol used,
the ip address and the port number.

The two registered users in this example are

ibmzp1928:PX with thrunode REMOTE_ibmptm3c_2 and is online

ibmzp1928:KUX with the same thrunode REMOTE_ibmptm3c_2 and is also online

But but but!!! two ITM processes cannot ever share listening ports.

This means that one of the two processes is not functional but is
continuing to send node status updates. This is a waste of resources
and confusing at best.

There have been two well diagnosed cases.
- An early config problem at the agent left an offline agent
  with the same HOSTADDR as the existing agent but usually in
  offline [N] status
- A Universal Agent was stopped, but the UA process continued
  updating node status. The new Agent Builder replacement used the
  same listening port. Both were online in the TNODESAV table on
  different remote TEMS. There were no situations assigned to
  that Universal Agent.

There will be many more cases to learn from. These are usually not
big problems. However, they do consume resources and can
create confusion in understanding the ITM environment.
It would be best to fix them.

Recovery plan:  Examine each on a case by case basis. In the case
where one agent was offline, a tacmd cleanms -m <agentname>
resolved the issue. In the UA case, the recovery was simply
to kill the errant UA process. UA then went offline and a tacmd
cleanms -m <ua_agent_name> restored normal functioning. If you
need further help, open a PMR and work with IBM Support
--------------------------------------------------------------

DATAHEALTH1011E
Text: HUB TEMS $hub_tems is present in TNODELST but missing from TNODESAV

Check: Check TNODELST NODETYPE=M and the *HUB entry. The corresponding
TNODESAV data does not contain the Hub TEMS nodeid.

Meaning:  The meaning and impact is unknown. This was observed in some
test environments. It has also been seen when checker run against a
remote TEMS. It is unlikely to be seen in a hub TEMS that is actually
working well.

Recovery plan:  Open a PMR and work with IBM Support on how to resolve
this issue.
--------------------------------------------------------------

DATAHEALTH1012E
Text: No TNODELST NODETYPE=V records

Check: TNODELST NODETYPE=V - no such records

Meaning: This might mean a very bad condition.

Recovery plan:  Open a PMR and work with IBM Support on
how to resolve this issue.
--------------------------------------------------------------

DATAHEALTH1013W
Text:  Node Name at 32 characters and might be truncated

Check: Length of NODE in TNODESAV is 32 characters

Meaning: This *might* mean truncation has happened.
For example, if a hostname is relatively long, it is likely
that the total length of Node Name will exceed 32 characters.
During agent registration, if the constructed Node Name is
longer than 32 characters the node name is silently truncated.
This might be harmless if the node name is unique after
truncation. But it could cause problems where one agent would
masquerade as another and cause lots of overhead and incorrect
monitoring. It could also be that the Node Name is exactly 32
characters long and there is no trouble at all.

Recovery plan: Review nodes. If truncation has occurred,
reconfigure the agent to avoid truncation if a problem exists.
--------------------------------------------------------------

DATAHEALTH1014W
Text:  Subnode Name at 31/32 characters and might be truncated

Check: Length of NODE in TNODESAV is 31 or 32 characters

Meaning: This *might* mean truncation has happened. For a subnode
agent this involves a configuration on the controlling agent.
In one case closely examined there was a 3 byte header RZ: and
a 5 byte trailer:RZB. That left 24 characters for the subnode name.
In all cases the nodename created by the agent was 31 characters,
so there was only 23 characters for identifying the subnode. With
some subnode agents, truncation occurred here and caused problems
with subnode agents going offline invalidly. As described earlier
this may or may not cause a problem. If the subnode specifier was
23 characters anyway there would be no trouble at all.

Recovery plan: Review subnodes. If truncation has occurred,
reconfigure the subnode agent to avoid truncation if a problem exists.
--------------------------------------------------------------

DATAHEALTH1015W
Text: Managing agent subnodelist is <count>,  more than $opt_subpc_warn% of 32768 bytes

Check: For a managing agent, compare the length of subnode string
to 32,768 bytes and alert if more than 80% full
[TEMS prior to ITM 623 FP2].

Meaning: This applies only if the TEMS the managing agent connects
to is at maintenance level before ITM 623 FP2.

Until ITM 623 FP2, there is an absolute limit of 32,768 bytes
for the string of subnode agent names [with blank separator]. If that
is exceeded, the TEMS usually fails. In one case TEMS did not crash
but totally stopped working correctly. This is a very dangerous
condition and must be avoided. The default is 90% of maximum.

Recovery plan:  1) Update TEMS to maintenance levels of ITM 623 or ITM 630.
2) Configure multiple managing agents and divide the workload. The usual
estimate is 800 to 1000 subnode agents per managing agent.  A precise number
is not known because the length of each subnode agent name is not fixed.
--------------------------------------------------------------

DATAHEALTH1016E
Text:  TNODESAV invalid node name

Severity: 50

Check:  Node Names should only use certain characters.

Meaning:  This will usually have little effect unless the
Hub TEMS is configured with CMS_NODE_VALIDATION.  Should
that be set the problem agents will be offline. The legal
characters are:

 A-Z, a-z, 0-9,* _-:@$#

A Node Name can never start with '*',  '#',  '.'  or  ' ' .

In one case, what appeared to be a legal name, contained
an invisible X'08' character [ASCII backspace] and therefore
was in fact an invalid Node Name.

At ITM 6.3, the CMS_NODE_VALIDATION was defaulted to YES.
Nodes like this will fail to connect and that could cause
monitoring disruption.

Recovery plan:  Reconfigure agent using legal characters.
--------------------------------------------------------------

DATAHEALTH1017E
Text:  TNODELST NODETYPE=M invalid nodelist name

Check:  Nodelist names should only use certain characters.

Meaning:  This will usually have little effect unless the
Hub TEMS is configured with CMS_NODE_VALIDATION.  At
ITM 630 this is now the default. Should that be set
the problem agents will  be offline. The legal characters are:

 A-Z, a-z, 0-9,* _-:@$# period and space

A Nodelist Name can never start with '*',  '#',  '.'  or  ' ' .

Recovery plan:  Reconfigure agent using legal characters.
--------------------------------------------------------------

DATAHEALTH1018W
Text:  Virtual Hub Table updates <count> per hour <count> agents
Text:  Virtual Hub Table updates peak <rate> per second more than nominal <rate>,  per hour <count>, total agents <count>

Check: Calculate certain agents and the known update virtual hub table update rate

Meaning: This applies to the following agents
UX - Unix OS Agent
OQ - Microsoft MS-SQL
OR - Oracle
OY - Sybase
Q5 - Microsoft Clustering
HV - Microsoft Hyper-V Server Agent
All agents named use an older technology that causes a hub TEMS
virtual table to be updated synchronously - like every one to
three minutes. When there are large numbers of these agents,
the effect on the Hub TEMS can be destabilizing. In addition,
the resulting summary Hub TEMS virtual tables are always
incomplete and thus of little value. The objects that cause
this activity should be deleted.

In the Total message, the peak rate is the number of updates
coming on from the agent's worst case. That is usually at
6 minutes, 12 minutes. etc after the hour. Some of the agents
update 2 or 3 tables and so it is not a pure count of agents.
The damage occurs when the incoming workload surpasses the ITM
communications capacity. Then other communications fail. There
have been cases with as few as 180 Unix OS Agents caused the
Hub TEMS to be destabilized.

Long term, the agent application support files will be changed
to avoid the issue. For any particular customer, they may already
have taken the recovery action.

Recovery plan: See this blog post https://ibm.biz/BdRW3z for a
fuller explanation of the issue and a recovery process. Often IBM
Support prepares the recovery action for the customer.
--------------------------------------------------------------

DATAHEALTH1019W
Text:  Agent using TEMA at <level> level

Check:  Check the Agent Support Library [TEMA] level for 6.1 or later

Meaning:  Prior to ITM 6.2 the OpenSSL library was used for secure
communications. This needs to be updated to later levels which use
 GSKIT for secure communications.

Recovery plan:  Upgrade the OS Agent which will upgrade the Agent
Support Library to use more recent secure communications logic. If t
he OS Agent is not currently installed then install it. That
case can happen with some agents that are installed alone.
--------------------------------------------------------------

DATAHEALTH1020W
Text:  FTO hub TEMS has <count> agents configured which is against FTO best practice

Check: Count number of agents connecting to a hub TEMS in FTO configuration

Meaning: From the installation guide here https://ibm.biz/BdiZue
you can read a statement that in FTO configuration most agents
should connect via remote TEMS. The only exceptions are TEPS,
WPA and Summarization and Pruning Agent. Any other Agents on
the system running the Hub TEMS should also connect to two
remote TEMSes. That provides continuity of monitoring when
the TEMS has stopped.

It may seem strange that in FTO mode we require two Hub TEMS and
two remote TEMS - even for just a single agent. Following is the
background.

1) If the agent loses contact with the primary Hub TEMS by a
communications failure the agent will attempt to connect to the
other Hub TEMS. However, that is in backup mode and will reject
the attempt to connect. That agent will never be able to report
any monitoring - and that conclusion violates the goal of High
Availability.

2) If an agent is connected to both FTO Hub TEMS, one will be
the normal primary remote TEMS. When an FTO switch has occurred
and the normal backup Hub TEMS take the primary role, the agents
will switch to that Hub TEMS. Later when the normal primary Hub
TEMS is started, that Hub TEMS takes on the backup role.  The
agent connection logic will attempt to switch back to the normal
primary remote TEMS after 75 minutes. Each time that happens,
the situations which should run on the agent will first start
up on the Hub TEMS in backup role. Shortly afterwards the agent
will be instructed to switch to another TEMS. When that agent
connects to the current Hub TEMS, the situations will be started
again and create situation events if the conditions warrant. This
will continue every 75 minutes and that is highly disruptive to
normal monitoring.

Please note that if you do not require FTO, a single Hub TEMS
is a fine configuration.

Recovery plan:  If you are going to configure FTO, then all
agents should be configured to remote TEMS except TEPS, WPA
and Summarization and Pruning Agent. TEPS will need two
separate Portal Servers and WPA and S&P will be configured
to both Hub TEMS.
--------------------------------------------------------------

DATAHEALTH1021E
Text:  TSITDESC duplicate nodes

Check: TSITDESC SITNAME values must be unique.

Meaning: This always means the Index file [.IDX] is out of
sync with the data [.DB]. The one fully diagnosed case where
this was observed was when a customer unwisely replaced an .IDX
file from another TEMS and not the .DB file. It could happen
for many other reasons.

Recovery plan: Open a PMR and work with IBM Support on how to
resolve this issue.
--------------------------------------------------------------

DATAHEALTH1022E
Text:  TNAME duplicate nodes

Check: TNAME ID values must be unique.
Meaning: This always means the Index file [.IDX] is out of sync
with the data [.DB]. The one fully diagnosed case where this was
observed was when a customer unwisely replaced an .IDX file from
another TEMS and not the .DB file. It could happen for many other
reasons.

Recovery plan:   Open a PMR and work with IBM Support on how to
resolve this issue.
--------------------------------------------------------------

DATAHEALTH1023W

Text:  TNAME ID index missing in TSITDESC

Check: TNAME ID should have matching TSITDESC SITNAME column

Meaning: This likely has little impact however it means the
TNAME FULLNAME could not be used. It could mean that some
data has been lost from the TSITDESC table.

Recovery plan: Open a PMR and work with IBM Support on
how to resolve this issue.
--------------------------------------------------------------

DATAHEALTH1024E
Text:  Situation Formula *SIT [ <situation> Missing from TSITDESC table

Check: Validate that situation references in the TSITDESC PDT match other TSITDESC SITNAMEs

Meaning: The affected situations will not run as expected.
It could mean that some data has been lost from the TSITDESC table.

Recovery plan:   Rewrite the situation and the situation editor
will force situations selected are correct.
--------------------------------------------------------------

DATAHEALTH1025E
Text:  TNODELST Type V Thrunode <thrunode>  missing in Node Status

Check: Validate that a thrunode reference in a TNODELST NODETYPE=V
object is represented in the TNODESAV table.

Meaning: This could mean that monitoring is not happening on the
node involved. Often this shows as other error checks.

Recovery plan:   Open a PMR and work with IBM Support on how to
resolve this issue.
--------------------------------------------------------------

DATAHEALTH1026E
Text:  TNODELST Type V node invalid name

Check:  Node names should only use certain characters.

Meaning:  This will usually have little effect unless the Hub TEMS
is configured with CMS_NODE_VALIDATION.  Should that be set the
problem agents will  be offline. The legal characters are:

 A-Z, a-z, 0-9,* _-:@$# period and space

A Nodelist Name can never start with '*',  '#',  '.'  or  ' '

Recovery plan:  Reconfigure agent and use legal characters.
--------------------------------------------------------------

DATAHEALTH1027E
Text:  TNODELST Type V Thrunode <node> invalid name

Check:  Nodelist names should only use certain characters.

Meaning:  This will usually have little effect unless the
Hub TEMS is configured with CMS_NODE_VALIDATION.  Should
that be set the problem agents will  be offline. The legal
characters are:

A-Z, a-z, 0-9,* _-:@$# period and space

A Nodelist Name can never start with '*',  '#',  '.'  or  ' '

Recovery plan:  Reconfigure nodelist and use legal characters.
--------------------------------------------------------------

DATAHEALTH1028E
Text:  TOBJACCL duplicate nodes

Check: TOBJACCL.NODE values must be unique.

Meaning: This always means the Index file [.IDX] is out of sync
with the data [.DB].

Recovery plan: Open a PMR and work with IBM Support on how to
resolve this issue.
--------------------------------------------------------------

DATAHEALTH1029W
Text:  TOBJACCL Nodel $nodel1 Apparent MSL but missing from TNODELST

Check: TOBJACCL.NODEL values should be present in TNODELST.

Meaning: This is a meaningless distribution.

Recovery plan: Review entry and delete if no longer needed.
--------------------------------------------------------------

DATAHEALTH1030W
Text:  "TOBJACCL unknown Situation with a unknown MSN/MSL name distribution

Check: TOBJACCL.OBJNAME values should be present in TNODESAV

Meaning: This is a meaningless distribution.

Recovery plan: Review entry and delete if no longer needed.
--------------------------------------------------------------

DATAHEALTH1031E
Text:  TGROUPI [$key] unknown TGROUP ID

Check: TGROUPI ID should match a TGROUP ID

Meaning: This could prevent Situation Group Distribution

Recovery plan: Review Situation Group entries and correct.
--------------------------------------------------------------

DATAHEALTH1032E
Text:  TGROUPI [$key] unknown group objectname

Check: TGROUPI OBJNAME should match a TGROUP ID

Meaning: This could prevent Situation Group Distribution

Recovery plan: Review Situation Group entries and correct.
--------------------------------------------------------------

DATAHEALTH1033E
Text:  TGROUPI [$key] unknown situation objectname

Check: TGROUPI OBJNAME should match a Situation name

Meaning: This could prevent Situation Group Distribution

Recovery plan: Review Situation Group entries and correct.
--------------------------------------------------------------

DATAHEALTH1034W
Text:  TGROUP ID $f not distributed in TOBJACCL

Check: Validate that a Situation Group ID is distributed.

Meaning: This could mean that monitoring is not happening on
the Situation Group. In some cases the data is used for reference only.

Recovery plan:   Review situation group and see if it should be
distributed.
--------------------------------------------------------------

DATAHEALTH1035W
Text:  TOBJACCL Group name missing in Situation Group

Check: Validate that a Group distribution exists in Situation Group

Meaning: This likely a left over distribution for a deleted situation group.

Recovery plan:   Review distribution and delete if no longer needed.
--------------------------------------------------------------

DATAHEALTH1036E
Text:  Invalid Agent version [agent_version] in node <nodename> in tnodesav

Check: Versions should be nn.nn.nn

Meaning: Probably a left over from a bad install, but it could prevent normal agent operation.

Recovery plan: review agent configuration
--------------------------------------------------------------

DATAHEALTH1037W
Text:  Agent at version [agent_version] using TEMA at lower release [TEMA_version]

Check: Compare TEMA and Agent version

Meaning: This may work OK but there is little experience and no IBM
testing at all. Older TEMA levels are missing APAR fixes and that
can increase the number of problems seen.

Recovery plan:   upgrade OS Agent to higher release level.
--------------------------------------------------------------

DATAHEALTH1038E
Text:  *HUB node missing from TNODELST Type M records"

Check: Check for presence of *HUB

Meaning: This is usually a severe problem where the TNODELST
has been damaged and needs rebuilding. It can also mean the
program was run on a remote TEMS in error.

Recovery plan:   Consult IBM Support if needed.
--------------------------------------------------------------

DATAHEALTH1039E
Text:  table LSTDATE is blank and will not synchronize in FTO configuration

Check: Check for blank column in table

Meaning: This is a FTO configuration and these IDs will not be
synchronized to the backup hub TEMS. This can lead to loss of
events at event receiver. If not FTO then not a problem. This
was an object created before ITM the objects were synchronized.

Recovery plan:   In some cases you can use tacmd functions to
delete and recreate the data. In other cases contact IBM Support
for advice.
--------------------------------------------------------------

DATAHEALTH1040E
Text:  LSTDATE for [comment] value in the future date

Check: Check for future date in that field and ensure FTO is configured

Meaning: This condition was corrected by APAR IV60288 at ITM 630 FP3.
Before that time, if the future LSTDATE was processed by a FTO Backup
hub TEMS, that would prevent other updates from being synchronized.
That means FTO would not work properly.

Recovery plan:   Upgrade to ITM 630 FP3. Otherwise contact IBM Support
for a recovery action plan.
--------------------------------------------------------------

DATAHEALTH1041W
Text:  table LSTDATE value in the future <date>

Check: Check for future date in that field and ensure FTO is not configured

Meaning: This has no effect when FTO is not configured but would
definitely be a problem if FTO was configured later on.

Recovery plan:   Upgrade to ITM 630 FP3. Otherwise contact IBM Support
in case a FTO configuration is planned for the future.
--------------------------------------------------------------

DATAHEALTH1042E
Text:  Agent [agent name] using TEMA at version [version] in IZ76410 danger

Check: Check for agent level

Meaning: TEMA in the range ITM 621 before FP3 and ITM 622 before
FP3 had a severe defect whereby an agent could be connected to
two remote TEMS at the same time. This would occur following a
switch to secondary remote TEMS and an automatic switch back.
The issues were many including situations running multiple
times, Agent crashes, no situations running and many more.

Recovery plan:   Upgrade OS Agent to levels past the danger zone.
Alternatively only configure agent to a single remote TEMS.
For more information contact IBM Support.
--------------------------------------------------------------

DATAHEALTH1043E
Text:  Agent with TEMA at [version] later than TEMS $tems1 at [version]

Check: Check for agent level and TEMS level

Meaning: Agents should be at a TEMA level equal or below the
TEMS version level. This case is not supported and is not
tested. It may work but is considered risky.

Recovery plan:   Upgrade the TEMS to the agent level or higher.
If needed a new remote TEMS at an equal or higher level can be
used. TEMSes can connect to other TEMS any order high to low
or low to high.
--------------------------------------------------------------

DATAHEALTH1044E
Text:  Agent with unknown TEMA level [version]

Check: Check for agent level

Meaning: This has been seen in a few cases and the exact impact
is unknown. However it does not seem to be a safe condition. This
might also suggest a new Database Health Checker version is needed.

Recovery plan: Reinstall the agent or contact IBM Support for advice.
--------------------------------------------------------------

DATAHEALTH1045E
Text:  TEMS with unknown version [version]

Check: Check for TEMS level

Meaning: This has never been seen and the exact impact is unknown.
However it does not seem to be a safe condition. This might also
suggest a new Database Health Checker version is needed.

Recovery plan: Contact IBM Support for advice
--------------------------------------------------------------

DATAHEALTH1046W
Text:  Total TEMS Packages [.cat files] count [count] exceeds nominal [500]

Check: Check for number of catalogs [IBM internal usage only]

Meaning: TEMS has an absolute maximum of 512 catalog files. If
one more is added then TEMS will fail to initialize.

Recovery plan: Remove unneeded .cat and related .atr files.
--------------------------------------------------------------

DATAHEALTH1047E
Text:  EVNTMAP ID[id] Unknown Situation in mapping - sitname

Check: See if event mapping references a known situation name

Meaning: This was probably left over when a situation was deleted.
This has relatively little impact.

Recovery plan: If concerned contact IBM Support to get help on
removing data.
--------------------------------------------------------------

DATAHEALTH1048E
Text:  Total TEMS Packages [.cat files] count count] close to TEMS failure point of 513"

Check: Check for number of catalogs [IBM internal usage only]

Meaning: TEMS has an absolute maximum of 512 catalog files. If one
more is added then TEMS will fail to initialize. This is when total
is more than 510 and failure is very close.

Recovery plan: Remove unneeded .cat and related .atr files.
--------------------------------------------------------------

DATAHEALTH1049W
Text:  TNODESAV node name with embedded blank

Check: Check for nodes with embedded blanks

Meaning: Agent names are allowed to have embedded blanks, however
it is usually a configuration error and confusing at best.

Recovery plan: Reconfigure agent without embedded blanks in name.
--------------------------------------------------------------

DATAHEALTH1050W
Text: TNODELST TYPE V node name with embedded blank

Check: Check for TNODELST TYPE V nodes with embedded blanks

Meaning:  This is likely a side effect of DATAHEALTH1049W.
Agent names are allowed to have embedded blanks, however
it is usually a configuration error and confusing at best.

Recovery plan: Reconfigure agent without embedded blanks in name.
--------------------------------------------------------------

DATAHEALTH1051W
Text:  TNODELST TYPE V Thrunode [thrunode] with embedded blank

Check: Check for TNODELST TYPE V thrunode with embedded blanks

Meaning:  This is likely a side effect of DATAHEALTH1049W. Agent
names are allowed to have embedded blanks, however it is usually
a configuration error and confusing at best.

Recovery plan: Reconfigure remote TEMS without embedded blanks
in name
--------------------------------------------------------------

DATAHEALTH1052W
Text:  TNODELST NODETYPE=M nodelist with embedded blank

Check: Check for TNODELST TYPE M nodelist with embedded blanks

Meaning:  Nodelist names are allowed to have embedded blanks,
however it is usually a configuration error and confusing at best.

Recovery plan: Reconfigure remote TEMS without embedded blanks
in name.
--------------------------------------------------------------

DATAHEALTH1053E
Text:  EVNTMAP Situation reference missing

Check: EVNTMAP Situation tag in MAP column

Meaning:  The Event Mapping does not reference a situation and
so cannot be applied. If an event mapping was expected, it will
not work.

Recovery plan: Work with IBM Support on how to remove the data.
--------------------------------------------------------------

DATAHEALTH1054E
Text:  TPCYDESC duplicate key PCYNAME

Check: TPCYDESC should have unique policy names

Meaning: This always means the Index file [.IDX] is out of sync
 with the data [.DB]. This usually means the workflow policy
 process is not working as expected.

Recovery plan: Open a PMR and work with IBM Support to resolve
this issue.
--------------------------------------------------------------

DATAHEALTH1055E
Text: Policy Activity [ACTNAME=name] Unknown policy name

Check: TACTYPCY should have reference a known policy name

Meaning: This is likely a left over activity from a deleted
workflow policy. It has no impact unless a new policy is
created using the old name in which case the new policy
might behave unexpectedly.

Recovery plan: If this is a concern, open a PMR and work
with IBM Support to resolve this issue.
--------------------------------------------------------------

DATAHEALTH1056E
Text: Policy Activity [ACTNAME=name] Unknown policy name

Check: Check that Workflow Policy activities reference
known situations.

Meaning: This usually means the workflow policy process is
not working as expected. Usually this means that the situation
was deleted.

Recovery plan: If the workflow policy is no longer used it
should be deleted or rewritten.
--------------------------------------------------------------

DATAHEALTH1057E
Text:  TPCYDESC Evaluate Sit Now - unknown situation sitname

Check: Check that Workflow Policy activities reference known
situations.

Meaning: This usually means the workflow policy process is
not working as expected. Usually this means that the situation
was deleted.

Recovery plan: If the workflow policy is no longer used
it should be deleted or rewritten.
--------------------------------------------------------------

DATAHEALTH1058E
Text:  TCALENDAR duplicate key ID

Check: TCALENDAR should have unique keys

Meaning: This always means the Index file [.IDX] is out of sync
with the data [.DB]. This usually means the workflow policy process
is not working as expected.

Recovery plan: Open a PMR and work with IBM Support to resolve
this issue.
--------------------------------------------------------------

DATAHEALTH1059E
Text:  TOVERRIDE duplicate key ID

Check: TOVERRIDE should have unique keys

Meaning: This always means the Index file [.IDX] is out of sync
with the data [.DB]. This usually means the workflow policy process
is not working as expected.

Recovery plan: Open a PMR and work with IBM Support to resolve
this issue.
--------------------------------------------------------------

DATAHEALTH1060E
Text:  TOVERRIDE Unknown Situation [sitname] in override

Check: TOVERRIDE should reference a known situation

Meaning: This usually means the situation was deleted and
has relatively low impact.

Recovery plan: If this is concerning, work with IBM Support
to delete the data.
--------------------------------------------------------------

DATAHEALTH1061E
Text:  TOVERITEM Unknown Calendar ID calid

Check: TOVERITEM should reference a known calendar if specified

Meaning: This could mean the situation override is not working as expected.

Recovery plan: Review override and validate it is correctly defined.
--------------------------------------------------------------

DATAHEALTH1062E
Text:  TOVERITEM Unknown TOVERRIDE ID id

Check: TOVERITEM should reference a known TOVERRIDE object

Meaning: This could mean the situation override is not working as expected.

Recovery plan: Review override and validate it is correctly defined.
--------------------------------------------------------------

DATAHEALTH1063W

Text:  table LSTDATE is blank and will not synchronize in FTO configuration
Check: LSTDATE should not be blank

Meaning: This is an error condition but it has no effect and
FTO is not defined.

Recovery plan: If FTO is planned in future, work with IBM Support
to correct data.
--------------------------------------------------------------

DATAHEALTH1064W
Text:  Situation Sampling Interval value seconds - higher then danger level danger

Check: situation sampling interval should be maximum 4 days

Meaning: This a recently identified issue. On Linux/Unix/Windows
it just doesn't work as expected on z/OS it can result in excessive
CPU resource used,

Recovery plan: Change sampling interval to 4 days or less.
--------------------------------------------------------------

DATAHEALTH1065W
Text: TPCYDESC Wait on SIT or Sit reset - unknown situation sitname but policy not autostarted

Check: Check that Workflow Policy activities reference known situations.

Meaning: This usually means the workflow policy process would not
work as expected if started. Usually this means that the situation
was deleted.

Recovery plan: If the workflow policy is no longer used it should be deleted or rewritten.
--------------------------------------------------------------

DATAHEALTH1066W
Text: TPCYDESC Evaluate Sit Now - unknown situation sitname but policy not autostarted

Check: Check that Workflow Policy activities reference known situations.

Meaning: This usually means the workflow policy process would not
work as expected if started. Usually this means that the situation
was deleted.

Recovery plan: If the workflow policy is no longer used it should be deleted or rewritten.
--------------------------------------------------------------

DATAHEALTH1067E
Text:  Danger of TEMS crash sending events to receiver APAR IV50167

Check: Check TEMS maintenance level.

Meaning: At ITM 630 FP2 there were a number of serious problems. The most
severe was APAR IV50167.

Using Msg Slot Customization with Event Forwarding may crash 6.3 FP2 TEMS
http://www-01.ibm.com/support/docview.wss?uid=swg21656217

With some customers no crash was seen. With others it was a couple times
a week. With others the crashing was constant after some point.

Here is a partial list of other known issues

APARs opened against IBM Tivoli Monitoring (ITM) V63 FP2
http://www-01.ibm.com/support/docview.wss?uid=swg21659707

Recovery plan: Upgrade the hub TEMS to a later maintenance level such as

IBM Tivoli Monitoring 6.3.0 Fix Pack 7 (6.3.0-TIV-ITM-FP0007)
http://www-01.ibm.com/support/docview.wss?uid=swg24041633
--------------------------------------------------------------

DATAHEALTH1068E
Text: Agent registering [count] times: possible duplicate agent names

Check: Check TEIBLOGT table

Meaning: It is quite possible to accidentally have multiple agents
with the same name. This contradicts a basic ITM requirement of each
managed system name being unique. The impact is a failure to monitor
as expected. It can also have severe impacts on TEMS and TEPS
performance. This Database Health Checker process identifies some
but not all of the problems. Another symptom of the issue is relatively
 constant "Navigator Updates Pending" messages in the Portal Client.

See the Database Health Checker report section showing the
top 20 agents which *may* be having a problem. There may be
no real problems if the hub TEMS has been running for a long
time and no agent is seen with unusually large counts. See the
recovery plan section below for a general way to identify all
such issue.

Recovery plan: See the following blog post
Sitworld: TEPS Audit https://ibm.biz/BdXNvy

The report shows all the duplicate agent names that affect the
TEPS. In the portal client this is seen as excessive
"Navigator Updates Pending" conditions. There is other work
underway to identify more cases.

Recovery is to configure the agents to have unique names.
--------------------------------------------------------------

DATAHEALTH1069E
Text:  FTO hub TEMS have different version levels [nodeid=version;…]

Check: Check definition of hub TEMSes

Meaning: FTO hub TEMSes should have the same maintenance level. It is
possible to run for a while at different levels such as while
installing new maintenance. However to minimize problems avoiding
this condition is required.

Recovery plan: Apply maintenance to backlevel TEMS so they run at the same level.
--------------------------------------------------------------

DATAHEALTH1070W
Text:  Agent There are count hub TEMS [nodeid=version;…]

Check: Check definition of hub TEMSes

Meaning: An ITM configuration can validly have one or two hub
TEMSes. This advisory is created when three or more hub
TEMSes are found. It is currently unknown if this causes
any actual problems, but it is often an accident. There is
a transient configuration with two FTO hub TEMSes and another
hub TEMS in Hot Backup mode, so condition could be normal.

Recovery plan: Correct the ITM to have only one or two hub TEMSes.
--------------------------------------------------------------

DATAHEALTH1071W
Text:  Situation with invalid sampling days [days]

Check: Check Situation Sampling Interval days

Meaning: The Situation Sampling interval days should be a number
from 1 to 3 digits. This advisory is produced if the number is
empty or more than 3 digits. If this condition exists, it might
cause situations to behave abnormally
--------------------------------------------------------------

DATAHEALTH1072W
Text:  Situation with invalid sampling time [time]

Check: Check Situation Sampling Interval time

Meaning: The Situation Sampling interval time should
be a 6 digit number representing hhmmss. Cases have been
seen where this is "0" or "0000". In those cases it caused
incorrect sampled situation behavior and monitoring did
not take place as expected.

Recovery plan: Re-write the situation if it is still useful,
otherwise delete it.
--------------------------------------------------------------

DATAHEALTH1073W
Text:  MQ Agent name has missing hostname qualifier

Check: MQ Agent name has missing hostname qualifier

Meaning: MQ agents should specify the hostname using
this control in the mq.cfg file:

SET AGENT NAME(<hostname>)

Without that it is quite easy to get accidental
duplicate names for different agents. That can
lead to confusion and excessive TEMS and TEPS work.

Recovery plan: Add the above control.
--------------------------------------------------------------

DATAHEALTH1074W
Text:  Situation Event arriving $psit_rate per minute

Check: Check situations and eliminate the reason for excessive event rates.

Meaning: Events that arrive in high volume can sometimes
de-stabilize the hub and remote TEMSes. Situation events should
be for rare and exceptional circumstances where a recovery action
is possible to correct the condition.

In the example customer situation, a Windows login rejected alert
was arriving hundreds of time per second and prevented the TEMS
from doing any other work including servicing TEPS and working
with the FTO backup hub TEMS.

The Database Health Checker "Top 20 Situation Event Report"
section will display more information including three example
offending agents.

Recovery plan: Stop the situation and investigate. Remove the
cause of the alert or, if condition is actually normal change
the situation to stop warning on this normal condition.
--------------------------------------------------------------

DATAHEALTH1075W
Text:  TNODESAV duplicate 2 SYSTEM_NAMEs in [...]

Check: Check managed systems for duplicate System Names on different systems

Meaning: The Portal Client Navigator layout is depended on
the Agent System Name. Usually that is identical to the Agent
Host Name which derives from the system hostname. However,
using CTIRA_HOSTNAME and CTIRA_SYSTEM_NAME an agent can be
configured to have almost any value. When a Hostname is
duplicated, you often see duplicate agent names, which
causes significant issues. When a System Name is duplicated,
there is a significant possibility of confusion.
Each of the agents will be shown in the Navigation tree under
the same node.

In one case, there were 500+ Windows OS Agents all under the
same navigation node. This caused great distress.

Recovery plan: Reconfigure the agents involved. Usually that
means making sure the Hostname and System Name are equivalent
and unique across all agents.
--------------------------------------------------------------

DATAHEALTH1076W
Text:  CF Agent configured to $thrunode1 which is not the hub TEMS

Check: Check managed systems for CF Agents not configured to the hub TEMS.

Meaning: The CF Agent - name ends ::CONFIG is part of the
MQ Configuration Agent. By product design there should be only
one such agent in an ITM environment and it must be configured
only to the hub TEMS.

The process is a coordination process between XXX::RCACFG agents.
The extra CONFIG agents connecting to remote TEMSes have no purpose
and will cause remote TEMS performance issues and confusion.

Recovery plan:   For each remote TEMS with this issue make these
changes and recycle the remote TEMS.

Windows: Remove "KCFFEPRB.KCFCCTII" from KDS_RUN in
<installdir>\cms\KBBENV.

Linux/Unix: Remove "KCFFEPRB.KCFCCTII" from KDS_RUN in
<installdir>/tables/<temsnodeid>/KBBENV

and

<installdir>/config/kbbenv.ini

In the future, only configure that agent to the hub TEMS.
--------------------------------------------------------------

DATAHEALTH1077E
Text:  CF Agent not supported in FTO mode

Check: Check managed systems for CF configured to hub TEMS in FTO mode

Meaning: The CF Agent - name ends in ::CONFIG is part of the
MQ Configuration Agent. By product design there should be
only one such agent in an ITM environment and it must be
configured only to the hub TEMS and the TEMS must not be
in FTO mode.

Recovery plan:   For each remote TEMS with this issue make these
changes and recycle the remote TEMS.

Windows: Remove "KCFFEPRB.KCFCCTII" from KDS_RUN in
<installdir>\cms\KBBENV.

Linux/Unix: Remove "KCFFEPRB.KCFCCTII" from KDS_RUN in
<installdir>/tables/<temsnodeid>/KBBENV

and

<installdir>/config/kbbenv.ini

In the future, only configure that agent to the hub TEMS.
--------------------------------------------------------------

DATAHEALTH1078E
Text:  WPA connected to $thrunode1 which is not the hub TEMS

Check: Check managed systems for WPA connected to remote TEMS

Meaning: The Warehouse Proxy Agent must only be configured
to the hub TEMS. If there is to be a WPA installed on each
remote TEMS [definitely best practice] each WPA must connect
to the hub TEMS and use an environment variable to specify
which remote TEMS it is responsible for.

Recovery plan: Configure each WPA to connect and register with
the hub TEMS and use the KHD_WAREHOUSE_TEMS_LIST environment
variable to specify the remote TEMS nodeid that the WPA will be
responsible for.
--------------------------------------------------------------

DATAHEALTH1079E
Text:  TNODESAV invalid affinities [aff] for node

Check: TNODESAV AFFINITIES

Meaning: Something is really wrong with the agent.

Recovery plan: Reinstall agent. If this does not cure issue
then contact IBM Support.
--------------------------------------------------------------

DATAHEALTH1080W
Text:  Situation Status Events arriving num per minute

Check: SITSTSH

Meaning: This means situation status events are arrive more than
60 per minute long term. Many hub TEMS cannot sustain such a rate
and will be unstable. Large systems may sustain such a rate with
success.

Recovery plan: Monitor system for stability. Change situation
definitions to reduce work. Create multiple hub TEMS for large
environments.
--------------------------------------------------------------

Recovery plan: Upgrade OS Agent to a supported level.

DATAHEALTH1081W
Text:  End of Service agents maint[level] count[num] date[date]

Check: TNODESAV

Meaning: This records that there are out of service
TEMA [Agent Support Library] levels. That usually corresponds
to OS Agent levels since they are bundled together. While
IBM Support will give aid when possible but it will be
impossible to do deep level diagnosis and APAR fix creation.

See separate report section.

Recovery plan: Upgrade OS Agent to a supported level.
--------------------------------------------------------------

DATAHEALTH1082W
Text:  End of Service agents maint[level] count[num] date[date]

Check: TNODESAV

Meaning: This records that there are some agents that will be
out of service TEMA [Agent Support Library] levels in the future.
That usually corresponds to OS Agent levels since they are bundled
together. After that date, IBM Support will give aid when possible
but it will be impossible to do deep level diagnosis and APAR
fix creation. See separate report section.

Recovery plan:  Upgrade the agent before the end of support date.
--------------------------------------------------------------

DATAHEALTH1083W
Text:  End of Service TEMS tems maint[level] date[date]

Check: TNODESAV

Meaning: This records that the TEMS is out of service maintenance
level. IBM Support will give aid when possible but it will be
impossible to do deep level diagnosis and APAR fix creation.

Recovery plan:  Upgrade the TEMS to a supported level before the
end of support date.
--------------------------------------------------------------

DATAHEALTH1084W
Text:  Future End of Service TEMS tems maint[level] date[date]

Check: TNODESAV

Meaning: This records that the TEMS will be out of service
maintenance level at a future date. IBM Support will give aid
when possible but it will be impossible to do deep level diagnosis
and APAR fix creation.

Recovery plan:  Upgrade the TEMS to a supported level before the
end of support date.
--------------------------------------------------------------

DATAHEALTH1085W
Text:  Situation undefined but Events arriving from nodes[nodes]

Check: TSITSTSH

Meaning: This means that situation event status are arriving for
a situation that is not defined in the current database. Depending
on volume of incoming work this can have a profound effect and
often goes unnoticed. The advisory is tagged with Situation and
the Atomize value if present.

The TEMS sends an order to the agent to stop the situation but
sometimes the agent does not get the instruction. This can happen
at any maintenance level.

Recovery plan:  At recent maintenance levels, where agent and TEMS
are at ITM 623 FP2 or higher, when the agent starts up with the hub
TEMS they will validate exactly what situations should running
and made any needed adjustments. An agent recycle will correct the
condition.

If either TEMS or agent is below that maintenance level, the
procedure documented here can be used - in the local workaround
section:

http://www.ibm.com/support/docview.wss?uid=swg1IV10164

The agent is stopped, the situation persistence file is deleted and the agent is started.
--------------------------------------------------------------

DATAHEALTH1086W
Text:  MS_Offline dataserver evaluation rate count per second somewhat high

Check: TSITDESC and TNODESAV

Meaning: There are more than 30 INODESTS evaluations per second
in the TEMS dataserver. This is associated with MS_Offline type
situations.

Recovery plan:  Run fewer MS_Offline type situations to avoid
performance problems.
--------------------------------------------------------------

DATAHEALTH1087E
Text:  MS_Offline dataserver evaluation rate count per second dangerously high

Check: TSITDESC and TNODESAV

Meaning: There are more than 200 INODESTS evaluations per second
in the TEMS dataserver. This is associated with MS_Offline type
situations. This can destablize hub TEMS operations.

Recovery plan:  Run fewer MS_Offline type situations to avoid
problems.
--------------------------------------------------------------

DATAHEALTH1088W
Text:  MS_Offline SITMON evaluation rate count per second somewhat high

Check: TSITDESC and TNODESAV

Meaning: There are more than 30 SITMODE evaluations per second
in the TEMS dataserver. This is associated with MS_Offline type
situations using Persist>1.

Recovery plan:  Avoid using MS_Offline type situations with
Persist, which can cause severe performance problems.
performance problems.
--------------------------------------------------------------

DATAHEALTH1089E
Text:  MS_Offline SITMON evaluation rate count per second dangerously high

Check: TSITDESC and TNODESAV

Meaning: There are more than 200 SITMODE evaluations per second
in the TEMS dataserver. This is associated with MS_Offline type
situations using Persist>1.

Recovery plan:  Avoid using MS_Offline type situations with
Persist, which can cause severe performance problems.
performance problems and TEMS instability.
--------------------------------------------------------------

DATAHEALTH1090W
Text:  Agent [agent name] using TEMA at version [version] in IV18016 danger zone

Check: Check for agent level

Meaning: TEMA at ITM 622 FP7 and ITM 623 FP1 have a risk of
looping during TEMS connection. This occurs sometimes when
embedded situations are in the situation formula. The result
is high agent CPU until the agent is recycled.

Recovery plan:   Upgrade OS Agent to levels past the danger zone.
--------------------------------------------------------------

DATAHEALTH1091W
Text:  Autostarted Situation to Online Agent ratio[percent] - dangerously high

Check: Check for situations versus agents

Meaning: Hub and remote TEMS can become unstable if too many
situations are running. This has been seen when separate situations
are distributed to specific agents instead of multiple agents. The
test here is 100%.

The TEMS dataserver [SQL processor] runs logic for each situation
which is distributed. In the key problem case there were 7,000
situations and 700 agents. The TEMS became so unstable it stopped
processing events entirely.

Recovery plan: Reduce the number of situations by using MSLs to
distribute a single situation to multuple agents. If this logic
is absolutely necessary, create multuple hub TEMSes to manage
the workload.
--------------------------------------------------------------

DATAHEALTH1092W
Text:  TEMS Dataserver SQL Situation Load $psit_rate per second more than 4.00/second

Check: Check for too many situations running

Meaning: Hub and remote TEMS can become unstable if too many
situations are running. The TEMS dataserver - SQL processor -
evaluates at each sampling interval. In one case a hub TEMS
failed when processing evaluations at 12 per second. The
problem level depends on many factors including how powerful
the system is running the TEMS.

This is a new area of interest and so is more of a warning than
a predicted error case.

Recovery plan: Reduce the number of situations by using MSLs to
distribute a single situation to multuple agents. Also you can
increase the sampling intervals and create remote TEMSes to
spread out the workload.
--------------------------------------------------------------

DATAHEALTH1093W
Text:  Agent [agent name] using TEMA at version [version] in IV30473 danger zone

Check: Check for agent level

Meaning: At ITM maintenance levels 622 FP7-FP7 and 623 GA-FP2
a defect was present which cause problems using the
KDEB_INTERFACELIST and KDEB_INTERFACELIST_IPV6 controls.

Anytime these are present and used to force exclusive bind

KDEB_INTERFACELIST=!xxx.xxx.xxx

that usage must be coordinated for all ITM processes. For
example all processes must use exclusive bind OR all processes
must use non-exclusive bind. If usage is accidentally mixed
severe problems are caused which cause TEMS disruption and
lack of monitoring.

This has always been true, and is true at the latest levels.

At the problematic maintenance levels, changes were introduced
which would create exclusive binds when not intended. For example

KDEB_INTERFACELIST=xxx.xxx.xxx

would be treated exactly like

KDEB_INTERFACELIST=!xxx.xxx.xxx

Thus you could get severe problems without indending them.

Recovery plan: Review the ITM processes to see if that environment
variable is being used at the agents. If not you can ignore the
issue. If so you have choices:

Best practice is to upgrade the OS Agent to a
more recent level to avoid the issue.

If that is impossible update the uses of KDEB_INTERFACELIST so
they are coordinated amoung all uses... all exclusive or all
non-exclusive.
--------------------------------------------------------------

DATAHEALTH1094W
Text:  TEMS Dataserver SQL Situation Startup total $sit_total more than 2000

Check: Check for too many situations running

Meaning: When a TEMS starts up, autostart situations must
be compiled and delivered to the online agents. If there
are a large number, this can take such a long time that
the TEMS loses contact with hub TEMS. On a remote TEMS
contact is eventually restored, however the condition is
abnormal and should be avoided.

Recovery plan: Reduce the number of situations or create
remote TEMSes to spread out the workload.
--------------------------------------------------------------

DATAHEALTH1095W
Text:  HUB TEMS Dataserver SQL Situation Startup total $sit_total more than 2000

Check: Check for too many situations running

Meaning: When a TEMS starts up, autostart situations must
be compiled and delivered to the online agents. If there
are a large number, this can take such a long time that
the TEMS loses contact with hub TEMS. On a hub TEMS
contact is never restored and the hub TEMS is effectively
disabled.

One case where this condition was fully diagnosed the
environment was a hub TEMS [no remote TEMS] with 700 agents
and 7500 autostated.

Recovery plan: Reduce the number of situations or create
remote TEMSes to spread out the workload.
--------------------------------------------------------------

DATAHEALTH1096W
Text:  Systems [count] running agents with multiple TEMA levels - see later report

Check: TNODESAV check for agent TEMA levels

Meaning: Each ITM agent requires an Agent Support library
TEMA and usually these share the OS Agent TEMS. When there
are multiple levels, that usually reflects 32-bit agents
with 64-bit OS agents. The 32-bit TEMAs are not updated
when 64-bit OS Agents are upgraded.

This can also be cases where agents are installed in different
installation directories.

The impact is that some agents are running back level TEMA
levels and thus are exposed to known defects.

Recovery plan: Correct the issue. The following command

tacmd updateFramework

can be used to upgrade all TEMAs including 32-bit.

Consult IBM Support if there are questions.
--------------------------------------------------------------

DATAHEALTH1097W
Text:  Remote TEMS nodeid maint[level] is later level than Hub TEMS nodeid maint[level]

Check: TNODESAV and TNODELST checks

Meaning: In general hub TEMS levels can be lower than
remote TEMS levels. However there is less customer experience
in that environment. In one recent case of a z/OS remote
TEMS at ITM 630 FP6 and a Windows hub TEMS at ITM 622 FP9
a SQL failure was observed as the remote TEMS was updating the
hub TEMS. The issue is rare and so impact level set low.

The issue is more problematical if the hub and remote TEMSes are
are at different release levels. Many such case will appear
to work but can fail under extreme circumstances.

Recovery plan: Update the hub TEMS.
--------------------------------------------------------------

DATAHEALTH1098E
Text:  UADVISOR Historical Situations enabled [count] but no online WPAs seen

Check: TNODESAV and TSITDESC checks

Meaning: This means uadvisor historical data situations are
collecting data at agents [or TEMS] however no Warehouse
Proxy Agents are online. This means that historical data
will collect at the agents [or TEMS] can can trigger an
out of disk storage condition.

Recovery plan: Install some WPAs or turn off historical data
collection.
--------------------------------------------------------------

DATAHEALTH1099W
Text:  TOBJACCL Unknown Situation with a known MSL name distribution

Check: TSITDESC and TNODESAV and TNODELST checks

Meaning: A situation is mentioned in the distribution table
TOBJACCL with a known managed system list - however the
situation is not defined.

This suggests a situation might be missing and not running
as it would be expected to. However if it was not supposed to be
running there is no effect.


Recovery plan: Review the conditions and see what was planned.
IBM Support can help you eliminate any false records.
collection.
--------------------------------------------------------------

DATAHEALTH1100W
Text:  TOBJACCL Unknown Situation with a known MSN name distribution";

Check: TSITDESC and TNODESAV and TNODELST checks

Meaning: A situation is mentioned in the distribution table
TOBJACCL with a known managed system name list - however the
situation is not defined.

This suggests a situation might be missing and not running
as it would be expected to. However if it was not supposed to be
running there is no effect.


Recovery plan: Review the conditions and see what was planned.
IBM Support can help you eliminate any false records.
collection.
--------------------------------------------------------------

DATAHEALTH1101E
Text:  TOBJACCL known Situation with a unknown MSN/MSL $nodel1 distribution

Check: TSITDESC and TNODESAV and TNODELST checks

Meaning: A situation is mentioned in the distribution table
and the situation is known. However the distribution target
(managed system list or managed system name) is unknown.

This strongly suggest that a situation should be running but is
is not. On one occasion a database file condition caused the
temporary loss of thousands of Managed System List objects
and then result was that many many situations were not running
as expected. That is a severe condition.


Recovery plan: Work with IBM Support to recover from this
severe condition. Having a good backup of the TEMS database
files could help recover. See this document

Sitworld: Best Practice TEMS Database Backup and Recovery
https://ibm.biz/BdRKKH
--------------------------------------------------------------

DATAHEALTH1102W
Text:  TOBJACCL known Situation with a unknown system generated MSL name

Check: TSITDESC and TNODESAV and TNODELST checks

Meaning: A situation is mentioned in the distribution table
and the situation is known. However the distribution target
(system generated managed system list) is unknown.

This is almost certainly a case where a application support
has been installed, the situations have been configured to
run but no agents are currently running. This has a small
effect on TEMS startup time but is not otherwise a problem.

Recovery plan: Probably ignore issue.
--------------------------------------------------------------
