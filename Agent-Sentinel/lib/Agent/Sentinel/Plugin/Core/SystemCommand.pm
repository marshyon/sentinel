package Agent::Sentinel::Plugin::Core::SystemCommand;

use Moose;
use Data::Dumper;
use IPC::Open3;
use YAML;

use Symbol 'gensym';
our $VERSION = '0.1';

has 'cfg'           => ( is => 'rw' );
has 'task'          => ( is => 'rw' );
has 'stdout'        => ( is => 'ro' );
has 'stderr'        => ( is => 'ro' );
has 'pid'           => ( is => 'ro' );

sub run {

    my $self = shift;
    my ( $wtr, $rdr, $err );
    my %dump = ();



   
    # construct command line argument from config
    my $args = '';
    if( $self->cfg->{'args'} ) {
    if( $self->cfg->{'args'} =~ m{ARRAY} ) {
        $args = join(" ", @{ $self->cfg->{'args'} } );
    }
    else {
        $args = $self->cfg->{'args'};
    }
    }
    my $command .= $self->cfg->{'command'} . ' ' . $args;

    $err = gensym;
    my $pid = open3( $wtr, $rdr, $err, $command );
    $self->{'pid'} = $pid;
    $dump{'pid'} = $pid;
    $dump{'cfg'} = $self->cfg;

    $dump{'debug'} = '[' . $self->cfg->{'command'} . ' ' . $args . ']';

    my $yaml_status_file  = $self->cfg->{'logfile'};
    YAML::DumpFile( $yaml_status_file, %dump ) if $yaml_status_file;
    close $wtr;

    while(<$rdr>) {
        $dump{'rdr'} .= $_;
    }
    close $rdr;

    while(<$err>) {
        $dump{'err'} .= $_;
    }
    close $err;

    YAML::DumpFile( $yaml_status_file, %dump ) if $yaml_status_file;

    if( $dump{'err'} ) {
    return
        "ERROR - SystemCommand task["
      . $self->task . "] log [". $yaml_status_file ."] ["
      . $command . "]" . $dump{'err'};
    }
    else {
        return $dump{'rdr'};
            #"SystemCommand !!!!!!!  task[" 
          #. $self->task . "] log [". $yaml_status_file ."] ["
          #. $command . "]";
    }

}

1;

