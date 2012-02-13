#===============================================================================
#
#         FILE: FileCopyTail.pm
#
#  DESCRIPTION:
#
#      VERSION: 1.0
#      CREATED: 20/08/11 16:21:56
#
#
# AUTHOR
#       Jon Brookes "<jon.brookes@ajbcontracts.co.uk>"
#
# LICENCE AND COPYRIGHT
#       Copyright (c) 2011, Jon Brookes "<jon.brookes@ajbcontracts.co.uk>". All
#       rights reserved.
#
#       This module is free software; you can redistribute it and/or modify it
#       under the same terms as Perl itself.
#
# DISCLAIMER OF WARRANTY
#       BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
#       FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
#       OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
#       PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
#       EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
#       WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#       THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS
#       WITH YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE
#       COST OF ALL NECESSARY SERVICING, REPAIR, OR CORRECTION.
#
#       IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
#       WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
#       REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE LIABLE
#       TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL, OR
#       CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE THE
#       SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
#       RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
#       FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
#       SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
#       SUCH DAMAGES.
#
#===============================================================================

package Agent::Sentinel::Util::FileCopyTail;

use feature ':5.10.0';
use Moose;
use Storable qw(store retrieve freeze thaw dclone);
use IO::File;
use IO::Dir;
use Digest::MD5 qw(md5_hex);
use Date::Parse;
use Date::Format;
use UUID::Tiny;
use Log::Log4perl qw(:easy);
use Data::Dumper;
use IPC::Open3;
use Symbol 'gensym';

has 'status_file_path'         => ( is => 'rw' );
has 'stop_copy_after_maxlines' => ( is => 'rw' );
has 'log_to'                   => ( is => 'rw' );
has 'buffer'                   => ( is => 'rw' );
has 'multi'                    => ( is => 'rw' );
has 'output_cmd'               => ( is => 'rw' );

=over

=item load_status

=back

load_status loads status file from previous run

it destroys and recreates same file if errors are 
encountered on load

=cut

sub load_status {

    my ( $self, $params ) = @_;

    Log::Log4perl->easy_init(
        {
            level => $DEBUG,
            file  => ">>$self->{'log_to'}"
        }
    );
    $self->{'seen'} = 1;

    my $statusfile = $params->{'status_file_path'}
      || $self->{'status_file_path'};
    $self->{'status_file_path'} = $statusfile;

    my %h = ( 'files' => undef );

    if ( !-e $statusfile ) {
        store( \%h, $statusfile );
        $self->{'seen'} = 0;
    }

    my $ref;
    eval {
        $ref = retrieve($statusfile)
          or LOGDIE "FATAL :: cannot retrieve status from [$statusfile]";
    };

    if ($@) {
        warn "WARNING :: errors encounterd retrieving "
          . "[$statusfile] :: $@ :: deleting file";
        unlink($statusfile);
        $self->{'seen'} = 0;
    }

    $self->{'sref'} = $ref;
}

=over

=item save_status

=back
 
save status accepts no parameter and saves status using 'store'
of storable fame, using internal variable set by accessors
 
=cut

sub save_status {

    my ( $self, $params ) = @_;

    store( $self->{'sref'}, $self->{'status_file_path'} );

}

=over

=item tie_directory

=back

accepts no parameters and opens directory using IO::Dir to do so

=cut

sub tie_directory {
    my ( $self, $param ) = @_;
    my $d = $param->{'dir'};
    tie %{ $self->{'dir'} }, 'IO::Dir', $d;
    return $self->{'dir'};
}

=over

=item examine_file

=back

examine file accepts 'file', 'dir', 'md5'
it uses md5 to check if this file has been
seen before

import_data_from is called if it has new
data

=cut



sub examine_file {

    my ( $self, $param ) = @_;

    my $file = $param->{'file'};
    my $dir  = $param->{'dir'};
    my $hash = $param->{'md5'};

    my $first_line;
    my $last_line;
    my $line_count = 0;
    my $from_line  = 1;

    my $fh = new IO::File;

    if ( $fh->open("< $dir/$file") ) {

        while (<$fh>) {
            $first_line = $_ if ( $line_count == 0 );
            $last_line = $_;
            $line_count++;
        }
        $fh->close;

        $self->{'sref'}->{'files'}->{$hash}->{'last'} = $last_line;
        $self->{'sref'}->{'files'}->{$hash}->{'modified'} =
          $self->{'dir'}->{$file}->mtime();
        $self->{'sref'}->{'files'}->{$hash}->{'first'} = $first_line
          if ( !exists $self->{'sref'}->{'files'}->{$hash}->{'first'} );
        $self->{'sref'}->{'files'}->{$hash}->{'created'} =
          $self->{'dir'}->{$file}->ctime()
          if ( !exists $self->{'sref'}->{'files'}->{$hash}->{'created'} );

        if ( !exists $self->{'sref'}->{'files'}->{$hash} ) {

            # create new entry
            $self->{'sref'}->{'files'}->{$hash}->{'lines'} = $line_count;
        }
        else {

            # update existing entry
            my $previous_line_count =
              $self->{'sref'}->{'files'}->{$hash}->{'lines'} || 0;
            if ( $previous_line_count < $line_count ) {
                $from_line = $self->{'sref'}->{'files'}->{$hash}->{'lines'};
                $self->{'sref'}->{'files'}->{$hash}->{'lines'} = $line_count;

            }
        }
        $self->import_data_from(
            {
                file      => $file,
                dir       => $dir,
                from_line => $from_line,
                to_line   => $line_count
            }
        );
    }
    else {
        warn "can't open file [$file] dir [$dir] : $!\n";
    }
}

=over

=item import_data_from

=back

import_data_from accepts 'file', 'dir', 'from_line', 'to_line

