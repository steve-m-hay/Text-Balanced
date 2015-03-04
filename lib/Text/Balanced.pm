# EXTRACT VARIOUSLY DELIMITED TEXT SEQUENCES FROM STRINGS.
# FOR FULL DOCUMENTATION SEE Balanced.pod

use strict;

package Text::Balanced;

use Exporter;
use vars qw { $VERSION @ISA %EXPORT_TAGS };

$VERSION = '1.36';
@ISA		= qw ( Exporter );
		     
%EXPORT_TAGS	= ( ALL => [ qw(
				&extract_delimited
				&extract_bracketed
				&extract_quotelike
				&extract_codeblock
				&extract_variable
			       ) ] );

Exporter::export_ok_tags('ALL');

# PAY NO ATTENTION TO THE TRACE BEHIND THE CURTAIN
# sub _trace($) { print $_[0], "\n" if defined $Balanced::TRACE; }
sub _trace($) {}

# HANDLE RETURN VALUES IN VARIOUS CONTEXTS

sub _fail
{
	my $wantarray = shift;
	return @_ if $wantarray;
	return undef;
}

sub _succeed
{
	$@ = undef;
	my $wantarray = shift;
	return @_[1..$#_]	if $wantarray;
	$_[0] = $_[2];		# MODIFY 1ST ARG IN NON-LIST CONTEXTS
	return $_[1]	 	if defined $wantarray;
	return undef;		# VOID CONTEXT
}

# THE EXTRACTION FUNCTIONS

sub extract_delimited (;$$$)
{
	my $text = defined $_[0] ? $_[0] : $_;
	my @fail = (wantarray,undef,$text);
	my $del  = defined $_[1] ? $_[1] : qq{\'\"\`};
	my $pre  = defined $_[2] ? $_[2] : '\s*';
	eval "'' =~ /$pre/; 1" or return _fail @fail;
	return _succeed (wantarray,(defined $_[0] ? $_[0] : $_),$2,$5,$1)
		if $text =~ /\A($pre)(([$del])(\\\3|(?!\3).)*\3)(.*)/s;
	$@ = "Could not extract \"$del\"-delimited substring";
	return _fail @fail;
}

sub extract_bracketed (;$$$)
{
	my $text = defined $_[0] ? $_[0] : defined $_ ? $_ : '';
	my $orig = $text;
	my $ldel = defined $_[1] ? $_[1] : '{([<';
	my $pre  = defined $_[2] ? $_[2] : '\s*';
	my @fail = (wantarray,undef,$text);

	unless ($text =~ s/\A($pre)//s)
		{ $@ = "Did not find prefix: /$pre/"; return _fail @fail; }

	$pre = $1;
	$ldel =~ tr/[](){}<>\0-\377/[[(({{<</ds;
	my $rdel = $ldel;

	unless ($rdel =~ tr/[({</])}>/)
	    { $@ = "Did not find a suitable bracket: \"$ldel\""; return _fail @fail; }

	$ldel = join('|', map { quotemeta $_ } split('', $ldel));
	$rdel = join('|', map { quotemeta $_ } split('', $rdel));

	unless ($text =~ m/\A($ldel)/)
	    { $@ = "Did not find opening bracket after prefix: \"$pre\"";
	      return _fail @fail; }

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
			          return _fail @fail; }
			my $expected = pop(@nesting);
			$expected =~ tr/({[</)}]>/;
			if ($expected ne $brackettype)
				{ $@ = "Mismatched closing bracket: expected \"$expected\" but found \"$found" . substr($text,0,10) . "\"";
			          return _fail @fail; }
			last if $#nesting < 0;
		}

		else { $text =~ s/.//s }
	}
	if ($#nesting>=0)
		{ $@ = "Unmatched opening bracket(s): "
		     . join("..",@nesting)."..";
		  return _fail @fail; }
	my $prelen = length $pre;
	return _succeed wantarray,
			(defined $_[0] ? $_[0] : $_),
			substr($orig,$prelen,length($orig)-length($text)-$prelen),
			$text,
		        $pre;
}

sub extract_variable (;$$)
{
	my $text = defined $_[0] ? $_[0] : defined $_ ? $_ : '';
	my $orig = $text;
	my $pre  = defined $_[1] ? $_[1] : '\s*';
	my @fail = (wantarray,undef,$text);
	unless ($text =~ s/\A($pre)//s)
		{ $@ = "Did not find prefix: /$pre/"; return _fail @fail; }
	$pre = $1;
	unless ($text =~ s/\A[\$\@\%]+//s)
		{ $@ = "Did not find leading dereferencer";
		  return _fail @fail; }

	unless ($text =~ s/\A((?:[a-z]\w*)?::)?[_a-z]\w*//i  or extract_codeblock($text,'{}',''))
		{ $@ = "Bad identifier after dereferencer";
		  return _fail @fail; }
	while ($text =~ s/\A((?:[a-z]\w*)?::)?[_a-z]\w*//i or extract_codeblock($text,'{}[]()','(?:->)?')) {}

	return _succeed wantarray,
			(defined $_[0] ? $_[0] : $_),
			substr($orig,0,length($orig)-length($text)),
			$text,
			$pre;
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
	my @fail = (wantarray,undef,$text);
	unless ($text =~ s/\A($pre)//s)
		{ $@ = "Did not find prefix: /$pre/"; return _fail @fail; }
	$pre = $1;
	unless ($text =~ s/\A$ldel//s)
		{ $@ = "Did not find opening bracket after prefix: \"$pre\"";
		  return _fail @fail; }
	my $closing = $1;
	   $closing =~ tr/([<{/)]>}/;
	my $matched;
	my $patvalid = 1;
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

		if ($text =~ s!\A\s*(=~|split|grep|map|return|;)!!)
		{
			$patvalid = 1;
			next;
		}

		if (extract_variable($text))
		{
			$patvalid = 0;
			next;
		}

		if ($text =~ m!\A\s*(m|s|qq|qx|qw|q|tr|y)\b\s*\S!
		 or $text =~ m!\A\s*[\"\'\`]!
		 or $patvalid and $text =~ m!\A\s*[/?]!)
		{
			_trace("Trying quotelike at [".substr($text,0,30)."]");
			($matched,$text) = extract_quotelike($text);
			if ($matched) { $patvalid = 0; next; }
			_trace("...quotelike failed");
		}

		if ($text =~ m/\A\s*$ldel/)
		{
			_trace("Trying codeblock at [".substr($text,0,30)."]");
			($matched,$text) = extract_codeblock($text,$del);
			if ($matched) { $patvalid = 1; next; }
			_trace("...codeblock failed");
			$@ = "Nested codeblock failed to balance from \""
				.  substr($text,0,10) . "...\"";
			last;
		}

		$patvalid = 0;
		$text =~ s/\s*(\w+|.)//s;
		_trace("Skipping: [$1]");
	}

	unless ($matched)
	{
		$@ = 'No match found for opening bracket' unless $@;
		return _fail @fail;
	}
	return _succeed wantarray,
			(defined $_[0] ? $_[0] : $_),
			substr($orig,0,length($orig)-length($text)),
			$text,
			$pre;
}

sub extract_quotelike (;$$)
{
	my $text = $_[0] ? $_[0] : defined $_ ? $_ : '';
	my $wantarray = wantarray;
	my @fail = (wantarray,undef,$text);
	my $pre  = $_[1] ? $_[1] : '\s*';

	my $ldel1  = '';
	my $block1 = '';
	my $rdel1  = '';
	my $ldel2  = '';
	my $block2 = '';
	my $rdel2  = '';
	my $mods   = '';

	my %mods   = (
			'none'	=> '[gimsox]*',
			'm'	=> '[gimsox]*',
			's'	=> '[egimsox]*',
			'tr'	=> '[cds]*',
			'y'	=> '[cds]*',
			'qq'	=> '',
			'qx'	=> '',
			'qw'	=> '',
			'q'	=> '',
		     );

	unless ($text =~ s/\A($pre)//s)
		{ $@ = "Did not find prefix: /$pre/"; return _fail @fail; }
	$pre = $1;
	my $orig = $text;

	if ($text =~ m!\A([/?\"\'\`])!)
	{
		$ldel1= $rdel1= $1;
		my $matched;
		($matched,$text) = extract_delimited($text, $ldel1);
	        return _fail @fail unless $matched;
		my $mods = '';
		if ($ldel1 =~ m![/]()!) 
			{ $text =~ s/\A($mods{none})// and $mods = $1; }
		return _succeed wantarray,
			(defined $_[0] ? $_[0] : $_),
		       ($matched.$mods,$text,$pre,
			'',					# OPERATOR
			$ldel1,					# BLOCK 1 LEFT DELIM
			substr($matched,1,length($matched)-2),	# BLOCK 1
			$rdel1,					# BLOCK 1 RIGHT DELIM
			'',					# BLOCK 2 LEFT DELIM
			'',					# BLOCK 2 
			'',					# BLOCK 2 RIGHT DELIM
			$mods					# MODIFIERS
			);
	}

	unless ($text =~ s!\A(m|s|qq|qx|qw|q|tr|y)\b(?=\s*\S)!!s)
	{
		$@ = "No quotelike function found after prefix: \"$pre\"";
		return _fail @fail
	}
	my $quotelike = $1;

	unless ($text =~ /\A\s*(\S)/)
	{
		$@ = "No block delimiter found after quotelike $quotelike";
		return _fail @fail;
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
	return _fail @fail if !$block1;
	$block1 =~ s/.(.*)./$1/s;

	if ($quotelike =~ /s|tr|y/)
	{
		if ($ldel1 =~ /[[(<{]/)
		{
			unless ($text =~ /\A\s*(\S)/)
			{
				$@ = "Missing second block for quotelike $quotelike";
				return _fail @fail;
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
		return _fail @fail if !$block2;
	}
	$block2 =~ s/.(.*)./$1/s;

	$text =~ s/\A($mods{$quotelike})//;

	return _succeed wantarray,
			(defined $_[0] ? $_[0] : $_),
	       		substr($orig,0,length($orig)-length($text)),
			$text,
			$pre,
			$quotelike,	# OPERATOR
			$ldel1,		
			$block1,
			$rdel1,
			$ldel2,		
			$block2,
			$rdel2,
			$1?$1:''	# MODIFIERS
			;
}

1;
