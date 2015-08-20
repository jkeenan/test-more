use strict;
use warnings;

use Test::Stream;

use Test::Stream::Event;

can_ok('Test::Stream::Event', qw/debug nested/);

my $ok = eval { Test::Stream::Event->new(); 1 };
my $err = $@;
ok(!$ok, "Died");
like($err, qr/No debug info provided/, "Need debug info");

{
    package My::MockEvent;
    use Test::Stream::Event(
        accessors => [qw/foo bar baz/],
    );
}

can_ok('My::MockEvent', qw/foo bar baz/);
isa_ok('My::MockEvent', 'Test::Stream::Event');

my $one = My::MockEvent->new(debug => 'fake');

ok(!$one->causes_fail, "Events do not cause failures by default");

ok(!$one->$_, "$_ is false by default") for qw/update_state terminate global/;

is([$one->to_tap()], [], "to_tap is an empty list by default");

done_testing;
