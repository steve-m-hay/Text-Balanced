# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..65\n"; }
END {print "not ok 1\n" unless $loaded;}
use Text::Balanced qw ( :ALL );
$loaded = 1;
print "ok 1\n";
$count=2;
# sub debug { print "\t>>>",@_ }
sub debug {}

######################### End of black magic.


# $text = q{$var = do {"val" && $val;};};
# print "[", join('|', extract_multiple($text,undef,1)), "]\n";
# print "[", join('|', extract_multiple($text,undef,2)), "]\n";
# print "[", join('|', extract_multiple($text,undef,3)), "]\n";
# print "[", join('|', extract_multiple($text,undef,4)), "]\n";
# print "[", join('|', extract_multiple($text,undef,5)), "]\n";
# print "[", join('|', extract_multiple($text)), "]\n";
# 
# $text = q{$var = "val" && (1,2,3);};
# print "[", join('|', extract_multiple($text)), "]\n";
# 
# print "[", join('|', extract_multiple($text,[\&extract_bracketed])), "]\n";

$cmd = "print";
$neg = 0;
while (defined($str = <DATA>))
{
	chomp $str;
	if ($str =~ s/\A# USING://) { $neg = 0; $cmd = $str; next; }
	elsif ($str =~ /\A# TH[EI]SE? SHOULD FAIL/) { $neg = 1; next; }
	elsif (!$str || $str =~ /\A#/) { $neg = 0; next }
	$str =~ s/\\n/\n/g;
	debug "\tUsing: $cmd\n";
	debug "\t   on: [$str]\n";
	$var = eval $cmd;
	debug "\t left: [$str]\n";
	print "not " if ($str =~ '\A;')==$neg;
	print "ok ", $count++;
	print " ($@)" if $@;
	print "\n";
}

__DATA__
# USING: extract_codeblock($str,'<>');
< %x = () >;
< %x = ( try => "this") >;
< %x = ( $try->{this}, "too") >;

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

# USING: extract_quotelike($str);
# THESE SHOULD FAIL
s<$self->{pat}>{$self->{sub}};
s-$self->{pap}-$self->{sub}-;

# USING: extract_bracketed($str,'<"`q>');
<a q{uoted} ">" unbalanced right bracket of /(q>)/ either sort (`>>>""">>>>`) is okay >;

# USING: use 5.005; extract_tagged($str,qr/<[A-Z]+>/,undef, undef, {ignore=>["<BR>"]});
	<A>aaa<B>bbb<BR>ccc</B>ddd</A>;

# USING: extract_codeblock($str,'{}');
{ $a = $b; # what's this doing here? \n };'
{ $a = $b; \n $a =~ /$b/; \n @a = map /\s/ @b };

# THIS SHOULD FAIL
{ $a = $b; # what's this doing here? };'

# USING: extract_tagged($str,";","-",undef,{reject=>[";"],fail=>"MAX"});
	; at the ;-) keyword

# USING: extract_tagged($str,"BEGIN","END");
	BEGIN at the BEGIN keyword and END at the END;
	BEGIN at the beginning and end at the END;

# USING: extract_tagged($str,undef,undef,undef,{ignore=>["<[^>]*/>"]});
	<A>aaa<B>bbb<BR/>ccc</B>ddd</A>;

# USING: extract_tagged($str,"<[A-Z]+>",undef, undef, {ignore=>["<BR>"]});
	<A>aaa<B>bbb<BR>ccc</B>ddd</A>;

# THESE SHOULD FAIL
	BEGIN at the beginning and end at the end;
	BEGIN at the BEGIN keyword and END at the end;

# TEST EXTRACTION OF TAGGED STRINGS
# USING: extract_tagged($str,"BEGIN","END",undef,{reject=>["BEGIN","END"]});
# THESE SHOULD FAIL
	BEGIN at the BEGIN keyword and END at the end;

# USING: extract_tagged($str,";","-",undef,{reject=>[";"],fail=>"PARA"});
	; at the ;-) keyword


# USING: extract_tagged($str);
	<A>some text</A>;
	<B>some text<A>other text</A></B>;
	<A>some text<A>other text</A></A>;
	<A HREF="#section2">some text</A>;

# THESE SHOULD FAIL
	<A>some text
	<A>some text<A>other text</A>;
	<B>some text<A>other text</B>;


# USING: extract_bracketed($str,'<">');
<a quoted ">" unbalanced right bracket is okay >;

# USING: extract_bracketed($str,'<"`>');
<a quoted ">" unbalanced right bracket of either sort (`>>>""">>>>`) is okay >;

# THIS SHOULD FAIL
<a misquoted '>' unbalanced right bracket is bad >;

# TEST EXTRACTION OF VARIABLES
# USING: extract_variable($str);
$a;
$_;
$a[1];
$_[1];
$a{cat};
$_{cat};
$a->[1];
$a->{"cat"}[1];
@$listref;
@{$listref};
@{$obj->nextval};
@{$obj->nextval($cat,$dog)->{new}};
@{$obj->nextval($cat?$dog:$fish)->{new}};
@{$obj->nextval(cat()?$dog:$fish)->{new}};
$ a {'cat'};
$a::b::c{d}->{$e->()};
$#_;
$#array;
$#{array};
$var[$#var];

# THESE SHOULD FAIL
$a->;
@{$;
$ a :: b :: c

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


# TEST EXTRACTION OF BALANCED TEXT
# USING: extract_bracketed($str);
{a nested { and } are okay as are () and <> pairs and escaped \}'s };

# USING: extract_bracketed($str,'{}');
{a nested { and } are okay as are unbalanced ( and < pairs and escaped \}'s };

# THESE SHOULD FAIL
{an unmatched nested { isn't okay, nor are ( and < };
{an unbalanced nested [ even with } and ] to match them;
