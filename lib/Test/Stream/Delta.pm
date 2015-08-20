package Test::Stream::Delta;
use strict;
use warnings;

use Test::Stream::HashBase(
    accessors => [qw/verified id got chk children dne exception/]
);

use Test::Stream::Table();
use Test::Stream::Context();

use Scalar::Util qw/reftype blessed/;

use Carp qw/croak/;

# 'CHECK' constant would not work, but I like exposing 'check()' to people
# using this class.
BEGIN {
    no warnings 'once';
    *check = \&chk;
    *set_check = \&set_chk;
}

sub init {
    my $self = shift;

    croak "Cannot specify both 'check' and 'chk' as arguments"
        if exists($self->{check}) && exists($self->{+CHK});

    # Allow 'check' as an argument
    $self->{+CHK} ||= delete $self->{check}
        if exists $self->{check};
}

sub render_got {
    my $self = shift;

    my $exp = $self->{+EXCEPTION};
    if ($exp) {
        chomp($exp = "$exp");
        $exp =~ s/\n.*$//g;
        return "<EXCEPTION: $exp>";
    }

    my $dne = $self->{+DNE};
    return '<DOES NOT EXIST>' if $dne && $dne eq 'got';

    my $got = $self->{+GOT};
    return '<UNDEF>' unless defined $got;

    return "$got";
}

sub render_check {
    my $self = shift;

    my $dne = $self->{+DNE};
    return '<DOES NOT EXIST>' if $dne && $dne eq 'check';

    my $check = $self->{+CHK};
    return '<UNDEF>' unless defined $check;

    return $check->render;
}

sub _full_id {
    my ($type, $id) = @_;
    return "<$id>" if !$type || $type eq 'META';
    return $id     if $type eq 'SCALAR';
    return "{$id}" if $type eq 'HASH';
    return "[$id]" if $type eq 'ARRAY';
    return "$id()" if $type eq 'METHOD';
    return "<$id>";
}

sub _arrow_id {
    my ($path, $type) = @_;
    return '' unless $path;

    return ' ' if !$type || $type eq 'META';    # Meta gets a space, not an arrow

    return '->' if $type eq 'METHOD';           # Method always needs an arrow
    return '->' if $type eq 'SCALAR';           # Scalar always needs an arrow
    return '->' if $path =~ m/(>|\(\))$/;       # Need an arrow after meta, or after a method
    return '->' if $path eq '$VAR';             # Need an arrow after the initial ref

    # Hash and array need an arrow unless they follow another hash/array
    return '->' if $type =~ m/^(HASH|ARRAY)$/ && $path !~ m/(\]|\})$/;

    # No arrow needed
    return '';
}

sub _join_id {
    my ($path, $parts) = @_;
    my ($type, $key) = @$parts;

    my $id   = _full_id($type, $key);
    my $join = _arrow_id($path, $type);

    return "${path}${join}${id}";
}

sub should_show {
    my $self = shift;
    return 1 unless $self->verified;
    my $check = $self->check || return 0;
    return 0 unless $check->lines;
    my $file = $check->file || return 0;

    my $ctx = Test::Stream::Context::context();
    my $cfile = $ctx->debug->file;
    $ctx->release;
    return 0 unless $file eq $cfile;

    return 1;
}

sub filter_visible {
    my $self = shift;

    my @deltas;
    my @queue = (['', $self]);

    while (my $set = shift @queue) {
        my ($path, $delta) = @$set;

        push @deltas => [$path, $delta] if $delta->should_show;

        my $children = $delta->children || next;
        next unless @$children;

        my @new;
        for my $child (@$children) {
            my $cpath = _join_id($path, $child->id);
            push @new => [$cpath, $child];
        }
        unshift @queue => @new;
    }

    return \@deltas;
}

sub table_header {[ qw/PATH LNs GOT OP CHECK LNs/ ]}

sub table_op {
    my $self = shift;

    my $check = $self->{+CHK} || return '!exists';

    return $check->operator($self->{+GOT})
        unless $self->{+DNE} && $self->{+DNE} eq 'got';

    return $check->operator();
}

sub table_check_lines {
    my $self = shift;

    my $check = $self->{+CHK} || return '';
    my $lines = $check->lines || return '';

    return '' unless @$lines;

    return join ', ' => @$lines;
}

sub table_got_lines {
    my $self = shift;

    my $check = $self->{+CHK} || return '';
    return '' if $self->{+DNE} && $self->{+DNE} eq 'got';

    my @lines = $check->got_lines($self->{+GOT});
    return '' unless @lines;

    return join ', ' => @lines;
}

sub table_rows {
    my $self = shift;

    my $deltas = $self->filter_visible;

    my @rows;
    for my $set (@$deltas) {
        my ($id, $d) = @$set;

        my $rc   = $d->render_check;
        my $rg   = $d->render_got;
        my $op   = $d->table_op;
        my $dlns = $d->table_check_lines;
        my $glns = $d->table_got_lines;

        push @rows => [$id, $glns, $rg, $op, $rc, $dlns];
    }

    return \@rows;
}

