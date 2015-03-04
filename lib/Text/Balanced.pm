# EXTRACT VARIOUSLY DELIMITED TEXT SEQUENCES FROM STRINGS.
# FOR FULL DOCUMENTATION SEE Balanced.pod

use 5.005;
use strict;

package Text::Balanced;

use Exporter;
use SelfLoader;
use vars qw { $VERSION @ISA %EXPORT_TAGS };

$VERSION = '1.77';
@ISA		= qw ( Exporter );
		     
%EXPORT_TAGS	= ( ALL => [ qw(
				&extract_delimited
				&extract_bracketed
				&extract_quotelike
				&extract_codeblock
				&extract_variable
				&extract_tagged
				&extract_multiple

				&gen_delimited_pat
				&gen_extract_tagged

				&delimited_pat
			       ) ] );

Exporter::export_ok_tags('ALL');

# PROTOTYPES

sub _match_bracketed($$$$$$);
sub _match_variable($$);
sub _match_codeblock($$$$$$$);
sub _match_quotelike($$$$);

# HANDLE RETURN VALUES IN VARIOUS CONTEXTS

sub _fail
{
	my ($wantarray,$textref) = @_;
	return ("",$$textref,"") if $wantarray;
	return undef;
}

sub _succeed
{
	$@ = undef;
	my ($wantarray,$textref) = splice @_, 0, 2;
	if ($wantarray)
	{
		# print join ("|", @_), "\n";
		my @res;
		pos($$textref) = $_[2];			# RESET \G
		while (my ($from, $len) = splice @_, 0, 2)
		{
			push @res, substr($$textref,$from,$len);
		}
		return @res;
	}
	else
	{
		my $match = substr($$textref,$_[0],$_[1]);
		eval {substr($$textref,$_[4],$_[1]+$_[5])=""} ;	#CHOP OUT PREFIX & MATCH, IF POSSIBLE
		pos($$textref) = $_[4];				# RESET \G
		return $match;
	}
}

# BUILD A PATTERN MATCHING A SIMPLE DELIMITED STRING

sub gen_delimited_pat($;$)  # ($delimiters;$escapes)
{
	my ($dels, $escs) = @_;
	return "" unless $dels =~ /\S/;
	$escs = '\\' unless $escs;
	$escs .= substr($escs,-1) x (length($dels)-length($escs));
	my @pat = ();
	my $i;
	for ($i=0; $i<length $dels; $i++)
	{
		my $del = quotemeta substr($dels,$i,1);
		my $esc = quotemeta substr($escs,$i,1);
		if ($del eq $esc)
		{
			push @pat, "$del(?:[^$del]*(?:(?:$del$del)[^$del]*)*)$del";
		}
		else
		{
			push @pat, "$del(?:[^$esc$del]*(?:$esc.[^$esc$del]*)*)$del";
		}
	}
	my $pat = join '|', @pat;
	return "(?:$pat)";
}

*delimited_pat = \&gen_delimited_pat;


# THE EXTRACTION FUNCTIONS

