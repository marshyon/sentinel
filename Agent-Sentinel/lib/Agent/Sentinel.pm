package Agent::Sentinel;

use Moose;    # automatically turns on strict and warnings
use Module::Pluggable require => 1, inner => 0;
use POE qw(Wheel::Run Filter::Reference);
use Config::Std;
use Net::Server::Daemonize qw(daemonize);
use YAML;
use Data::Dumper;

has 'config_file' => ( is => 'rw' );
has 'debug'       => ( is => 'ro' );
has 'daemon'      => ( is => 'ro' );
has 'cfg'         => ( is => 'ro' );
has 'interval'    => ( is => 'ro' );
has 'pid_file'    => ( is => 'ro' );
has 'user'        => ( is => 'ro' );
has 'group'       => ( is => 'ro' );
has 'status_dir'  => ( is => 'ro' );

my $MAX;
my @tasks = qw(one two three four five six seven eight nine ten);
my $sentinel_plugin;

=head1 NAME

Agent::Sentinel - The great new Agent::Sentinel!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use Agent::Sentinel;

    my $foo = Agent::Sentinel->new();
    ...

=head1 SUBROUTINES/METHODS

=head2 function1

=cut

sub function1 {
}

sub function2 {
}

sub load_config {
    my $file = shift;
    read_config $file => my %cfg;
    return \%cfg;
}

sub init {
    my $self = shift;

    # load config file and store for object access
    $self->{'cfg'} = load_config( $self->config_file() );

    $self->{'debug'}    = ${ $self->cfg }{'main'}{'debug'} || 0;
    $self->{'daemon'}   = ${ $self->cfg }{'main'}{'daemon'};
    $self->{'user'}     = ${ $self->cfg }{'main'}{'user'};
    $self->{'group'}    = ${ $self->cfg }{'main'}{'group'};
    $self->{'interval'} = ${ $self->cfg }{'main'}{'interval'} || 300;
    ${ $self->cfg }{'main'}{'pid_file_dir'} .= '/'
      unless ( ${ $self->cfg }{'main'}{'pid_file_dir'} =~ m{/$} );
    $self->{'status_dir'} = ${ $self->cfg }{'main'}{'status_dir'};

    $self->{'pid_file'} =
        ${ $self->cfg }{'main'}{'pid_file_dir'}
      . ${ $self->cfg }{'main'}{'pid_file'};

    # load a list of plugins and save to a hash for lookup
    #
    map {

        $sentinel_plugin = $_->new();

    } $self->plugins();

    # validate each section in config starting 'task <num>' to have
    # a plugin installed of name 'type' in config
    #
    foreach my $section ( keys( %{ $self->{'cfg'} } ) ) {

        next unless ( $section =~ m{^task \d+} );

        {
            #$self->{'SENTINEL_DATA'}->{'tasks'}->{$section}->{'interval'} =
            #  $self->{'cfg'}{$section}->{'interval'};
            #$self->{'SENTINEL_DATA'}->{'tasks'}->{$section}->{'type'} =
            #  $self->{'cfg'}{$section}->{'type'};
            #$self->{'SENTINEL_DATA'}->{'tasks'}->{$section}->{'command'} =
            #  $self->{'cfg'}{$section}->{'command'};
            #$self->{'SENTINEL_DATA'}->{'tasks'}->{$section}->{'parameters'} =
            #  $self->{'cfg'}{$section}->{'parameters'};

            my %section_config = ();
            print ">>found plugin for [[$section]]\n" ;
            foreach my $plugin_param ( keys %{ $self->{'cfg'}->{$section} } )
            {
                print "\t-->param : $plugin_param => "
                  . $self->{'cfg'}->{$section}->{$plugin_param} . "\n";
                $section_config{ $plugin_param } = $self->{'cfg'}->{$section}->{$plugin_param};
            }
            $self->{'SENTINEL_DATA'}->{'tasks'}->{$section}->{'config'} = \%section_config;
            
        }
    }
}

sub run {

    my $self = shift;

    if ( $self->daemon ) {

        daemonize( $self->user(), $self->group(), $self->{'pid_file'}, );

    }

    POE::Session->create(
        inline_states => {
            _start => sub { $self->start_tasks( $_[KERNEL], $_[HEAP] ); },
            time_check =>
              sub { $self->time_tick( $_[KERNEL], $_[HEAP], $_[ARG0] ); },
            next_task => sub { $self->start_tasks( $_[KERNEL], $_[HEAP] ); },
            task_result => sub { $self->handle_task_result( $_[ARG0] ); },
            task_done =>
              sub { $self->handle_task_done( $_[KERNEL], $_[HEAP], $_[ARG0] ); }
            ,
            task_debug => sub { $self->handle_task_debug( $_[ARG0] ); },
            sig_child  => \&sig_child,
        }
    );
    $poe_kernel->run();
}

