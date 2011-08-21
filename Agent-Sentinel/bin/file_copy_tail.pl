#!/usr/bin/env perl

use strict;
use warnings;

$| = 1;

use 5.010;
use strict;
use warnings;

use IO::Dir;
use IO::File;
use File::Copy;
use Data::Dumper;
use Log::Log4perl qw(:easy);
use Digest::MD5 qw(md5_hex);
use Date::Parse;
use Date::Format;
use UUID::Tiny;
use Config::Std;
use Getopt::Std;

use Getopt::Long;

use vars qw(
  $help $verbose
  $statusfile
  $directory
  $file_match
  $ignore_file_older_than_seconds
  $logfile
  $stop_copy_after_maxlines
);

GetOptions(
    "verbose"                           => \$verbose,
    "help"                              => \$help,
    "statusfile=s"                      => \$statusfile,
    "directory=s"                       => \$directory,
    "file_match=s"                      => \$file_match,
    "ignore_files_older_than_seconds=n" => \$ignore_file_older_than_seconds,
    "logfile=s"                         => \$logfile,
    "stop_copy_after_maxlines=n"        => \$stop_copy_after_maxlines,
);

use Agent::Sentinel::Util::FileCopyTail;
use YAML::Tiny;

my %opts = ();
getopts( 'ic:', \%opts );

usage_die() if $help;

# VALIDATE COMMAND LINE OPTIONS

if ( !$statusfile ) {
    print "\nERROR :: no statusfile specified\n";
    usage_die();
}
else {
    print "using statusfile [$statusfile]\n" if $verbose;
}

if ( !$directory ) {
    print "\nERROR :: no directory specified\n";
    usage_die();
}
else {
    print "searching directory [$directory]\n" if $verbose;
}

if ( !$file_match ) {
    print "\nERROR :: no file_match specified\n";
    usage_die();
}
else {
    print "using file match [$file_match]\n" if $verbose;
}

if ( !$ignore_file_older_than_seconds ) {
    print "\nERROR :: no ignore_file_older_than_seconds specified\n";
    usage_die();
}
else {
    print
      "ignoring files older than [$ignore_file_older_than_seconds] seconds\n"
      if $verbose;
}

if ( !$logfile ) {
    print "\nERROR :: no logfile specified\n";
    usage_die();
}
else {
    print "writing to logfile [$logfile]\n" if $verbose;
}

if ($stop_copy_after_maxlines && $verbose) {
    print "will stop output after a maximum of "
      . "[$stop_copy_after_maxlines] lines\n";
}
Log::Log4perl->easy_init(
    {
        level => $DEBUG,
        file  => ">>$logfile"
    }
);

LOGDIE "directory $directory does not exist\n" unless ( -d $directory );

my $fct = Agent::Sentinel::Util::FileCopyTail->new(
    'status_file_path'         => $statusfile,
    'stop_copy_after_maxlines' => $stop_copy_after_maxlines,
    'log_to'                   => $logfile,
);

$fct->run(
    {
        'd'             => $directory,
        'pattern_match' => $file_match,
        'oldest'        => $ignore_file_older_than_seconds,
    }
);

sub usage_die {

    print <<EOF;

$0 

file copy tail - takes a directory, file name ( regex ) specification and
                 command line parameters ( see below )

prints to standard output the last line of files not seen by previous run

maintains state between each invocation

will optionaly stop outputing after a max limit of lines ( where files 
are bloated by excessive application log output )

the first run will not output anything but will save the size of the 
current file(s) to be watched

the pattern match can be used to match multiple files, trapping instances
where log files are rotated and renamed

USAGE

$0 --statusfile <full path to status file> \\
   --directory <full directory path> \\
   --file_match <pattern to match files in directory by> \\
   --ignore_file_older_than_seconds <number> \\
   --logfile <full path to logfile for this process>

optional

   --stop_copy_after_maxlines <number>
   --verbose

parameters may be shortened if they do not lose their individual identity, for example:

$0 --status /tmp/status.str \\
   --dir /var/log/dansguardian/ \\
   --file_m 'dansguardian\.log\$' \\
   --ignore 1800 \\
   --log /var/log/fct_dans.log \\
   --stop_copy_after 1000

AUTHOR
       Jon Brookes "<jon.brookes <at> ajbcontracts.co.uk>"

LICENCE AND COPYRIGHT
       Copyright (c) 2011, Jon Brookes "<jon.brookes <at> ajbcontracts.co.uk>". All rights reserved.

       This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

DISCLAIMER OF WARRANTY
       BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY FOR THE SOFTWARE, 
       TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN OTHERWISE STATED IN WRITING THE 
       COPYRIGHT HOLDERS AND/OR OTHER PARTIES PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF 
       ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
       OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE ENTIRE RISK AS TO THE QUALITY AND
       PERFORMANCE OF THE SOFTWARE IS WITH YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE 
       COST OF ALL NECESSARY SERVICING, REPAIR, OR CORRECTION.

       IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING WILL ANY COPYRIGHT HOLDER,
       OR ANY OTHER PARTY WHO MAY MODIFY AND/OR REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE 
       LICENCE, BE LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL, OR 
       CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE THE SOFTWARE (INCLUDING 
       BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING RENDERED INACCURATE OR LOSSES
       SUSTAINED BY YOU OR THIRD PARTIES OR A FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER 
       SOFTWARE), EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF 
       SUCH DAMAGES.

EOF

    exit;
}

