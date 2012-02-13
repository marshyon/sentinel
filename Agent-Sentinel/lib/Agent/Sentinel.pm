package Agent::Sentinel;

use feature ':5.10';
use Moose;

use Module::Pluggable require => 1, inner => 0;

use POE qw(Wheel::Run Filter::Reference);
use Config::Std;
use Net::Server::Daemonize qw(daemonize);
use YAML;
use Data::Dumper;
use List::Util qw(first);
use Cwd;
use Log::Log4perl qw(:easy);

has 'config_file' => ( is => 'rw' );
has 'log_file'    => ( is => 'rw' );
has 'debug'       => ( is => 'ro' );
has 'daemon'      => ( is => 'ro' );
has 'cfg'         => ( is => 'ro' );
has 'interval'    => ( is => 'ro' );
has 'pid_file'    => ( is => 'ro' );
has 'user'        => ( is => 'ro' );
has 'group'       => ( is => 'ro' );
has 'status_dir'  => ( is => 'ro' );
has 'sd'          => ( is => 'rw' );

#my $MAX;
#my @tasks = qw(one two three four five six seven eight nine ten);
#my $sentinel_plugin;

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

=head2 load_config

TODO - add docs 

=cut

sub load_config {
	my $file = shift;
	read_config $file => my %cfg;
	return \%cfg;
}

=over

=item init

=back

TODO - add docs 

=cut

sub init {
	my $self = shift;
	my $debug_log = $self->log_file || '/tmp/sentinel_debug.log';
	Log::Log4perl->easy_init(
		{
			level => $DEBUG,
			file  => ">>$debug_log"
		}
	);

	# load config file and store for object access
	$self->{'cfg'} = load_config( $self->config_file() );

	# store current working directory in 'STACK' for later use
	my $working_dir;
	if ( ${ $self->cfg }{'main'}{'working_directory'} ) {
		$working_dir = ${ $self->cfg }{'main'}{'working_directory'};
	}
	$working_dir = getcwd unless $working_dir;
	chdir($working_dir);

	$self->{'STACK'}->{'working_dir'} = "$working_dir/status.yaml";

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

	# validate each section in config starting 'task <num>' to have
	# a plugin installed of name 'type' in config
	#

  SECTION:
	foreach my $section ( keys( %{ $self->{'cfg'} } ) ) {

		# skip sections not beginning with [task ....]
		next SECTION unless ( $section =~ m{^task \d+} );

		# find plugins of type config 'type'
		my $config_plugin_name = $self->{'cfg'}{$section}->{'type'};

		# skip any configs without a configured type
		if ( !$config_plugin_name ) {
			warn "WARNING :: NO PLUGIN found "
			  . "for [$section] type = '<plugin type - see docs>'\n";
			next SECTION;
		}

		# lookup plugin name from this objects plugins matching 'type'
		my $plugin_name =
		  first { $_ =~ m{.+?$config_plugin_name$}mxs } $self->plugins();

		# skip any configured jobs that do not have a matching
		# plugin to their type
		if ( !$plugin_name ) {
			warn "WARNING :: NO PLUGIN found for "
			  . "[$section] type = $config_plugin_name\n"
			  . Dumper( $self->plugins() );
			next SECTION;
		}

		# save for this task its plugin name for later instantiation
		$self->{'STACK'}->{'tasks'}->{$section}->{'task_plugin'} = $plugin_name;

		# extract the config for this task, store into a hash
		my %section_config = ();
		foreach my $plugin_param ( keys %{ $self->{'cfg'}->{$section} } ) {

			$section_config{$plugin_param} =
			  $self->{'cfg'}->{$section}->{$plugin_param};
		}

		# copy config hash to objects stash for this task for passing
		# to plugin when instantiated and run
		$self->{'STACK'}->{'tasks'}->{$section}->{'config'} = \%section_config;

	}
}

=over

=item run

=back

starts the POE Session - this is like 'main' where the whole of POE
is controlled by each 'inline_state(s)' there after

=cut

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

=over

=item start_tasks

=back

just starts tasks, nothing else
a task may be started if it is time to do so
time to run is decided upon by configured 'interval' time
in the config file section of 'task <num>' section
a task may not be run untill this time interval has elapsed

