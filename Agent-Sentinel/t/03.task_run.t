use strict;
use warnings;
#use lib qw(/home/jon/dev/poe/cpan/Agent-Sentinel/lib /home/jon/dev/poe/cpan/Agent-Sentinel/t/lib);
use lib qw(./lib ./t/lib);
use Test::More;
use Config::Std;
use Agent::Sentinel;
use Unix::PID;
use YAML;

# PURPOSE OF TEST
#
# set up config to hold a new task
#
# this task will be a 'test task'
#
# it has in it that are parts of a staged
# test, so this plugin will be held in 
# the t/lib namespace, not sentinels
# core plugin(s) 
#
# the ability of sentinel
# to run plugins outside of core
# is tested :
#
# 1. run sentinel as a separate process
#
# 2. wait and check for the test task
# to start up, stop, start up again
# and run as scheduled
#
# 3. when we have seen this is happeing ok
# issue a kill to the sentinel process
#
# 4. wait to see if it dies - using pidfile
# to check for it's process id

# START OF TESTS
#

# read config file and set daemon mode
#
my $config_file      = 't/test_config_file.cfg';
my $interval_default = 10;
read_config $config_file => my %config;
$config{'main'}{'daemon'} = 1;
use FindBin;
my $logpath = "$FindBin::Bin/task1.log";

$config{'task 1'}{'logfile'} = $logpath;

# commit changes to the config
#
write_config %config;

diag("Sentinel task run test");
my $pid = Unix::PID->new();

# get current location of pidfile
my $s = Agent::Sentinel->new( config_file => $config_file );
$s->init();
my $pidfile = $s->pid_file;

# start sentinel
#
diag("staring sentinel");
system("perl t/sentinel_run $config_file");



#print Dump(\%status);
my $running = 0;
#sleep 1;
diag("waiting for sentinel test plugin to report started");
WAIT:
foreach ( 1 .. 250 ) {
    my %status = YAML::LoadFile($logpath);
    $running = $status{'running'};
    last WAIT if ($running);
}

ok( $running, "test plugin reports to be running");

# periodically check sentinel is still running

diag("watching for sentinel test plugin to still be running");
my %status;
RUNNING:
foreach ( 1 .. 1000 ) {
    %status = ();
    %status = YAML::LoadFile($logpath);
    $running = $status{'running'};
    last RUNNING if ( ! $running );
    ok( $running, "test plugin reports still to be running");
}

sleep 1;

diag("checking sentinel test plugin to have stopped and sentinel process to have stopped");

ok( ! $running, "test plugin reports stopped");

# stop sentinel
#
$pid->kill_pid_file($pidfile);

ok( !$pid->is_pidfile_running($pidfile), 'stopped running' );

done_testing;

