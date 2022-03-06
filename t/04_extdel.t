use 5.008001;

use strict;
use warnings;
use Test::More;
use Text::Balanced qw ( extract_delimited );

our $DEBUG;
sub debug { print "\t>>>",@_ if $DEBUG }

## no critic (BuiltinFunctions::ProhibitStringyEval)

my $cmd = "print";
my $neg = 0;
my $str;
while (defined($str = <DATA>))
{
    chomp $str;
    if ($str =~ s/\A# USING://) { $neg = 0; $cmd = $str; next; }
    elsif ($str =~ /\A# TH[EI]SE? SHOULD FAIL/) { $neg = 1; next; }
    elsif (!$str || $str =~ /\A#/) { $neg = 0; next }
    $str =~ s/\\n/\n/g;
    debug "\tUsing: $cmd\n";
    debug "\t   on: [$str]\n";

    my $var = eval "() = $cmd";
    is $@, '', 'no error';
    debug "\t list got: [$var]\n";
    debug "\t list left: [$str]\n";
    ($neg ? \&isnt : \&is)->(substr($str,pos($str)||0,1), ';');

    pos $str = 0;
    $var = eval $cmd;
    is $@, '', 'no error';
    $var = "<undef>" unless defined $var;
    debug "\t scalar got: [$var]\n";
    debug "\t scalar left: [$str]\n";
    ($neg ? \&unlike : \&like)->( $str, qr/\A;/);
}

my $text = 'while($a == "test"){ print "true";}';
my ($extracted, $remainder) = extract_delimited($text, '#');
ok '' ne $@, 'string overload should not crash';

done_testing;

__DATA__
# USING: extract_delimited($str,'/#$',undef,'/#$');
/a/;
/a///;
#b#;
#b###;
$c$;
$c$$$;

# TEST EXTRACTION OF DELIMITED TEXT WITH ESCAPES
# USING: extract_delimited($str,'/#$',undef,'\\');
/a/;
/a\//;
#b#;
#b\##;
$c$;
$c\$$;

# TEST EXTRACTION OF DELIMITED TEXT
# USING: extract_delimited($str);
'a';
"b";
`c`;
'a\'';
'a\\';
'\\a';
"a\\";
"\\a";
"b\'\"\'";
`c '\`abc\`'`;

# TEST EXTRACTION OF DELIMITED TEXT
# USING: extract_delimited($str,'/#$','-->');
-->/a/;
-->#b#;
-->$c$;

# THIS SHOULD FAIL
$c$;