=cut

sub start_tasks {

	my ( $self, $k, $h ) = @_;

  CONFIG:
	foreach my $config_task ( keys( %{ $self->{'STACK'}->{'tasks'} } ) ) {

		my $running = $self->{'STACK'}->{'tasks'}->{$config_task}->{'running'}
		  || 0;
		my $last_ran = $self->{'STACK'}->{'tasks'}->{$config_task}->{'last_ran'}
		  || 0;
		my $interval =
		  $self->{'STACK'}->{'tasks'}->{$config_task}->{'config'}->{'interval'}
		  || 300;
		my $last_started_at =
		  $self->{'STACK'}->{'tasks'}->{$config_task}->{'started_at'} || 0;
		my $run_immediate =
		  $self->{'STACK'}->{'tasks'}->{$config_task}->{'config'}
		  ->{'run_immediate'};

		# skip runnig tasks
		next CONFIG
		  if ( $self->{'STACK'}->{'tasks'}->{$config_task}->{'running'} );

		# now run only jobs that are scheduled to run
		my $now                     = time();
		my $elapsed_since_end_run   = $now - $last_ran;
		my $elapsed_since_start_run = $now - $last_started_at;
		if (
			$self->time_to_run(
				{
					e => $elapsed_since_end_run,
					s => $elapsed_since_start_run,
					i => $interval,
					n => $now,
					t => $config_task,
					r => $run_immediate,
				}
			)
		  )
		{

			# it is time for this task to run

			$self->{'STACK'}->{'tasks'}->{$config_task}->{'running'} = 1;
			my $sentinel_plugin =
			  $self->{'STACK'}->{'tasks'}->{$config_task}->{'task_plugin'}
			  ->new();

			my $sentinel_config =
			  $self->{'STACK'}->{'tasks'}->{$config_task}->{'config'};



			# POE's Wheel::Run takes a reference to a subroutine which will
			# itself be spawned as a child process - we call this sub here
			# 'child_process'

			my $task = POE::Wheel::Run->new(
				Program => sub {
					child_process( $config_task, $sentinel_plugin,
						$sentinel_config );
				},
				StdoutFilter => POE::Filter::Reference->new(),
				StdoutEvent  => "task_result",
				StderrEvent  => "task_debug",
				CloseEvent   => "task_done",
			);
			my $poe_id = $task->ID;
			$h->{task}->{$poe_id} = $task;
			$k->sig_child( $task->PID, "sig_child" );
			$self->{'STACK'}->{'poe_ids'}->{$config_task} = $poe_id;
			$self->{'STACK'}->{'tasks'}->{$config_task}->{'started_at'} = $now;

			$self->{'STACK'}->{'tasks'}->{$config_task}->{'pid'} = $task->PID;
		}
	}

	# create an alarm to set off 'time_check' 1 second from now
	$k->alarm( time_check => time() + 1, 0 );

}

=over

=item time_to_run

=back

returns true if it is 'time to run'

if our 'interval' is a figure divisible into a minute or hour period,
only run when it is on the second of the division, for example 300 seconds
being 5 minutes will run on each 5th minute of the hour
this can be disabled in config for this task if run_immediate is set
failing the above, simply run if the interval of time since last run has
passed

=cut

sub time_to_run {

	my ( $self, $param ) = @_;
	my $elapsed_since_end_run   = $param->{'e'};
	my $interval                = $param->{'i'};
	my $now                     = $param->{'n'};
	my $task                    = $param->{'t'};
	my $run_immediate           = $param->{'r'};
	my $elapsed_since_start_run = $param->{'s'};

	given ($interval) {
		when ( ( ( ( 60 % $interval ) == 0 ) || ( ( 3600 % $interval ) == 0 ) )
			  && !$run_immediate )
		{
			if (   ( ( $now % $interval ) == 0 )
				&& ( $elapsed_since_start_run >= $interval ) )
			{
				DEBUG "DEBUG :: INTERVAL MIN/HOUR running [" . $task
				  . "] elapsed since start [$elapsed_since_start_run] interval[$interval]";
				return 1;
			}
		}
		default {
			if ( $elapsed_since_end_run >= $interval ) {
				DEBUG "DEBUG :: running [" . $task
				  . "] elapsed since end [$elapsed_since_end_run] interval[$interval]";
				return 1;
			}
		}
	}
	return 0;
}

