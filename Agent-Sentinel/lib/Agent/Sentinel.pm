package Agent::Sentinel;

use Moose;    # automatically turns on strict and warnings
use Module::Pluggable require => 1, inner => 0;
use POE qw(Wheel::Run Filter::Reference);
use Config::Std;
use Net::Server::Daemonize qw(daemonize);

use Data::Dumper;

has 'config_file'    => ( is => 'rw' );
has 'debug'          => ( is => 'ro' );
has 'daemon'         => ( is => 'ro' );
has 'config'         => ( is => 'ro' );
has 'interval'       => ( is => 'ro' );
has 'pid_file'       => ( is => 'ro' );
has 'user'           => ( is => 'ro' );
has 'group'          => ( is => 'ro' );

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
    $self->{'config'} = load_config( $self->config_file() );

    $self->{'debug'} = ${$self->config}{'main'}{'debug'} || 0;
    $self->{'daemon'} = ${$self->config}{'main'}{'daemon'};
    $self->{'user'} = ${$self->config}{'main'}{'user'};
    $self->{'group'} = ${$self->config}{'main'}{'group'};
    $self->{'interval'} = ${$self->config}{'main'}{'interval'} || 300;
    ${$self->config}{'main'}{'pid_file_dir'} .= '/' unless ( ${$self->config}{'main'}{'pid_file_dir'} =~ m{/$} );

    $self->{'pid_file'} = ${$self->config}{'main'}{'pid_file_dir'} . ${$self->config}{'main'}{'pid_file'};

    #my $cf = $self->config_file();
    #%cfg = load_config($cf);


    # load a list of plugins and save to a hash for lookup
    #
    #map {
    #    if ( $_ =~ m{Sentinel::Plugin::(.+)} )
    #    {
    #        $self->{'plugins_hash'}->{$1}++;
    #        
    #        $sentinel_plugin = $_->new();
    #    }
    #} $self->plugins();
#
#
#    # store global 'default' config values from config for later use
#    #
#    $self->max_concurrent(
#        $self->{'config'}->{'sentinel'}{'max_concurrent_jobs'} );
#    $MAX = $self->max_concurrent();
#    $self->debug( $self->{'config'}->{'sentinel'}{'debug'} );
#    print "config is [" . $self->config_file . "]\n" if $self->debug();
#
#    # validate each section in config starting 'task <num>' to have
#    # a plugin installed of name 'type' in config
#    #
#    foreach my $section ( keys( %{ $self->{'config'} } ) ) {
#        next unless ( $section =~ m{^task \d+} );
#        if ( $self->{'plugins_hash'}
#            ->{ $self->{'config'}->{$section}->{'type'} } )
#        {
#            print "found plugin for [[$section]]\n" if $self->debug();
#            foreach my $plugin_param ( keys %{ $self->{'config'}->{$section} } )
#            {
#                print "\tparam : $plugin_param => "
#                  . $self->{'config'}->{$section}->{$plugin_param} . "\n" if $self->debug();
#            }
#        }
#    }
}

sub run {

    my $self = shift;

    if($self->daemon) {

        daemonize(
            $self->user(),
            $self->group(),
            $self->{'pid_file'},
        );

        while(1) {
            sleep 1;
        }
    }

    #$self->{'SENTINEL_DATA'} = \{ 'one' => 1, 'two' => 2, 'three' => 10 };
    #POE::Session->create(
    #inline_states => {
    #_start      => sub {  $self->start_tasks( $_[KERNEL], $_[HEAP] ) ; },
    #interval    => sub {  $self->time_check( $_[KERNEL], $_[HEAP], $_[ARG0] ) ; },
    #next_task   => sub {  $self->start_tasks( $_[KERNEL], $_[HEAP] ) ; },
    #task_result => sub {  $self->handle_task_result( $_[ARG0] ) ; },
    #task_done   => sub {  $self->handle_task_done( $_[KERNEL], $_[HEAP], $_[ARG0] ) ; },
    #task_debug  => sub {  $self->handle_task_debug( $_[ARG0] ) ; },
    #sig_child   => \&sig_child,
    #}
    #);
    #$poe_kernel->run();
}



# just starts tasks, nothing else
# a task may be started if it is time to do so
# time to run is decided upon by configured 'interval' time
# in the config file section of 'task <num>' section
# a task may not be run untill this time interval has elapsed
sub start_tasks {

    my( $self, $k, $h ) = @_;

    $k->alarm( interval => time() + 1, 0 );
    while ( keys( %{ $h->{task} } ) < $MAX ) {
        my $next_task = shift @tasks;
        last unless defined $next_task;
        print "Starting task for $next_task...\n";
        my $task = POE::Wheel::Run->new(
            Program => sub { do_stuff($next_task, $sentinel_plugin) },
            StdoutFilter => POE::Filter::Reference->new(),
            StdoutEvent  => "task_result",
            StderrEvent  => "task_debug",
            CloseEvent   => "task_done",
            );
        $h->{task}->{ $task->ID } = $task;
        $k->sig_child( $task->PID, "sig_child" );
    }
}

# checks for running tasks and starts new ones if old one has 
# finished - will continually call new task untill it is running
# it leaves the job of finding out if the job is ready to be run
# to start tasks
sub time_check {

    my( $self, $k, $h, $a ) = @_;

    print "<time check $a";

    foreach ( keys( %{ $h->{task} } ) ) {
        print "[$_]";
    }
    print "> ";
    print Dumper($self->{'SENTINEL_DATA'});
    $k->alarm( interval => time() + 1, $a + 1 );

}

sub do_stuff {
    binmode(STDOUT);
    my $task = shift;
    my $sentinel_plugin = shift;

    $sentinel_plugin->cmd('theres nothing for you here ...');
    my $result = $sentinel_plugin->run();

    if ( $task eq 'nine' ) {
        warn "I AM A BAD BOY\n";
        sleep 300;
    }
    my $filter = POE::Filter::Reference->new();

    sleep( rand 5 );

    my %result = (
        task   => $task,
        status => $result . " .... seems ok to me",
    ); 
    my $output = $filter->put( [ \%result ] );
    print @$output;
}

sub handle_task_result {
    my ($self, $a) = @_;
    my $result = $a;
    print "Result for $result->{task}: ------>" . $result->{status} . "<---------\n";
}

sub handle_task_debug {
    my ($self, $result) = @_;
    print "Debug: $result\n";
}

sub handle_task_done {
    my ( $self, $k, $h, $task_id ) = @_;
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

1; # End of Agent::Sentinel
