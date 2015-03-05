use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Text::Balanced',
    AUTHOR              => 'Damian Conway <DCONWAY@CPAN.org>',
    VERSION_FROM        => 'lib/Text/Balanced.pm',
    ABSTRACT_FROM       => 'lib/Text/Balanced.pm',
    INSTALLDIRS         => ($] >= 5.007003 ? 'perl' : 'site'),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Text-Balanced-*' },
);
