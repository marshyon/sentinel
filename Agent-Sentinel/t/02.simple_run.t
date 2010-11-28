use strict;
use warnings;
use FindBin qw($Bin);
use lib qw(./lib ./t/lib $Bin/../lib);

use Test::More;
use Config::Std;
use Agent::Sentinel;
use Unix::PID;

# PURPOSE OF TEST
#
# read config, extract location of pidfile,
# run sentinel as a separate process
# wait to see if it dies - using pidfile
# to check for it's process id
# after a short time, kill sentinel process
# check it's gone

# create directorys for test runs if not there already
mkdir ("t/run") unless ( -d "t/run");
mkdir ("t/status") unless ( -d "t/status");

# read config file and set daemon mode
#
my $config_file      = 't/test_config_file.cfg';
my $interval_default = 10;
read_config $config_file => my %config;
$config{'main'}{'daemon'} = 1;

# commit changes to the config
#
write_config %config;

diag("Simple Sentinel Run test");
my $pid = Unix::PID->new();

# get current location of pidfile
my $s = Agent::Sentinel->new( config_file => $config_file );
$s->init();
my $pidfile = $s->pid_file;

# start sentinel
#
#my $libpath = "$FindBin::Bin/../lib:$FindBin::Bin/lib";

system("perl t/simple_sentinel_run $config_file");

# periodically check sentinel is still running
my $c = 1;
foreach ( 1 .. 50 ) {
    $c++;
    ok( $pid->is_pidfile_running($pidfile), 'still running' );
}

# stop sentinel
#
$pid->kill_pid_file($pidfile);

ok( !$pid->is_pidfile_running($pidfile), 'stopped running' );

done_testing;

