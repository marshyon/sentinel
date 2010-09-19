package Agent::Sentinel::Plugin::Test::TestCommand;

use Moose; # automatically turns on strict and warnings
use Data::Dumper;

has 'cfg' => (is => 'rw' );
has 'task' => (is => 'rw' );

sub run {
      my $self = shift;
      # be busy for a bit
      sleep 1;
      return "TestCommand task[" . $self->task . "] [" . $self->{'cfg'}->{'command'} . "]";
}

1;

