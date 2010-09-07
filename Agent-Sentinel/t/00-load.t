#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Agent::Sentinel' ) || print "Bail out!
";
}

diag( "Testing Agent::Sentinel $Agent::Sentinel::VERSION, Perl $], $^X" );
