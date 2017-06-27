#v1.0.0
# ovdeploy -cmd "sc query type= service" -node nxsclctx04.nexussa.cl | grep ^SERVICE_NAME | grep -i
#ovdeploy -cmd "sc query type= service" -node nxsclctx04.nexussa.cl | grep ^SERVICE_NAME | grep -i citrix | awk -F: '{print $2}' | sed 's/^ //'
#!/usr/bin/perl
#
# To select type of startup (AUTO_START, AUTO_START (Delayed), DEMAND_START)
#
#Usage: perl srv_checker.pl --node <node_name>|--list_nodes <input_file> --search <all|search_pattern> --timeout <miliseconds>
use warnings;
use strict;
use Getopt::Long;
use lib '/opt/OpC_local/GENERIC_ROUTINES/libs';
#use Mail::Sendmail;
use MIME::Lite;
require 'generic_routines.pm';
use generic_routines qw/execute_cmd_in_HPOM send_report_to_email logger_for_csv_line testOvdeploy_HpomToNode_383_SSL check_node_in_HPOM/;

my @nodename_array = ();
my $current_nodename;
my $to_email;
my $nodenames_list;
my $nodename;
my $search_pattern;
my $timeout;
#my @r_check_node_in_HPOM = ();
my @node_info;
my @get_service_names = ();
my %hash_service_start_type = ();
my @arr_service_start_type = ();
my $scalar_test_return_values;
my @arr_test_title =  ();
my $node_counter = 0;
chomp(my $dateTimeStamp = `date "+%m%d%Y_%H%M%S"`);
my $out_module_audit = "results_srv_checker.$dateTimeStamp";
my $title_csv = "node_name;node_name_found;node_name_mach_type;node_name_ssl;srv_name_start_type";


GetOptions( 'node|n=s' => \$nodename,
            'email|e=s' => \$to_email,
            'list_nodes|l=s' => \$nodenames_list,
            'node_name|n=s' => \$nodename,
            'search|s=s' => \$search_pattern,
            'timeout|t=s' => \$timeout)
            or die ("Error in command line argument(s)!\n");