# just starts tasks, nothing else
# a task may be started if it is time to do so
# time to run is decided upon by configured 'interval' time
# in the config file section of 'task <num>' section
# a task may not be run untill this time interval has elapsed
sub start_tasks {

    my ( $self, $k, $h ) = @_;

  CONFIG:
    foreach my $config_task ( keys( %{ $self->{'SENTINEL_DATA'}->{'tasks'} } ) )
    {

        my $running =
          $self->{'SENTINEL_DATA'}->{'tasks'}->{$config_task}->{'running'} || 0;
        my $last_ran =
          $self->{'SENTINEL_DATA'}->{'tasks'}->{$config_task}->{'last_ran'}
          || 0;
        my $interval =
          $self->{'SENTINEL_DATA'}->{'tasks'}->{$config_task}->{'config'}->{'interval'}
          || 300;

        # skip runnig tasks
        next CONFIG if $running;

        # skip jobs that are not scheduled to run yet
        my $now     = time();
        my $elapsed = $now - $last_ran;
        if ( $elapsed >= $interval ) {

# TODO : add to do_stuff params of config 
# bar expected ( so all of config file 
# entry gets passed for plugin to use 
# whatever has been given to it )
            my %test_hash = ( 'a' => 'one', 'b' => 'two', 'c' => '99' );
            my $task = POE::Wheel::Run->new(
                Program => sub {
                    do_stuff( $config_task, $sentinel_plugin, $self->{'SENTINEL_DATA'}->{'tasks'}->{$config_task}->{'config'} );
                },
                StdoutFilter => POE::Filter::Reference->new(),
                StdoutEvent  => "task_result",
                StderrEvent  => "task_debug",
                CloseEvent   => "task_done",
            );
            my $poe_id = $task->ID;
            $h->{task}->{$poe_id} = $task;
            $k->sig_child( $task->PID, "sig_child" );
            $self->{'SENTINEL_DATA'}->{'poe_ids'}->{$config_task} = $poe_id;
            $self->{'SENTINEL_DATA'}->{'tasks'}->{$config_task}->{'running'} =
              1;
        }
    }
    $k->alarm( time_check => time() + 1, 0 );

    # heap task hash is iterated over for jobs
    # we use a hash all of our own, separate to this called 'SENTINEL_DATA'
    # (for want of a better name at the moment)

    # Run Wheel is created and stored into heap and task->ID needs to be
    # recorded against this job by a hash of job => ids where the ID
    # changes each time a new job is started - so we keep track of the current
    # POE internal ID against each of our config'ed tasks

}

# checks for running tasks and starts new ones if old one has
# finished - will continually call new task untill it is running
# it leaves the job of finding out if the job is ready to be run
# to start tasks
sub time_tick {

    my ( $self, $k, $h, $a ) = @_;

    print '.';

    #print "<time tick $a";
    #foreach ( keys( %{ $h->{task} } ) ) {
    #    print "[$_]";
    #}
    #print "> ";
    YAML::DumpFile(
        $self->{status_dir} . "/status.yaml",
        $self->{'SENTINEL_DATA'}->{'tasks'}
    );
    $k->alarm( time_check => time() + 1, $a + 1 );
    $self->start_tasks( $k, $h );

}

sub do_stuff {

    binmode(STDOUT);
    my $task            = shift;
    my $sentinel_plugin = shift;
    my $hash            = shift;

    $sentinel_plugin->cfg($hash);
    $sentinel_plugin->task($task);

    my $result = $sentinel_plugin->run();

    my $filter = POE::Filter::Reference->new();

    my %result = (
        task   => $task,
        status => $result . "[$task] .... seems ok to me",
    );
    my $output = $filter->put( [ \%result ] );
    print @$output;
}

sub handle_task_result {
    my ( $self, $a ) = @_;
    my $result = $a;
    print "\n\nResult for $result->{task}: [" . $result->{status} . "]\n";
    $self->{'SENTINEL_DATA'}->{'tasks'}->{ $result->{task} }->{'result'} =
      $result->{status};
}

sub handle_task_debug {
    my ( $self, $result ) = @_;
    print "Debug: $result\n";
}

sub handle_task_done {
    my ( $self, $k, $h, $task_id ) = @_;

    #print ">>DEBUG>>IN DONE :: task_id [$task_id]\n";

    my $config_task;
  POE_ID:
    while ( my ( $task, $id ) =
        ( each %{ $self->{'SENTINEL_DATA'}->{'poe_ids'} } ) )
    {
        if ( $id eq $task_id ) {
            $config_task = $task;
            last POE_ID;
        }
    }

    if ($config_task) {
        $self->{'SENTINEL_DATA'}->{'tasks'}->{$config_task}->{'running'} = 0;
        $self->{'SENTINEL_DATA'}->{'tasks'}->{$config_task}->{'last_ran'} =
          time();
    }
    my $dummy = Dumper( $self->{'SENTINEL_DATA'}->{'poe_ids'} );

    #sleep 1;
    delete $h->{task}->{$task_id};
    $k->yield("next_task");
}

sub sig_child {
    my ( $heap, $sig, $pid, $exit_val ) = @_[ HEAP, ARG0, ARG1, ARG2 ];
    my $details = delete $heap->{$pid};

    #warn "$$: Child $pid exited";
}

=head1 AUTHOR

Jon Brookes, C<< <marshyon at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-agent-sentinel at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Agent-Sentinel>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Agent::Sentinel


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Agent-Sentinel>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Agent-Sentinel>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Agent-Sentinel>

=item * Search CPAN

L<http://search.cpan.org/dist/Agent-Sentinel/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2010 Jon Brookes.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1;    # End of Agent::Sentinel
