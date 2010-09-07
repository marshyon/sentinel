use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Agent::Sentinel',
    AUTHOR              => q{Jon Brookes <marshyon@gmail.com>},
    VERSION_FROM        => 'lib/Agent/Sentinel.pm',
    ABSTRACT_FROM       => 'lib/Agent/Sentinel.pm',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Agent-Sentinel-*' },
);
