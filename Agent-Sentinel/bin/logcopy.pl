#!/usr/bin/env perl
#===============================================================================
#
#         FILE:  logcopy.pl
#
#        USAGE:  ./logcopy.pl  -c configfile
#
#  DESCRIPTION:  script that will 'tail' files within a directory structure 
#                files may be 'rotated' - that is change name and will be 
#                processed in the order in which they were last modified, oldest
#                first
#                status information is stored in a yaml file so that the next run
#                picks up where the last one left off
#                log file lines are printed to standard output 
#
#       AUTHOR:  jon brookes ( marshyon ( at ) gmail.com ), 
#      COMPANY:  
#      VERSION:  1.0
#      CREATED:  22/03/11 22:37:16
#     REVISION:  ---
#===============================================================================

use strict;
use warnings;

use 5.010;
use strict;
use warnings;

use IO::Dir;
use IO::File;
use File::Copy;
use Data::Dumper;
use YAML;
use Log::Log4perl qw(:easy);
use Digest::MD5 qw(md5_hex);
use Date::Parse;
use Date::Format;
use UUID::Tiny;
use Config::Std;
use Getopt::Std;

my %opts = ();
getopts('c:', \%opts);

die "\nERROR :: no configuration file specified :: USAGE :: \n\n$0 -c <full_path_to_config_file>\n\n" unless $opts{c};

die "\nERROR :: no configuration found as specified [$opts{c}]\n\n" unless ( -e $opts{c} );

read_config $opts{c} => my %config;

# SANITISE CONFIG FILE
die "\nERROR :: no \"[main] logfile = <logfile>\" entry found in $opts{c}\n\n" unless $config{'main'}{'logfile'};
my $log   = $config{'main'}{'logfile'};

die "\nERROR :: no \"[main] directory = <logfile_directoy>\" entry found in $opts{c}\n\n" unless $config{'main'}{'directory'};
my $dir = $config{'main'}{'directory'};


die "\nERROR :: no \"[main] status_file = <path_to_yaml_status_file>\" entry found in $opts{c}\n\n" unless $config{'main'}{'status_file'};
my $status_file = $config{'main'}{'status_file'};

die "\nERROR :: no \"[main] file_match = <pattern_match>\" entry found in $opts{c}\n\n" unless $config{'main'}{'file_match'};
my $pattern_match = $config{'main'}{'file_match'};

# no interested in files not mofied for 'oldest' time
my $oldest = $config{'main'}{'ignore_file_older_than_seconds'} || ( 60 * 60 * 24 * 10 ); # 10 days

my $status_ref;
my $count = 0;

Log::Log4perl->easy_init(
    {
        level => $WARN,
        file  => ">>$log"
    }
);

if ( -e $status_file ) {
    $status_ref = YAML::LoadFile($status_file);
}

LOGDIE "directory $dir does not exist\n" unless ( -d $dir );
my %dir = ();
tie %dir, 'IO::Dir', $dir;

# sub used by sort to do numeric sort of keys in hash by value
sub hashValueAscendingNum {
    $dir{$a}->mtime() <=> $dir{$b}->mtime();
}

my $now = time();

FILE:
foreach my $file ( sort hashValueAscendingNum ( keys(%dir) ) ) {

    next FILE unless ( $file =~ m{$pattern_match} );
    my $age = $now - $dir{$file}->mtime() ;
    next FILE if ($age > $oldest) ;

    DEBUG "DEBUG :: file : [$file]";

    DEBUG "DEBUG :: \tmodified : ["
      . scalar localtime( $dir{$file}->mtime() ) . "]";

    DEBUG "DEBUG :: \tcreated  : ["
      . scalar localtime( $dir{$file}->ctime() ) . "]";

    # get hash key for this file based upon an md5hex of
    # the files first line and its creation time
    #
    my $file_md5 = file_hash_id("$dir/$file");

    if ( exists $status_ref->{$file_md5} ) {
        DEBUG "DEBUG :: \twe've seen $file before";
        if ( $dir{$file}->mtime() == $status_ref->{$file_md5}->{'modified'} ) {
            DEBUG "DEBUG :: \tmodified time is same";
            next FILE;
        }
        else {
            DEBUG "DEBUG :: \tmodified time CHANGED...";
        }
    }
    else {
        DEBUG "\tDEBUG :: never seen $file before";
    }

    examine_file(
        {
            dir  => $dir,
            file => $file,
            sref => $status_ref,
            md5  => $file_md5
        }
    );
}


# DELETE ANY STATUS INFORMATION OLDER THAN 'oldest' 
foreach my $key (keys(%{$status_ref})) {
    my $age = $now - $$status_ref{$key}->{'modified'};
    if($age > $oldest) {
        delete($$status_ref{$key});
    }
}

YAML::DumpFile( $status_file, $status_ref );

# SUBS
#
sub examine_file {

    my ($param) = @_;

    my $file = $param->{'file'};
    my $dir  = $param->{'dir'};
    my $ref  = $param->{'sref'};
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

        DEBUG "DEBUG :: \tlines      : [$line_count]";
        DEBUG "DEBUG :: \tfirst line : [$first_line]" if $first_line;
        DEBUG "DEBUG :: \tlast line  : [$last_line]"  if $last_line;

        $ref->{$hash}->{'last'}     = $last_line;
        $ref->{$hash}->{'modified'} = $dir{$file}->mtime();
        $ref->{$hash}->{'first'}    = $first_line
          if ( !exists $ref->{$hash}->{'first'} );
        $ref->{$hash}->{'created'} = $dir{$file}->ctime()
          if ( !exists $ref->{$hash}->{'created'} );

        if ( !exists $ref->{$hash} ) {

            DEBUG "\tDEBUG :: new entry, file hash : [$hash]";

            # create new entry
            $ref->{$hash}->{'lines'} = $line_count;

        }
        else {

            # update existing entry
            DEBUG "\tDEBUG :: update, file hash : [$hash]";
            my $previous_line_count = $ref->{$hash}->{'lines'} || 0;
            if ( $previous_line_count < $line_count ) {
                $from_line = $ref->{$hash}->{'lines'};
                $ref->{$hash}->{'lines'} = $line_count;

            }
        }
        import_data_from(
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

sub import_data_from {

    my ($param) = @_;
    my $file    = $param->{'file'};
    my $dir     = $param->{'dir'};
    my $from_line = $param->{'from_line'} || 1;
    my $to_line = $param->{'to_line'};

    DEBUG "DEBUG :: importing [$dir][$file] [$from_line][$to_line] ...";

    open my $fh, '<', "$dir/$file"
      or LOGDIE  "can't open $dir/$file for read : $!\n";

    my $count = 0;
  LINE:
    while (<$fh>) {
        $count++;

        next LINE
          unless ( ( $count >= $from_line ) and ( $count <= $to_line ) );
        chomp();

        print "$dir :: $file :: $_\n";

    }

    close $fh;
}

sub file_hash_id {

    my $file = shift;
    open my $fh, '<', $file or LOGDIE  "can't open $file for read : $!\n";
    my $first_line = <$fh> || '';
    if ( $first_line eq '' ) {
        return '';
    }
    close $fh;
    my $digest = md5_hex($first_line);
    return $digest;

}

__END__

config file should look like : 


[main]

logfile = logcopy.log
directory = /var/log/dansguardian
status_file = logcopy_status.yaml
# oldest files - 10 days
ignore_file_older_than_seconds = 864000


