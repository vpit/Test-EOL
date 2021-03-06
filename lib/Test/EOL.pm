package Test::EOL;
# ABSTRACT: Check the correct line endings in your project

use strict;
use warnings;

our $VERSION = '2.01';

use Test::Builder;
use File::Spec;
use File::Find;
use Cwd qw/ cwd /;

our $PERL    = $^X || 'perl';
our $UNTAINT_PATTERN  = qr|^([-+@\w./:\\]+)$|;
our $PERL_PATTERN     = qr/^#!.*perl/;

my %file_find_arg = ($] <= 5.006) ? () : (
    untaint => 1,
    untaint_pattern => $UNTAINT_PATTERN,
    untaint_skip => 1,
);

my $Test  = Test::Builder->new;

my $no_plan;

sub import {
    my $self   = shift;
    my $caller = caller;
    {
        no strict 'refs';
        *{$caller.'::eol_unix_ok'} = \&eol_unix_ok;
        *{$caller.'::all_perl_files_ok'} = \&all_perl_files_ok;
    }
    $Test->exported_to($caller);

    if ($_[0] && $_[0] eq 'no_plan') {
        shift;
        $no_plan = 1;
    }
    $Test->plan(@_);
}

sub _all_perl_files {
    my @all_files = _all_files(@_);
    return grep { _is_perl_module($_) || _is_perl_script($_) || _is_pod_file($_) } @all_files;
}

sub _all_files {
    my @base_dirs = @_ ? @_ : cwd();
    my $options = pop(@base_dirs) if ref $base_dirs[-1] eq 'HASH';
    my @found;
    my $want_sub = sub {
        return if ($File::Find::dir =~ m![\\/]?CVS[\\/]|[\\/]?\.svn[\\/]!); # Filter out cvs or subversion dirs/
        return if ($File::Find::dir =~ m![\\/]?blib[\\/]libdoc$!); # Filter out pod doc in dist
        return if ($File::Find::dir =~ m![\\/]?blib[\\/]man\d$!); # Filter out pod doc in dist
        return if ($File::Find::dir =~ m![\\/]?inc!); # Filter out Module::Install stuff
        return if ($File::Find::name =~ m!Build$!i); # Filter out autogenerated Build script
        return unless (-f $File::Find::name && -r _);
        push @found, File::Spec->no_upwards( $File::Find::name );
    };
    my $find_arg = {
        %file_find_arg,
        wanted   => $want_sub,
        no_chdir => 1,
    };
    find( $find_arg, @base_dirs);
    return @found;
}

# Formats various human invisible symbols
# to similar visible ones.
# Perhaps ^M or something like that
# would be more appropriate?

sub _show_whitespace {
    my $string = shift;
    $string =~ s/\r/[\\r]/g;
    $string =~ s/\t/[\\t]/g;
    $string =~ s/ /[\\s]/g;
    return $string;
}

# Format a line record for diagnostics.

sub _debug_line {
    my ( $options, $line ) = @_;
    $line->[2] =~ s/\n\z//g;
    return "line $line->[1]: $line->[0]" . (
      $options->{show_lines} ? qq{: } . _show_whitespace( $line->[2] )  : q{}
    );
}

sub eol_unix_ok {
    my $file = shift;
    my $test_txt;
    $test_txt   = shift if !ref $_[0];
    $test_txt ||= "No incorrect line endings in '$file'";
    my $options = shift if ref $_[0] eq 'HASH';
    $options ||= {
        trailing_whitespace => 0,
        all_reasons => 0,
    };
    $file = _module_to_path($file);

    open my $fh, $file or do { $Test->ok(0, $test_txt); $Test->diag("Could not open $file: $!"); return; };
    # Windows-- , default is :crlf, which hides \r\n  -_-
    binmode( $fh, ':raw' );
    my $line = 0;
    my @fails;
    while (<$fh>) {
        $line++;
        if ( !$options->{trailing_whitespace} && /(\r+)$/ ) {
          my $match = $1;
          push @fails, [ _show_whitespace( $match ) , $line , $_ ];
        }
        if (  $options->{trailing_whitespace} && /([ \t]*\r+|[ \t]+)$/ ) {
          my $match = $1;
          push @fails, [ _show_whitespace($match), $line , $_ ];
        }
        # Minor short-circuit for people who don't need the whole file scanned
        # once there's an err.
        last if( @fails > 0 && !$options->{all_reasons} );
    }
    if( @fails ){
       $Test->ok( 0, $test_txt . " on "  . _debug_line({ show_lines => 0 } , $fails[0]  )  );
       if ( $options->{all_reasons} || 1 ){
          $Test->diag( "  Problem Lines: ");
          for ( @fails ){
            $Test->diag(_debug_line({ show_lines => 1 } , $_ ) );
          }
       }
       return 0;
    }
    $Test->ok(1, $test_txt);
    return 1;
}
sub all_perl_files_ok {
    my $options = shift if ref $_[0] eq 'HASH';
    my @files = _all_perl_files( @_ );
    _make_plan();
    foreach my $file ( @files ) {
      eol_unix_ok($file, $options);
    }
}