=over

=item time_tick

=back

checks for running tasks and starts new ones if old one has
finished - will continually call new task untill it is running
it leaves the job of finding out if the job is ready to be run
to start tasks

=cut

sub time_tick {

	my ( $self, $k, $h, $a ) = @_;

	print '.';

	YAML::DumpFile( $self->{'STACK'}->{'working_dir'},
		$self->{'STACK'}->{'tasks'} );
	$k->alarm( time_check => time() + 1, $a + 1 );
	$self->start_tasks( $k, $h );

}

=over

=item child_process

=back

TODO - add docs 

=cut

sub child_process {

	binmode(STDOUT);
	my $task            = shift;
	my $sentinel_plugin = shift;
	my $config          = shift;

	$sentinel_plugin->cfg($config);
	$sentinel_plugin->task($task);

	my $result = $sentinel_plugin->run();

	my $filter = POE::Filter::Reference->new();

	my %result = (
		task   => $task,
		status => $result,
	);
	my $output = $filter->put( [ \%result ] );
	print @$output;
}

=over

=item handle_task_result

=back

TODO - add docs 

=cut

sub handle_task_result {
	my ( $self, $a ) = @_;
	my $result = $a;


	# CHECK OUTPUT RESULTS
	
	# if there is 'tagged' yaml output from plugin ...
	if($result->{status} =~ m{<yaml>(.+?)</yaml>}msxi) {

	    my %yaml = ();
	    eval{
	    	# try to get a hash of loaded yaml
	    	%yaml = %{ YAML::Load($1) };
	    };

	    my %args = ();
	    my @args_list = ();
	    
	    # if yaml loaded successefully ....
	    if(!$@){
	        while(my($key, $val) = each(%yaml)) {
	        	# save arguments into a temporary hash
	        	$args{$key} = $val;
	        }
	    }
	    
	    # if we saved arguments ...
	    if(%args) {

            # save each hash element to a list 
	        while( my($key, $val) = each( %{ $args{'args'} } ) )    {
	            push @args_list, $key . ' ' . $val;
	        }

            # save the list to our 'STACK', config, args for current task
	        $self->{'STACK'}->{'tasks'}->{ $result->{task} }->{'config'}->{'args'} = \@args_list;
	        print "ran task[".$result->{'task'}."] and found [".@args_list."] args in YAML output\n";
	    }
	    else {
	    	print "no args found in YAML\n"
	    }
	}
	else {
		# just print resultant output, as there was no 'YAML' embedded
	    print "\n$result->{task} status ::\n" . $result->{status}."\n-----\n";
	}
	$self->{'STACK'}->{'tasks'}->{ $result->{task} }->{'result'} =
	  $result->{status};
}

=over

=item handle_task_debug

=back

TODO - add docs 

=cut

sub handle_task_debug {
	my ( $self, $result ) = @_;
	print "Debug: $result\n";
}

=over

=item handle_task_done

=back

TODO - add docs 

=cut

sub handle_task_done {
	my ( $self, $k, $h, $task_id ) = @_;

	my $config_task;
  POE_ID:
	while ( my ( $task, $id ) = ( each %{ $self->{'STACK'}->{'poe_ids'} } ) ) {
		if ( $id eq $task_id ) {
			$config_task = $task;
			last POE_ID;
		}
	}

	if ($config_task) {
		$self->{'STACK'}->{'tasks'}->{$config_task}->{'running'}  = 0;
		$self->{'STACK'}->{'tasks'}->{$config_task}->{'last_ran'} = time();
	}

	# TODO : find out what is going on here for this to have to be
	#        done - autovivication is suspected
	my $dummy = Dumper( $self->{'STACK'}->{'poe_ids'} );

	delete $h->{task}->{$task_id};
	$k->yield("next_task");
}

=over

=item sig_child

=back

TODO - add docs 

=cut

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