sub extract_delimited (;$$$$)
{
	my $textref = defined $_[0] ? \$_[0] : \$_;
	my $wantarray = wantarray;
	my $del  = defined $_[1] ? $_[1] : qq{\'\"\`};
	my $pre  = defined $_[2] ? $_[2] : '\s*';
	my $esc  = defined $_[3] ? $_[3] : qq{\\};
	my $pat = gen_delimited_pat($del, $esc);
	my $startpos = pos $$textref || 0;
	return _fail($wantarray, $textref)
		unless $$textref =~ m/\G($pre)($pat)/gc;
	my $prelen = length($1);
	my $matchpos = $startpos+$prelen;
	my $endpos = pos $$textref;
	return _succeed $wantarray, $textref,
			$matchpos, $endpos-$matchpos,		# MATCH
			$endpos,   length($$textref)-$endpos,	# REMAINDER
			$startpos, $prelen;			# PREFIX
}

sub extract_bracketed (;$$$)
{
	my $textref = defined $_[0] ? \$_[0] : \$_;
	my $ldel = defined $_[1] ? $_[1] : '{([<';
	my $pre  = defined $_[2] ? $_[2] : '\s*';
	my $wantarray = wantarray;
	my $qdel = "";
	my $quotelike;
	$ldel =~ s/'//g and $qdel .= q{'};
	$ldel =~ s/"//g and $qdel .= q{"};
	$ldel =~ s/`//g and $qdel .= q{`};
	$ldel =~ s/q//g and $quotelike = 1;
	$ldel =~ tr/[](){}<>\0-\377/[[(({{<</ds;
	my $rdel = $ldel;
	unless ($rdel =~ tr/[({</])}>/)
        {
		$@ = "Did not find a suitable bracket in delimiter: \"$_[1]\"";
		return _fail $wantarray, $textref;
	}
	my $posbug = pos;
	$ldel = join('|', map { quotemeta $_ } split('', $ldel));
	$rdel = join('|', map { quotemeta $_ } split('', $rdel));
	pos = $posbug;

	my $startpos = pos $$textref || 0;
	my @match = _match_bracketed($textref,$pre, $ldel, $qdel, $quotelike, $rdel);

	return _fail ($wantarray, $textref) unless @match;

	return _succeed ( $wantarray, $textref,
			  $match[2], $match[5]+2,	# MATCH
			  @match[8,9],			# REMAINDER
			  @match[0,1],			# PREFIX
			);
}

sub _match_bracketed($$$$$$)	# $textref, $pre, $ldel, $qdel, $quotelike, $rdel
{
	my ($textref, $pre, $ldel, $qdel, $quotelike, $rdel) = @_;
	my ($startpos, $ldelpos, $endpos) = (pos $$textref = pos $$textref||0);
	unless ($$textref =~ m/\G$pre/gc)
	{
		$@ = "Did not find prefix: /$pre/";
		return;
	}

	$ldelpos = pos $$textref;

	unless ($$textref =~ m/\G($ldel)/gc)
	{
		$@ = "Did not find opening bracket after prefix: \"$pre\"";
		pos $$textref = $startpos;
		return;
	}

	my @nesting = ( $1 );
	my $textlen = length $$textref;
	while (pos $$textref < $textlen)
	{
		next if $$textref =~ m/\G\\./gcs;

		if ($$textref =~ m/\G($ldel)/gc)
		{
			push @nesting, $1;
		}
		elsif ($$textref =~ m/\G($rdel)/gc)
		{
			my ($found, $brackettype) = ($1, $1);
			if ($#nesting < 0)
			{
				$@ = "Unmatched closing bracket: \"$found\"";
				pos $$textref = $startpos;
			        return;
			}
			my $expected = pop(@nesting);
			$expected =~ tr/({[</)}]>/;
			if ($expected ne $brackettype)
			{
				$@ = qq{Mismatched closing bracket: expected "$expected" but found "$found"};
				pos $$textref = $startpos;
			        return;
			}
			last if $#nesting < 0;
		}
		elsif ($qdel && $$textref =~ m/\G([$qdel])/gc)
		{
			$$textref =~ m/\G[^\\$1]*(?:\\.[^\\$1]*)*(\Q$1\E)/gc and next;
			$@ = "Unmatched embedded quote ($1)";
			pos $$textref = $startpos;
			return;
		}
		elsif ($quotelike && _match_quotelike($textref,"",1,0))
		{
			next;
		}

		else { $$textref =~ m/\G(?:[a-zA-Z0-9]+|.)/gcs }
	}
	if ($#nesting>=0)
	{
		$@ = "Unmatched opening bracket(s): "
		     . join("..",@nesting)."..";
		pos $$textref = $startpos;
		return;
	}

	$endpos = pos $$textref;
	
	return (
		$startpos,  $ldelpos-$startpos,		# PREFIX
		$ldelpos,   1,				# OPENING BRACKET
		$ldelpos+1, $endpos-$ldelpos-2,		# CONTENTS
		$endpos-1,  1,				# CLOSING BRACKET
		$endpos,    length($$textref)-$endpos,	# REMAINDER
	       );
}

sub revbracket($)
{
	my $brack = reverse $_[0];
	$brack =~ tr/[({</])}>/;
	return $brack;
}

my $XMLNAME = q{[a-zA-Z_:][a-zA-Z_:.-]*};

sub extract_tagged (;$$$$$) # ($text, $opentag, $closetag, $pre, \%options)
{
	my $textref = defined $_[0] ? \$_[0] : \$_;
	my $ldel    = $_[1];
	my $rdel    = $_[2];
	my $pre     = defined $_[3] ? $_[3] : '\s*';
	my %options = defined $_[4] ? %{$_[4]} : ();
	my $omode   = defined $options{fail} ? $options{fail} : '';
	my $bad     = ref($options{reject}) eq 'ARRAY' ? join('|', @{$options{reject}})
		    : defined($options{reject})	       ? $options{reject}
		    :					 ''
		    ;
	my $ignore  = ref($options{ignore}) eq 'ARRAY' ? join('|', @{$options{ignore}})
		    : defined($options{ignore})	       ? $options{ignore}
		    :					 ''
		    ;

	if (!defined $ldel) { $ldel = '<\w+(?:' . gen_delimited_pat(q{'"}) . '|[^>])*>'; }
	$@ = undef;

	my @match = _match_tagged($textref, $pre, $ldel, $rdel, $omode, $bad, $ignore);

	return _fail(wantarray, $textref) unless @match;
	return _succeed wantarray, $textref,
			$match[2], $match[3]+$match[5]+$match[7],	# MATCH
			@match[8..9,0..1,2..7];				# REM, PRE, BITS
}

sub _match_tagged	# ($$$$$$$)
{
	my ($textref, $pre, $ldel, $rdel, $omode, $bad, $ignore) = @_;

	my ($startpos, $opentagpos, $textpos, $parapos, $closetagpos, $endpos) = ( pos($$textref) = pos($$textref)||0 );

	unless ($$textref =~ m/\G($pre)/gc)
	{
		$@ = "Did not find prefix: /$pre/";
		goto failed;
	}

	$opentagpos = pos($$textref);

	unless ($$textref =~ m/\G($ldel)/gc)
	{
		$@ = "Did not find opening tag: /$ldel/";
		goto failed;
	}

	$textpos = pos($$textref);

	if (!defined $rdel)
	{
		$rdel = $1;
		unless ($rdel =~ s/\A([[(<{]+)($XMLNAME).*/ "$1\/$2". revbracket($1) /oes)
		{
			$@ = "Unable to construct closing tag to match: $rdel";
			goto failed;
		}
	}

	while (pos($$textref) < length($$textref))
	{
		next if $$textref =~ m/\G\\./gc;

		if ($$textref =~ m/\G(\n[ \t]*\n)/gc )
		{
			$parapos = pos($$textref) - length($1)
				unless defined $parapos;
		}
		elsif ($$textref =~ m/\G($rdel)/gc )
		{
			$closetagpos = pos($$textref)-length($1);
			goto matched;
		}
		elsif ($ignore && $$textref =~ m/\G(?:$ignore)/gc)
		{
			next;
		}
		elsif ($bad && $$textref =~ m/\G($bad)/gcs)
		{
			pos($$textref) -= length($1);	# CUT OFF WHATEVER CAUSED THE SHORTNESS
			goto short if ($omode eq 'PARA' || $omode eq 'MAX');
			$@ = "Found invalid nested tag: $1";
			goto failed;
		}
		elsif ($$textref =~ m/\G($ldel)/gc)
		{
			my $tag = $1;
			pos($$textref) -= length($tag);	# REWIND TO NESTED TAG
			unless (_match_tagged(@_))	# MATCH NESTED TAG
			{
				goto short if $omode eq 'PARA' || $omode eq 'MAX';
				$@ = "Found unbalanced nested tag: $tag";
				goto failed;
			}
		}
		else { $$textref =~ m/./gcs }
	}

short:
	$closetagpos = pos($$textref);
	goto matched if $omode eq 'MAX';
	goto failed unless $omode eq 'PARA';

	if (defined $parapos) { pos($$textref) = $parapos }
	else		      { $parapos = pos($$textref) }

	return (
		$startpos,    $opentagpos-$startpos,		# PREFIX
		$opentagpos,  $textpos-$opentagpos,		# OPENING TAG
		$textpos,     $parapos-$textpos,		# TEXT
		$parapos,     0,				# NO CLOSING TAG
		$parapos,     length($$textref)-$parapos,	# REMAINDER
	       );
	
matched:
	$endpos = pos($$textref);
	return (
		$startpos,    $opentagpos-$startpos,		# PREFIX
		$opentagpos,  $textpos-$opentagpos,		# OPENING TAG
		$textpos,     $closetagpos-$textpos,		# TEXT
		$closetagpos, $endpos-$closetagpos,		# CLOSING TAG
		$endpos,      length($$textref)-$endpos,	# REMAINDER
	       );

failed:
	$@ = "Did not find closing tag" unless $@;
	pos($$textref) = $startpos;
	return;
}

sub extract_variable (;$$)
{
	my $textref = defined $_[0] ? \$_[0] : \$_;
	return ("","","") unless defined $$textref;
	my $pre  = defined $_[1] ? $_[1] : '\s*';

	my @match = _match_variable($textref,$pre);

	return _fail wantarray, $textref unless @match;

	return _succeed wantarray, $textref,
			@match[2..3,4..5,0..1];		# MATCH, REMAINDER, PREFIX
}

sub _match_variable($$)
{
	my ($textref, $pre) = @_;
	my $startpos = pos($$textref) = pos($$textref)||0;
	unless ($$textref =~ m/\G($pre)/gc)
	{
		$@ = "Did not find prefix: /$pre/";
		return;
	}
	my $varpos = pos($$textref);
	unless ($$textref =~ m/\G(\$#?|[\@\%])+/gc)
	{
		$@ = "Did not find leading dereferencer";
		pos $$textref = $startpos;
		return;
	}

	unless ($$textref =~ m/\G\s*(?:::)?(?:[_a-z]\w*::)*[_a-z]\w*/gci
		or _match_codeblock($textref, "", '\{', '\}', '\{', '\}', 0))
	{
		$@ = "Bad identifier after dereferencer";
		pos $$textref = $startpos;
		return;
	}

	1 while ( _match_codeblock($textref,'\s*(?:->(?:\s*\w+\s*)?)?\s*',
				   '[({[]','[)}\]]',
				   '[({[]','[)}\]]',
				   0
				   )
	        || _match_variable($textref,'\s*->\s*')
	        || $$textref =~ m/\G\s*->\s*\w+(?![{([])/gc
	        );
	
	my $endpos = pos($$textref);
	return ($startpos, $varpos-$startpos,
		$varpos,   $endpos-$varpos,
		$endpos,   length($$textref)-$endpos
		);
}

sub extract_codeblock (;$$$$$)
{
	my $textref = defined $_[0] ? \$_[0] : \$_;
	my $wantarray = wantarray;
	my $ldel_inner = defined $_[1] ? $_[1] : '{';
	my $pre        = defined $_[2] ? $_[2] : '\s*';
	my $ldel_outer = defined $_[3] ? $_[3] : $ldel_inner;
	my $rd         = $_[4];
	my $rdel_inner = $ldel_inner;
	my $rdel_outer = $ldel_outer;
	my $posbug = pos;
	for ($ldel_inner, $ldel_outer) { tr/[]()<>{}\0-\377/[[((<<{{/ds }
	for ($rdel_inner, $rdel_outer) { tr/[]()<>{}\0-\377/]]))>>}}/ds }
	for ($ldel_inner, $ldel_outer, $rdel_inner, $rdel_outer)
	{
		$_ = '('.join('|',map { quotemeta $_ } split('',$_)).')'
	}
	pos = $posbug;

	my @match = _match_codeblock($textref, $pre,
				     $ldel_outer, $rdel_outer,
				     $ldel_inner, $rdel_inner,
				     $rd);
	return _fail($wantarray, $textref) unless @match;
	return _succeed($wantarray, $textref,
			@match[2..3,4..5,0..1]	# MATCH, REMAINDER, PREFIX
		       );

}

sub _match_codeblock($$$$$$$)
{
	my ($textref, $pre, $ldel_outer, $rdel_outer, $ldel_inner, $rdel_inner, $rd) = @_;
	my $startpos = pos($$textref) = pos($$textref) || 0;
	unless ($$textref =~ m/\G($pre)/gc)
	{
		$@ = qq{Did not match prefix /$pre/ at"} .
		       substr($$textref,pos($$textref),20) .
		       q{..."};
		return; 
	}
	my $codepos = pos($$textref);
	unless ($$textref =~ m/\G($ldel_outer)/gc)	# OUTERMOST DELIMITER
	{
		$@ = qq{Did not find expected opening bracket at "} .
		     substr($$textref,pos($$textref),20) .
		     q{..."};
		pos $$textref = $startpos;
		return;
	}
	my $closing = $1;
	   $closing =~ tr/([<{/)]>}/;
	my $matched;
	my $patvalid = 1;
	while (pos($$textref) < length($$textref))
	{
		$matched = '';
		if ($rd && $$textref =~ m#\G(\Q(?)\E|\Q(s?)\E|\Q(s)\E)#gc)
		{
			$patvalid = 0;
			next;
		}

		if ($$textref =~ m/\G\s*#.*/gc)
		{
			next;
		}

		if ($$textref =~ m/\G\s*($rdel_outer)/gc)
		{
			unless ($matched = ($closing && $1 eq $closing) )
			{
				next if $1 eq '>';	# MIGHT BE A "LESS THAN"
				$@ = q{Mismatched closing bracket at "} .
				     substr($$textref,pos($$textref),20) .
				     qq{...". Expected '$closing'};
			}
			last;
		}

		if (_match_variable($textref,'\s*') ||
		    _match_quotelike($textref,'\s*',$patvalid,$patvalid) )
		{
			$patvalid = 0;
			next;
		}


		# NEED TO COVER MANY MORE CASES HERE!!!
		if ($$textref =~ m#\G\s*( [-+*x/%^&|.]=?
					| =(?!>)
					| (\*\*|&&|\|\||<<|>>)=?
					| [!=][~=]
					| split|grep|map|return
					)#gcx)
		{
			$patvalid = 1;
			next;
		}

		if ( _match_codeblock($textref, '\s*', $ldel_inner, $rdel_inner, $ldel_inner, $rdel_inner, $rd) )
		{
			$patvalid = 1;
			next;
		}

		if ($$textref =~ m/\G\s*$ldel_outer/gc)
		{
			$@ = q{Improperly nested codeblock at "} .
			     substr($$textref,pos($$textref),20) .
			     q{..."};
			last;
		}

		$patvalid = 0;
		$$textref =~ m/\G\s*(\w+|[-=>]>|.|\Z)/gc;
	}

	unless ($matched)
	{
		$@ = 'No match found for opening bracket' unless $@;
		return;
	}

	my $endpos = pos($$textref);
	return ( $startpos, $codepos-$startpos,
		 $codepos, $endpos-$codepos,
		 $endpos,  length($$textref)-$endpos,
	       );
}


my %mods   = (
		'none'	=> '[cgimsox]*',
		'm'	=> '[cgimsox]*',
		's'	=> '[cegimsox]*',
		'tr'	=> '[cds]*',
		'y'	=> '[cds]*',
		'qq'	=> '',
		'qx'	=> '',
		'qw'	=> '',
		'qr'	=> '[imsx]*',
		'q'	=> '',
	     );

sub extract_quotelike (;$$)
{
	my $textref = $_[0] ? \$_[0] : \$_;
	my $wantarray = wantarray;
	my $pre  = defined $_[1] ? $_[1] : '\s*';

	my @match = _match_quotelike($textref,$pre,1,0);
	return _fail($wantarray, $textref) unless @match;
	return _succeed($wantarray, $textref,
			$match[2], $match[18]-$match[2],	# MATCH
			@match[18,19],				# REMAINDER
			@match[0,1],				# PREFIX
			@match[2..17],				# THE BITS
		       );
};

sub _match_quotelike($$$$)	# ($textref, $prepat, $allow_raw_match)
{
	my ($textref, $pre, $rawmatch, $qmark) = @_;

	my ($textlen,$startpos,
	    $oppos,
	    $preld1pos,$ld1pos,$str1pos,$rd1pos,
	    $preld2pos,$ld2pos,$str2pos,$rd2pos,
	    $modpos) = ( length($$textref), pos($$textref) = pos($$textref) || 0 );

	unless ($$textref =~ m/\G($pre)/gc)
	{
		$@ = qq{Did not find prefix /$pre/ at "} .
		     substr($$textref, pos($$textref), 20) .
		     q{..."};
		return; 
	}
	$oppos = pos($$textref);

	my $initial = substr($$textref,$oppos,1);

	if ($initial && $initial =~ m|^[\"\'\`]|
		     || $rawmatch && $initial =~ m|^/|
		     || $qmark && $initial =~ m|^\?|)
	{
		unless ($$textref =~ m/ \Q$initial\E [^\\$initial]* (\\.[^\\$initial]*)* \Q$initial\E /gcx)
		{
			$@ = qq{Did not find closing delimiter to match '$initial' at "} .
			     substr($$textref, $oppos, 20) .
			     q{..."};
			pos $$textref = $startpos;
			return;
		}
		$modpos= pos($$textref);
		$rd1pos = $modpos-1;

		if ($initial eq '/' || $initial eq '?') 
		{
			$$textref =~ m/\G$mods{none}/gc
		}

		my $endpos = pos($$textref);
		return (
			$startpos,	$oppos-$startpos,	# PREFIX
			$oppos,		0,			# NO OPERATOR
			$oppos,		1,			# LEFT DEL
			$oppos+1,	$rd1pos-$oppos-1,	# STR/PAT
			$rd1pos,	1,			# RIGHT DEL
			$modpos,	0,			# NO 2ND LDEL
			$modpos,	0,			# NO 2ND STR
			$modpos,	0,			# NO 2ND RDEL
			$modpos,	$endpos-$modpos,	# MODIFIERS
			$endpos, 	$textlen-$endpos,	# REMAINDER
		       );
	}

	unless ($$textref =~ m!\G(m|s|qq|qx|qw|q|qr|tr|y)\b(?=\s*\S)!gc)
	{
		$@ = q{No quotelike operator found after prefix at "} .
		     substr($$textref, pos($$textref), 20) .
		     q{..."};
		pos $$textref = $startpos;
		return;
	}

	my $op = $1;
	$preld1pos = pos($$textref);
	$$textref =~ m/\G\s*/gc;
	$ld1pos = pos($$textref);
	$str1pos = $ld1pos+1;

	unless ($$textref =~ m/\G(\S)/gc)	# SHOULD USE LOOKAHEAD
	{
		$@ = "No block delimiter found after quotelike $op";
		pos $$textref = $startpos;
		return;
	}
	pos($$textref) = $ld1pos;	# HAVE TO DO THIS BECAUSE LOOKAHEAD BROKEN
	my ($ldel1, $rdel1) = ("\Q$1","\Q$1");
	if ($ldel1 =~ /[[(<{]/)
	{
		$rdel1 =~ tr/[({</])}>/;
		_match_bracketed($textref,"",$ldel1,"","",$rdel1)
		|| do { pos $$textref = $startpos; return };
	}
	else
	{
		$$textref =~ /$ldel1[^\\$ldel1]*(\\.[^\\$ldel1]*)*$ldel1/gc
		|| do { pos $$textref = $startpos; return };
	}
	$ld2pos = $rd1pos = pos($$textref)-1;

	if ($op =~ /s|tr|y/)
	{
		my ($ldel2, $rdel2);
		if ($ldel1 =~ /[[(<{]/)
		{
			unless ($$textref =~ /\G\s*(\S)/gc)	# SHOULD USE LOOKAHEAD
			{
				$@ = "Missing second block for quotelike $op";
				pos $$textref = $startpos;
				return;
			}
			$ldel2 = $rdel2 = "\Q$1";
			$rdel2 =~ tr/[({</])}>/;
		}
		else
		{
			$ldel2 = $rdel2 = $ldel1;
		}
		$str2pos = $ld2pos+1;

		if ($ldel2 =~ /[[(<{]/)
		{
			pos($$textref)--;	# OVERCOME BROKEN LOOKAHEAD 
			_match_bracketed($textref,"",$ldel2,"","",$rdel2)
			|| do { pos $$textref = $startpos; return };
		}
		else
		{
			$$textref =~ /[^\\$ldel2]*(\\.[^\\$ldel2]*)*$ldel2/gc
			|| do { pos $$textref = $startpos; return };
		}
		$rd2pos = pos($$textref)-1;
	}
	else
	{
		$ld2pos = $str2pos = $rd2pos = $rd1pos;
	}

	$modpos = pos $$textref;

	$$textref =~ m/\G($mods{$op})/gc;
	my $endpos = pos $$textref;

	return (
		$startpos,	$startpos-$oppos,	# PREFIX
		$oppos,		length($op),		# OPERATOR
		$ld1pos,	1,			# LEFT DEL
		$str1pos,	$rd1pos-$str1pos,	# STR/PAT
		$rd1pos,	1,			# RIGHT DEL
		$ld2pos,	1,			# 2ND LDEL
		$str2pos,	$rd2pos-$str2pos,	# 2ND STR
		$rd2pos,	1,			# 2ND RDEL
		$modpos,	$endpos-$modpos,	# MODIFIERS
		$endpos,	$textlen-$endpos,	# REMAINDER
	       );
}

my $def_func = 
[
	sub { extract_variable($_[0], '') },
	sub { extract_quotelike($_[0],'') },
	sub { extract_codeblock($_[0],'{}','') },
];

sub extract_multiple (;$$$$)	# ($text, $functions_ref, $max_fields, $ignoreunknown)
{
	my $textref = defined($_[0]) ? \$_[0] : \$_;
	my $posbug = pos;
	my ($lastpos, $firstpos);
	my @fields = ();

	for ($$textref)
	{
		my @func = defined $_[1] ? @{$_[1]} : @{$def_func};
		my $max  = defined $_[2] && $_[2]>0 ? $_[2] : 1_000_000_000;
		my $igunk = $_[3];

		pos ||= 0;

		unless (wantarray)
		{
			use Carp;
			carp "extract_multiple reset maximal count to 1 in scalar context"
				if $^W && defined($_[2]) && $max > 1;
			$max = 1
		}

		my $unkpos;
		my $func;
		my $field;

		FIELD: while (pos() < length())
		{
			foreach $func ( @func )
			{
				undef $field;
				$lastpos = pos;
				if (ref($func) eq 'CODE')
					{ ($field) = $func->($_) }
				elsif( m/\G$func/gc )
					{ $field = defined($1) ? $1 : $& }

				if (defined($field) && length($field))
				{
					if (defined($unkpos) && !$igunk)
					{
						push @fields, substr($_, $unkpos, $lastpos-$unkpos);
						$firstpos = $unkpos unless defined $firstpos;
						undef $unkpos;
						last FIELD if @fields == $max;
					}
					push @fields, $field;
					$firstpos = $lastpos unless defined $firstpos;
					$lastpos = pos;
					last FIELD if @fields == $max;
					next FIELD;
				}
			}
			if (/\G(.)/gcs)
			{
				$unkpos = pos()-1
					unless $igunk || defined $unkpos;
			}
		}
		
		if (defined $unkpos)
		{
			push @fields, substr($_, $unkpos);
			$firstpos = $unkpos unless defined $firstpos;
			$lastpos = length;
		}
		last;
	}

	pos $$textref = $lastpos;
	return @fields if wantarray;

	$firstpos ||= 0;
	eval { substr($$textref,$firstpos,$lastpos-$firstpos)="";
	       pos $$textref = $firstpos };
	return $fields[0];
}


sub gen_extract_tagged # ($opentag, $closetag, $pre, \%options)
{
	my $ldel    = $_[0];
	my $rdel    = $_[1];
	my $pre     = defined $_[2] ? $_[2] : '\s*';
	my %options = defined $_[3] ? %{$_[3]} : ();
	my $omode   = defined $options{fail} ? $options{fail} : '';
	my $bad     = ref($options{reject}) eq 'ARRAY' ? join('|', @{$options{reject}})
		    : defined($options{reject})	       ? $options{reject}
		    :					 ''
		    ;
	my $ignore  = ref($options{ignore}) eq 'ARRAY' ? join('|', @{$options{ignore}})
		    : defined($options{ignore})	       ? $options{ignore}
		    :					 ''
		    ;

	if (!defined $ldel) { $ldel = '<\w+(?:' . gen_delimited_pat(q{'"}) . '|[^>])*>'; }

	my $posbug = pos;
	for ($ldel, $pre, $bad, $ignore) { $_ = qr/$_/ if $_ }
	pos = $posbug;

	my $closure = sub
	{
		my $textref = defined $_[0] ? \$_[0] : \$_;
		my @match = Text::Balanced::_match_tagged($textref, $pre, $ldel, $rdel, $omode, $bad, $ignore);

		return _fail(wantarray, $textref) unless @match;
		return _succeed wantarray, $textref,
				$match[2], $match[3]+$match[5]+$match[7],	# MATCH
				@match[8..9,0..1,2..7];				# REM, PRE, BITS
	};

	bless $closure, 'Text::Balanced::Extractor';
}

package Text::Balanced::Extractor;

sub extract($$)	# ($self, $text)
{
	&{$_[0]}($_[1]);
}

1;