opens and reads in file to be imported

if lines are greater than 'stop_copy_after_maxlines', it drops out

it currently does the job of buffering multi-lines 

=cut

sub import_data_from {

    my ( $self, $param ) = @_;
    my $file      = $param->{'file'};
    my $dir       = $param->{'dir'};
    my $from_line = $param->{'from_line'} || 1;
    my $to_line   = $param->{'to_line'};

    open my $fh, '<', "$dir/$file"
      or LOGDIE "can't open $dir/$file for read : $!\n";

    my $count = 0;
  LINE:
    while (<$fh>) {
        $count++;

        $self->{'lines_copied'} = 0
          unless ( defined( $self->{'lines_copied'} ) );
        if ( $self->{'stop_copy_after_maxlines'} ) {
            next LINE
              if ( $self->{'lines_copied'} >=
                $self->{'stop_copy_after_maxlines'} );
        }

        next LINE
          unless ( ( $count > $from_line ) and ( $count <= $to_line ) );

        chomp();

        ## TODO : re-factor following into another sub

        # this test is to see if we have 'seen' a status file
        # basically, if there isnt a status file, this is a
        # first run, so we dont want to output anything untill
        # we have 'seen' this file or files matched before

        if ( $self->{'seen'} ) {

            if ( $self->{'buffer'} ) {

                my $current_line = "$_";

                given ($current_line) {

                    when ( $current_line =~ m{ $self->{'multi'} }msx ) {
                        $self->{'buffered_lines'} .= $current_line . "\n";
                    }
                    when ( $current_line !~ m{ $self->{'multi'} }msx ) {
                        if ( $self->{'buffered_lines'} ) {
                            $self->run_commands();
                            $self->{'buffered_lines'} = '';
                        }
                        $self->{'buffered_lines'} = $current_line . "\n";
                    }
                }
            }
            else {
                print "$_\n";
            }
            $self->{'lines_copied'}++;
        }
    }

    close $fh;

    # if buffering, output last line(s) here
    if ( $self->{'buffer'} ) {
        $self->run_commands();
        $self->{'buffered_lines'} = '';
    }
}

=over

=item run_commands

=back

run_commands accepts no parameters and uses an internally stored
list of commands to open pipes to each using IPC::Open3

=cut

sub run_commands {
    my ($self) = @_;
    my $err = gensym;

    foreach my $cmd ( @{ $self->{'output_cmd'} } ) {

        my ( $wtr, $rdr, $err, $pid );
        eval { $pid = open3( $wtr, $rdr, $err, $cmd ) };
        warn "$cmd could not be run at all : $@\n" if $@;
        if ( !$@ ) {
            print $wtr $self->{'buffered_lines'};
            close $wtr;
            while (<$rdr>) {
                print;
            }
            close $rdr;
        }
    }
}

=over

=item file_hash_id

=back

file_hash_id takes file name as parameter

it returns a digest using md5_hex

=cut

sub file_hash_id {

    my ( $self, $param ) = @_;
    my $file = $param->{'file'};

    open my $fh, '<', $file or LOGDIE "can't open $file for read : $!\n";
    my $first_line = <$fh> || '';
    if ( $first_line eq '' ) {
        return '';
    }
    close $fh;
    my $digest = md5_hex($first_line);
    chomp($first_line);

    return $digest;

}

=over

=item run

=back

the run sub is used to run the application

it accepts 'd' ( dir ), 'pattern_match' and 'oldest'

the directory is iterated, using a pattern match to locate
files of interest and ignorning anything older than oldest

each file is 'examined' and subsequently tested for 'import'

finally, old status information is cleared down in the state
persistent filestore

=cut

sub run {

    my ( $self, $param ) = @_;

    my $dir           = $param->{'d'};
    my $pattern_match = $param->{'pattern_match'};
    my $oldest        = $param->{'oldest'};

    $self->{'multi'} = '^\s+' unless $self->{'multi'};

    # TODO : if multi line specified, but no commmands error and die

    $self->load_status();
    $self->tie_directory( { dir => $dir } );
    $self->{'now'} = time();

  FILE:

    foreach my $file (
        sort {

            # numeric sort of keys in hash by value
            $self->{'dir'}->{$a}->mtime() <=> $self->{'dir'}->{$b}->mtime();
        }
        keys( %{ $self->{'dir'} } )
      )
    {

        next FILE unless ( $file =~ m{$pattern_match} );

        $self->{'age'} = $self->{'now'} - $self->{'dir'}->{$file}->mtime();
        next FILE if ( $self->{'age'} > $oldest );

        # get hash key for this file based upon an md5hex of
        # the files first line and its creation time
        my $file_md5 = $self->file_hash_id( { 'file' => "$dir/$file" } );

        if ( exists $self->{'sref'}->{'files'}->{$file_md5} ) {

            if ( $self->{'dir'}->{$file}->mtime() ==
                $self->{'sref'}->{'files'}->{$file_md5}->{'modified'} )
            {
                next FILE;
            }
        }
        else {
            $self->{'seen'} = 0;
        }

        $self->examine_file(
            {
                dir  => $dir,
                file => $file,
                md5  => $file_md5
            }
        );
    }

    # DELETE ANY STATUS INFORMATION OLDER THAN 'oldest'
    foreach my $key ( keys( %{ $self->{'sref'} } ) ) {
        if ( !defined( $self->{'sref'}->{'files'}->{$key}->{'modified'} ) ) {
            last;
        }
        my $self->{'age'} =
          $self->{'now'} - $self->{'sref'}->{'files'}->{$key}->{'modified'};
        if ( $self->{'age'} > $oldest ) {
            delete( $self->{'sref'}->{'files'}->{$key} );
        }
    }

    $self->save_status();

}

return 1;