if (!$nodename && !$nodenames_list)
{
  print "Mandatory parameter missing! --node_name <node_fqdn> or --list_nodenames <input_file>\n";
  exit 0;
}
if ($nodename && $nodenames_list)
{
  print "Can't use both --nodename <node_fqdn> and --list_nodenames <input_file> options!\n";
  exit 0;
}
if ($nodenames_list)
{
  chomp($nodenames_list);
  open(INPUT_NODELIST, "$nodenames_list")
    or die ("Can't open file $nodenames_list!\n");
  while(<INPUT_NODELIST>)
  {
      chomp(my $current_nodename = $_);
      push(@nodename_array, $current_nodename);
  }
  close(INPUT_NODELIST);
}
#If option --nodename was selected loads nodename into array
if ($nodename)
{
  chomp($nodename);
  @nodename_array = ($nodename);
}
print "Starting srv_checker.pl...\n";
if (!$search_pattern)
{
  print "Using default search mode: all\n";
  $search_pattern = "all";
}
if (!$timeout)
{
  print "Using default timeout: 3000ms\n";
  $timeout = "3000";
}
foreach my $loaded_nodename (@nodename_array)
{
  #@r_check_node_in_HPOM = check_node_in_HPOM($loaded_nodename);
  #print "\nChecking node: $loaded_nodename";
  ## Checking nodename within HPOM
  #print "\n--> Checking nodename within HPOM...";
  @node_info = check_node_in_HPOM($loaded_nodename);
  push(@arr_service_start_type, $loaded_nodename);
  #If managed node is WINDOWS
  if ($node_info[0] eq "1")
  {
    push(@arr_test_title, "node_name_found");
    push(@arr_service_start_type, "NODE_FOUND");
    push(@arr_test_title, "node_name_mach_type");
    push(@arr_service_start_type, $node_info[3]);
    if ($node_info[3] =~ m/MACH_BBC_WIN/)
    {
      #print "\r--> Checking nodename within HPOM...FOUND! OS=>WIN";
      #print "\n--> Checking SSL connection to node...";
      my $r_testOvdeploy_HpomToNode_383_SSL = testOvdeploy_HpomToNode_383_SSL($loaded_nodename, $timeout);
      if ($r_testOvdeploy_HpomToNode_383_SSL eq "0")
      {
        push(@arr_service_start_type, "NOK");
        if ($node_counter eq "0")
        {
          print "\n$title_csv";
          logger_for_csv_line($out_module_audit.".csv", $title_csv);
        }
        $scalar_test_return_values = join ';', @arr_service_start_type;
        print "\n$scalar_test_return_values";
        logger_for_csv_line($out_module_audit.".csv", $scalar_test_return_values);
        @arr_service_start_type = ();
        #logger_for_csv_line($out_module_audit.".ssl", "ERROR_NO_SSL_CONNECTION");
        #print "\r--> Checking SSL connection to node...FAILED!";
        #print "\n";
        $node_counter++;
        next;
      }
      push(@arr_service_start_type, "OK");
      #print "\r--> Checking SSL connection to node...SUCCESS!";
      chomp(my $service_name_filter = $search_pattern);
      if($search_pattern eq "all")
      {
        @get_service_names = qx{ovdeploy -cmd \"sc query type\= service\" -node $loaded_nodename -cmd_timeout $timeout | grep ^SERVICE_NAME};
      }
      else
      {
        #print "\npattern: $search_pattern\n";
        @get_service_names = qx{ovdeploy -cmd \"sc query type\= service\" -node $loaded_nodename -cmd_timeout $timeout | grep ^SERVICE_NAME | grep -Ei \'$service_name_filter\'};
      }
      foreach my $r_get_service_names (@get_service_names)
      {
        chomp($r_get_service_names);
        if (!$r_get_service_names)
        {
          push(@arr_service_start_type, "SC_QUERY_TIMEDOUT");
        }
        else
        {
          #print "\n$r_get_service_names";
          $r_get_service_names =~ m/SERVICE_NAME:\s(.*)/;
          my $filtered_service_name = $1;
          my @service_details = qx{ovdeploy -cmd \'sc qc \"$filtered_service_name\" 5000\' -node $loaded_nodename};
          foreach my $r_service_details (@service_details)
          {
            chomp($r_service_details);
            if ($r_service_details =~ m/\s+START_TYPE\s+:\s+[\d+]\s+(.*)/)
            {
              my $start_type = $1;
              chomp($start_type);
              $start_type =~ s/\s+//;
              $hash_service_start_type{$filtered_service_name} = $start_type;
              push(@arr_service_start_type, $filtered_service_name."=>".$start_type);
              #print "\n$filtered_service_name --> $start_type";
            }
          }
        }
      }
      #foreach my $arr_entry (@arr_service_start_type)
      #{
      #  print "$arr_entry\n";
      #}
      #for my $key_srv_name (keys %hash_service_start_type)
      #{
      #  #my $value_srv_start_type = $hash_service_start_type{$key_srv_name};
      #  push(@arr_service_start_type, $hash_check_value{$key_test_name});
      #  print "$key_srv_name => $value_srv_start_type\n";
      #}
    }
    if ($node_info[3] =~ m/MACH_BBC_LX26|MACH_BBC_SOL|MACH_BBC_HPUX|MACH_BBC_AIX/)
    {
      #print "\r--> Checking nodename within HPOM...FOUND but SKIPPING!(Unix-like)";
      push(@arr_service_start_type, "UNIX_LIKE_NODE");
    }
    if ($node_info[3] =~ m/MACH_BBC_OTHER/)
    {
      push(@arr_service_start_type, "NOT_A_MANAGED_NODE");
    }
    $scalar_test_return_values = join ';', @arr_service_start_type;
    if ($node_counter eq "0")
    {
      print "\n$title_csv";
      logger_for_csv_line($out_module_audit.".csv", $title_csv);
    }
    logger_for_csv_line($out_module_audit.".csv", $scalar_test_return_values);
    print "\n$scalar_test_return_values";
  }
  else
  {
    #print "\r--> Checking nodename within HPOM...NOT FOUND!";
    push(@arr_service_start_type, "NODE_NOT_FOUND");
    $scalar_test_return_values = join ';', @arr_service_start_type;
    if ($node_counter eq "0")
    {
      print "\n$title_csv";
      logger_for_csv_line($out_module_audit.".csv", $title_csv);
    }
    print "\n$scalar_test_return_values";
    logger_for_csv_line($out_module_audit.".csv", $scalar_test_return_values);
  }
  @arr_service_start_type = ();
  $node_counter++;
  #print "\n";
}
print "\n";
