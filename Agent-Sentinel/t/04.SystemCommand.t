#!perl 

use Test::More;
use FindBin;
use YAML;

BEGIN {
    use_ok('Agent::Sentinel::Plugin::Core::SystemCommand') || print "Bail out!
";
}

diag(
"Testing Agent::Sentinel::Plugin::Core::SystemCommand $Agent::Sentinel::Plugin::Core::SystemCommand::VERSION, Perl $], $^X"
);

my $logpath = "$FindBin::Bin/SystemCommand.yml";

my %cfg = (
    'answer'  => 42,
    'command' => 'ls',
    'stdin'   => 'what is the answer to life, the universe and everything ?',
    'args'    => ['-al','/doesnt_exist'],
    'logfile' => $logpath,
);

my $task    = 'task 101';
my $command = '';

my $sc = Agent::Sentinel::Plugin::Core::SystemCommand->new(
    task => $task,
    cfg  => \%cfg
);

ok( $sc, 'new SystemCommand' );

diag('Testing plugin to read and return configuration parameters ...');

ok( ( $sc->cfg->{'answer'} == 42 ), 'single config value ok' );
ok( ( $sc->cfg->{'stdin'} =~ m{answer to life} ), 'single config value ok' );

diag('run and return correct results - firstly with output to STDERR ...');

my $res = $sc->run();
ok( ( $res =~ m{ERROR} ), 'system command result error returned ok');

diag('run and return correct results - now with no reported errors');
$cfg{'args'}  = ['-al'];


$sc = undef;
$sc = Agent::Sentinel::Plugin::Core::SystemCommand->new(
    task => $task,
    cfg  => \%cfg
);
my %res = YAML::LoadFile($logpath);

$res = $sc->run();
ok( ( $res !~ m{ERROR} ), 'system command result returned with no error ok');



done_testing;