sub table {
    my $self = shift;

    my @out;

    my $header = $self->table_header;
    my $rows   = $self->table_rows;

    my $max = exists $ENV{TS_MAX_DELTA} ? $ENV{TS_MAX_DELTA} : 25;
    if ($max && @$rows > $max) {
        @$rows = @{$rows}[0 .. ($max - 1)];
        push @out => (
            "************************************************************",
            sprintf("* Stopped after %-42.42s *", "$max differences."),
            "* Set the TS_MAX_DELTA environment var to raise the limit. *",
            "* Set it to 0 for no limit.                                *",
            "************************************************************",
        );
    }

    unshift @out => Test::Stream::Table::table(
        header    => $header,
        rows      => $rows,
        collapse  => 1,
        sanitize  => 1,
        mark_tail => 1,
        no_collapse => [2, 4],
    );

    return @out;
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Test::Stream::Delta - Representation of differences between nested data
structures.

=head1 EXPERIMENTAL CODE WARNING

B<This is an experimental release!> Test-Stream, and all its components are
still in an experimental phase. This dist has been released to cpan in order to
allow testers and early adopters the chance to write experimental new tools
with it, or to add experimental support for it into old tools.

B<PLEASE DO NOT COMPLETELY CONVERT OLD TOOLS YET>. This experimental release is
very likely to see a lot of code churn. API's may break at any time.
Test-Stream should NOT be depended on by any toolchain level tools until the
experimental phase is over.

=head1 DESCRIPTION

This is used by L<Test::Stream::Compare>. When data structures are compared a
delta will be returned. Deltas are a tree datastructure that represent all the
differences between 2 other data structures.

=head1 METHODS

=head2 ATTRIBUTES

=over 4

=item $bool = $delta->verified

=item $delta->set_verified($bool)

This will be true if the delta itself matched, if the delta matched then the
problem is in the deltas children, not the delta itself.

=item $aref = $delta->id

=item $delta->set_id([$type, $name])

Id for the delta, this is used to produce the path into the data structure. An
example is C<< ['HASH' => 'foo'] >> which means the delta is in the path
C<< ...->{'foo'} >>. Valid types are C<HASH>, C<ARRAY>, C<SCALAR>, C<META>, and
C<METHOD>.

=item $val = $delta->got

=item $delta->set_got($val)

Deltas are produced by comparing a recieved data structure 'got' against a
check data structure 'check'. The 'got' attribute contains the value that was
recieved for comparison.

=item $check = $delta->chk

=item $check = $delta->check

=item $delta->set_chk($check)

=item $delta->set_check($check)

Deltas are produced by comparing a recieved data structure 'got' against a
check data structure 'check'. The 'check' attribute contains the value that was
expected in the comparison.

C<check> and C<chk> are aliases for the same attribute.

=item $aref = $delta->children

=item $delta->set_children([$delta1, $delta2, ...])

A Delta may have child deltas, if it does then this is an arrayref with those
children.

=item $dne = $delta->dne

=item $delta->set_dne($dne)

Sometimes a comparison results in one side or the other not existing at all, in
which case this is set to the name of the attribute that does not exist. This
can be set to 'got' or 'check'.

=item $e = $delta->exception

=item $delta->set_exception($e)

This will be set to the exception in cases where the comparison failed due to
an exception being thrown.

=back

=head2 OTHER

=over 4

=item $string = $delta->render_got

Renders the string that should be used in a table to represent the recieved
value in a comparison.

=item $string = $delta->render_check

Renders the string that should be used in a table to represent the expected
value in a comparison.

=item $bool = $delta->should_show

This will return true if the delta should be shown in the table. This is
normally true for any unverified delta. This will also be true for deltas that
contain extra useful debug information.

=item $aref = $delta->filter_visible

This will produce an arrayref of C<< [ $path => $delta ] >> for all deltas that
should be displayed in the table.

=item $aref = $delta->table_header

This returns an array ref of the headers for the table.

=item $string = $delta->table_op

This returns the operator that should be shown in the table.

=item $string = $delta->table_check_lines

This returns the defined lines (extra debug info) that should be displayed.

=item $string = $delta->table_got_lines

This returns the generated lines (extra debug info) that should be displayed.

=item $aref = $delta->table_rows

This returns an arrayref of table rows, each row is itself an arrayref.

=item @table_lines = $delta->table

Returns all the lines of the table that should be displayed.

=back

=head1 SOURCE

The source code repository for Test::Stream can be found at
F<http://github.com/Test-More/Test-Stream/>.

=head1 MAINTAINERS

=over 4

=item Chad Granum E<lt>exodist@cpan.orgE<gt>

=back

=head1 AUTHORS

=over 4

=item Chad Granum E<lt>exodist@cpan.orgE<gt>

=back

=head1 COPYRIGHT

Copyright 2015 Chad Granum E<lt>exodist7@gmail.comE<gt>.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

See F<http://www.perl.com/perl/misc/Artistic.html>

=cut