sub _is_perl_module {
    $_[0] =~ /\.pm$/i || $_[0] =~ /::/;
}

sub _is_pod_file {
    $_[0] =~ /\.pod$/i;
}

sub _is_perl_script {
    my $file = shift;
    return 1 if $file =~ /\.pl$/i;
    return 1 if $file =~ /\.t$/;
    open (my $fh, $file) or return;
    my $first = <$fh>;
    return 1 if defined $first && ($first =~ $PERL_PATTERN);
    return;
}

sub _module_to_path {
    my $file = shift;
    return $file unless ($file =~ /::/);
    my @parts = split /::/, $file;
    my $module = File::Spec->catfile(@parts) . '.pm';
    foreach my $dir (@INC) {
        my $candidate = File::Spec->catfile($dir, $module);
        next unless (-e $candidate && -f _ && -r _);
        return $candidate;
    }
    return $file;
}

sub _make_plan {
    return if $no_plan;
    unless ($Test->has_plan) {
        $Test->plan( 'no_plan' );
    }
    $Test->expected_tests;
}

sub _untaint {
    my @untainted = map { ($_ =~ $UNTAINT_PATTERN) } @_;
    return wantarray ? @untainted : $untainted[0];
}

1;
__END__

=pod

=head1 SYNOPSIS

C<Test::EOL> lets you check for the presence of trailing whitespace and/or
windows line endings in your perl code. It reports its results in standard
C<Test::Simple> fashion:

  use Test::EOL tests => 1;
  eol_unix_ok( 'lib/Module.pm', 'Module is ^M free');

and to add checks for trailing whitespace:

  use Test::EOL tests => 1;
  eol_unix_ok( 'lib/Module.pm', 'Module is ^M and trailing whitespace free', { trailing_whitespace => 1 });

Module authors can include the following in a t/eol.t and have C<Test::EOL>
automatically find and check all perl files in a module distribution:

  use Test::EOL;
  all_perl_files_ok();

or

  use Test::EOL;
  all_perl_files_ok( @mydirs );

and if authors would like to check for trailing whitespace:

  use Test::EOL;
  all_perl_files_ok({ trailing_whitespace => 1 });

or

  use Test::EOL;
  all_perl_files_ok({ trailing_whitespace => 1 }, @mydirs );

or

  use Test::More;
  use Test::EOL 'no_test';
  all_perl_files_ok();
  done_testing;

=head1 DESCRIPTION

This module scans your project/distribution for any perl files (scripts,
modules, etc) for the presence of windows line endings.

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=func all_perl_files_ok

  all_perl_files_ok( [ \%options ], [ @directories ] )

Applies C<eol_unix_ok()> to all perl files found in C<@directories> (and sub
directories). If no <@directories> is given, the starting point is the current
working directory, as tests are usually run from the top directory in a typical
CPAN distribution. A perl file is *.pl or *.pm or *.pod or *.t or a file starting
with C<#!...perl>

Valid C<\%options> currently are:

=over

=item * trailing_whitespace

By default Test::EOL only looks for Windows (CR/LF) line-endings. Set this
to true to raise errors if any kind of trailing whitespace is present in
the file.

=item * all_reasons

Normally Test::EOL reports only the first error in every file (given that
a text file originated on Windows will fail every single line). Set this
a true value to register a test failure for every line with an error.

=back

If the test plan is defined:

  use Test::EOL tests => 3;
  all_perl_files_ok();

the total number of files tested must be specified.

=func eol_unix_ok

  eol_unix_ok ( $file [, $text] [, \%options ] )

Run a unix EOL check on C<$file>. For a module, the path (lib/My/Module.pm) or the
name (My::Module) can be both used. C<$text> is the diagnostic label emitted after
the C<ok>/C<not ok> TAP output. C<\%options> takes the same values as described in
L</all_perl_files_ok>.

=head1 ACKNOWLEDGEMENTS

Shamelessly ripped off from L<Test::NoTabs>.

=head1 SEE ALSO

=for :list
* L<Test::More>
* L<Test::Pod>
* L<Test::Distribution>
* L<Test:NoWarnings>
* L<Test::NoTabs>
* L<Module::Install::AuthorTests>

=cut
