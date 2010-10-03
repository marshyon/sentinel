package Agent::Sentinel::Plugin::Test::TestCommand;

use Moose;
use Data::Dumper;
use YAML;
my $yaml_file = 'TestCommand.yaml';

has 'cfg'  => ( is => 'rw' );
has 'task' => ( is => 'rw' );

sub run {
    my $self = shift;

    # be busy for a bit
    open( Y, ">$yaml_file" );
    print Y scalar( localtime() ) . "\n";
    close Y;
    my $pwd = `pwd`;
    chomp($pwd);
    my $log  = $self->cfg->{'logfile'};
    my %dump = ();
    $dump{'cfg'}     = $self->cfg;
    $dump{'epoch'}   = time();
    $dump{'date'}    = scalar( localtime() );
    $dump{'task'}    = $self->task();
    $dump{'running'} = 1;
    YAML::DumpFile( $log, %dump );
    sleep 3;
    $dump{'epoch'}   = time();
    $dump{'date'}    = scalar( localtime() );
    $dump{'running'} = 0;
    YAML::DumpFile( $log, %dump );

    return
        "TestCommand [$pwd] plugin sees config [$log] task["
      . $self->task . "] ["
      . $self->{'cfg'}->{'command'} . "]";
}

1;

