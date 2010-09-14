use Test::More tests => 8;
use Config::Std;

# PURPOSE OF TEST
#
# sentinel reads config from a Config::Std
# file and saves values read from this file
# to object accessible methods within the 
# object itself

# so we can check that the important ones
# are being both read and stored as they should
# we set up first test values in a config file
# then invoke sentinel and check it has 
# the correct values stored internally

# first read the test config file we 
# will be using
my $config_file = 't/test_config_file.cfg';
my $interval_default = 10;
read_config $config_file => my %config;

# next set values within the config we just
# read - here set current user to be the one
# to run tests
$config{'main'}{'user'} = $ENV{'USER'};
$config{'main'}{'group'} = $ENV{'USER'};
$config{'main'}{'interval'} = $interval_default;
$config{'main'}{'daemon'} = 0;

# commit changes to the config 
write_config %config;

# now begin tests by invoking sentinel itself
BEGIN {
    use_ok('Agent::Sentinel') || print "Bail out!  ";
}

diag("Testing Config");

# tell sentinel to start up and use the config file
# we just modified
my $s = Agent::Sentinel->new( config_file => $config_file );
$s->init();

# now read back the values sentinel thinks it has 
# from our config file
my $debug    = $s->debug();
my $daemon   = $s->daemon();
my $interval = $s->interval();
my $user     = $s->user();
my $group    = $s->group();
my $pidfile  = $s->pid_file();
my $status_dir  = $s->status_dir();

# run checks on our actual results
ok( $debug == 0,      'test debug value' );
ok( $daemon == 0,     'test daemon value' );
ok( $interval == $interval_default, 'test interval value' );
ok( $group eq $ENV{'USER'}, 'test group value' );
ok( $user  eq $ENV{'USER'}, 'test user value' );
ok( $pidfile eq 't/run/senintel.pid', 'test pidfile ' . $pidfile );
ok( $status_dir eq 't/status', 'test status dir [' . $status_dir . ']' );



