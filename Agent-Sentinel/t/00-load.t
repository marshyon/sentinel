#!perl

use Test::More tests => 1;
use FindBin qw($Bin);
use lib "$Bin/../lib";

BEGIN {
    use_ok( 'Agent::Sentinel' ) || print "Bail out!
";
}

diag( "Testing Agent::Sentinel $Agent::Sentinel::VERSION, Perl $], $^X" );
