use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Text::Balanced',
    license             => 'perl',
    dist_author         => 'Damian Conway <DCONWAY@CPAN.org>',
    dist_version_from   => 'lib/Text/Balanced.pm',
    requires => {
        'Test::More' => 0,
    },
    add_to_cleanup      => [ 'Text-Balanced-*' ],
);

$builder->create_build_script();
