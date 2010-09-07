package Agent::Sentinel::Plugin::Core::SystemCommand;

use Moose; # automatically turns on strict and warnings

has 'cmd' => (is => 'rw' );

sub run {
      my $self = shift;
      return "running [" . $self->cmd() . "]\n";
      #return "running nothing";
}

1;

