# EXTRACT VARIOUSLY DELIMITED TEXT SEQUENCES FROM STRINGS.
# FOR FULL DOCUMENTATION SEE Balanced.pod

use strict;

package Text::Balanced;

use Exporter;
use vars qw { $VERSION @ISA @EXPORT_OK };

$VERSION	= 1.20;
@ISA		= qw ( Exporter );
@EXPORT_OK	= qw (
			&extract_delimited
			&extract_bracketed
			&extract_quotelike
			&extract_codeblock
		     );

# PAY NO ATTENTION TO THE TRACE BEHIND THE CURTAIN
# sub _trace($) { print $_[0], "\n" if defined $Balanced::TRACE; }
sub _trace($) {}

sub extract_delimited (;$$$)
{
	my $text = defined $_[0] ? $_[0] : $_;
	my @fail = ('',$text,'');
	my $del  = defined $_[1] ? $_[1] : q{'"`};
	my $pre  = defined $_[2] ? $_[2] : '\s*';
	eval "'' =~ /$pre/; 1" or return @fail;
	return ($2,$5,$1)
		if $text =~ /\A($pre)(([$del])(\\\3|(?!\3).)*\3)(.*)/s;
	$@ = "Could not extract \"$del\"-delimited substring";
	return @fail;
}

sub extract_bracketed (;$$$)
{
	$@ = '';
	my $text = defined $_[0] ? $_[0] : defined $_ ? $_ : '';
	my $orig = $text;
	my $ldel = defined $_[1] ? $_[1] : '{([<';
	my $pre  = defined $_[2] ? $_[2] : '\s*';
	my @fail = ('',$text,'');

	unless ($text =~ s/\A($pre)//s)
		{ $@ = "Did not find prefix: /$pre/"; return @fail; }

	$pre = $1;
	$ldel =~ tr/[](){}<>\0-\377/[[(({{<</ds;
	my $rdel = $ldel;

	unless ($rdel =~ tr/[({</])}>/)
	    { $@ = "Did not find a suitable bracket: \"$ldel\""; return @fail; }

	$ldel = join('|', map { quotemeta $_ } split('', $ldel));
	$rdel = join('|', map { quotemeta $_ } split('', $rdel));

	unless ($text =~ m/\A($ldel)/)
	    { $@ = "Did not find opening bracket after prefix: \"$pre\"";
	      return @fail; }

	my @nesting = ();
	while (length $text)
	{
		next if $text =~ s/\A\\.//s;

		if ($text =~ s/\A($ldel)//)
		{
			push @nesting, $1;
		}
		elsif ($text =~ s/\A($rdel)//)
		{
			my ($found, $brackettype) = ($1, $1);
			if ($#nesting < 0)
				{ $@ = "Unmatched closing bracket: \"$found\"";
			          return @fail; }
			my $expected = pop(@nesting);
			$expected =~ tr/({[</)}]>/;
			if ($expected ne $brackettype)
				{ $@ = "Mismatched closing bracket: expected \"$expected\" but found \"$found" . substr($text,0,10) . "\"";
			          return @fail; }
			last if $#nesting < 0;
		}

		else { $text =~ s/.//s }
	}
	if ($#nesting>=0)
		{ $@ = "Unmatched opening bracket(s): "
		     . join("..",@nesting)."..";
		  return @fail; }
	my $prelen = length $pre;
	return ( substr($orig,$prelen,length($orig)-length($text)-$prelen)
	       , $text
	       , $pre);
}

sub extract_codeblock (;$$$)
{
	my $text = defined $_[0] ? $_[0] : defined $_ ? $_ : '';
	my $orig = $text;
	my $del  = defined $_[1] ? $_[1] : '{';
	my $pre  = defined $_[2] ? $_[2] : '\s*';
	my ($ldel, $rdel) = ($del, $del);
	$ldel =~ tr/[]()<>{}\0-\377/[[((<<{{/ds;
	$rdel =~ tr/[]()<>{}\0-\377/]]))>>}}/ds;
	$ldel = '('.join('|',map { quotemeta $_ } split('',$ldel)).')';
	$rdel = '('.join('|',map { quotemeta $_ } split('',$rdel)).')';
	_trace("Trying /$ldel/../$rdel/");
	my @fail = ('',$text,'');
	$@ = '';
	unless ($text =~ s/\A($pre)//s)
		{ $@ = "Did not find prefix: /$pre/"; return @fail; }
	$pre = $1;
	unless ($text =~ s/\A$ldel//s)
		{ $@ = "Did not find opening bracket after prefix: \"$pre\"";
		  return @fail; }
	my $closing = $1;
	   $closing =~ tr/([<{/)]>}/;
	my $matched;
	while (length $text)
	{
		$matched = '';
		if ($text =~ s/\A\s*$rdel//)
		{
			$matched = ($1 eq $closing);
			unless ($matched)
			{
				$@ = "Mismatched closing bracket: expected \""
				   . "$closing\" but found \"$1"
				   . substr($text,0,10) . "\"";
			}
			last;
		}

		if ($text =~ m#\A\s*(m|s|qq|qx|qw|q|tr|y)\b\s*\S#
		 or $text =~ m#\A\s*["'`/]#)
		{
			_trace("Trying quotelike at [".substr($text,0,30)."]");
			($matched,$text) = extract_quotelike($text);
			next if $matched;
			_trace("...quotelike failed");
		}

		if ($text =~ m/\A\s*$ldel/)
		{
			_trace("Trying codeblock at [".substr($text,0,30)."]");
			($matched,$text) = extract_codeblock($text,$del);
			next if $matched;
			_trace("...codeblock failed");
			$@ = "Nested codeblock failed to balance from \""
				.  substr($text,0,10) . "...\"";
			last;
		}

		$text =~ s/\s*(\w+|.)//s;
		_trace("Skipping: [$1]");
	}

	unless ($matched)
	{
		$@ = 'No match found for opening bracket' unless $@;
		return @fail;
	}
	return (substr($orig,0,length($orig)-length($text)),$text,$pre);
}

sub extract_quotelike (;$$)
{
	my $text = $_[0] ? $_[0] : defined $_ ? $_ : '';
	my @fail = ('',$text,'','','','','','','','','');
	my $pre  = $_[1] ? $_[1] : '\s*';

	my $ldel1  = '';
	my $block1 = '';
	my $rdel1  = '';
	my $ldel2  = '';
	my $block2 = '';
	my $rdel2  = '';
	my $mods   = '';

	my %mods   = (
			'none'	=> '[gimsox]',
			'm'	=> '[gimsox]',
			's'	=> '[egimsox]',
			'tr'	=> '[cds]',
			'y'	=> '[cds]',
			'qq'	=> '',
			'q'	=> '',
		     );

	unless ($text =~ s/\A($pre)//s)
		{ $@ = "Did not find prefix: /$pre/"; return @fail; }
	$pre = $1;
	my $orig = $text;

	if ($text =~ m#\A([/"'`])#)
	{
		$ldel1= $rdel1= $1;
		my $matched;
		($matched,$text) = extract_delimited($text, $ldel1);
	        return @fail unless $matched;
		$text =~ s/\A(($mods{none})*)// if ($ldel1 =~ m#[/]()#);
		return ($matched.$1,$text,$pre,
			'',					# OPERATOR
			$ldel1,					# BLOCK 1 LEFT DELIM
			substr($matched,1,length($matched)-2),	# BLOCK 1
			$rdel1,					# BLOCK 1 RIGHT DELIM
			'',					# BLOCK 2 LEFT DELIM
			'',					# BLOCK 2 
			'',					# BLOCK 2 RIGHT DELIM
			$1?$1:''				# MODIFIERS
			);
	}

	unless ($text =~ s#\A(m|s|qq|qx|qw|q|tr|y)\b(?=\s*\S)##s)
	{
		$@ = "No quotelike function found after prefix: \"$pre\"";
		return @fail
	}
	my $quotelike = $1;

	unless ($text =~ /\A\s*(\S)/)
	{
		$@ = "No block delimiter found after quotelike $quotelike";
		return @fail;
	}
	$ldel1= $rdel1= $1;
	if ($ldel1 =~ /[[(<{]/)
	{
		$rdel1 =~ tr/[({</])}>/;
		($block1,$text) = extract_bracketed($text,$ldel1);
	}
	else
	{
		($block1,$text) = extract_delimited($text,$ldel1);
	}
	return @fail if !$block1;
	$block1 =~ s/.(.*)./$1/s;

	if ($quotelike =~ /s|tr|y/)
	{
		if ($ldel1 =~ /[[(<{]/)
		{
			unless ($text =~ /\A\s*(\S)/)
			{
				$@ = "Missing second block for quotelike $quotelike";
				return @fail;
			}
			$ldel2= $rdel2= $1;
			$rdel2 =~ tr/[({</])}>/;
		}
		else
		{
			$ldel2= $rdel2= $ldel1;
			$text = $ldel2.$text;
		}

		if ($ldel2 =~ /[[(<{]/)
		{
			($block2,$text) = extract_bracketed($text,$ldel2);
		}
		else
		{
			($block2,$text) = extract_delimited($text,$ldel2);
		}
		return @fail if !$block2;
	}
	$block2 =~ s/.(.*)./$1/s;

	$text =~ s/\A($mods{$quotelike}*)//;

	return (substr($orig,0,length($orig)-length($text)),$text,$pre,
		$quotelike,	# OPERATOR
		$ldel1,		
		$block1,
		$rdel1,
		$ldel2,		
		$block2,
		$rdel2,
		$1?$1:''	# MODIFIERS
		);
}

1;
