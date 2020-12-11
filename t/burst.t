use Test2::V0;
use Atomic::Pipe;
BEGIN { *PIPE_BUF = Atomic::Pipe->can('PIPE_BUF') }

my ($rh, $wh);
pipe($rh, $wh);
$rh->blocking(0);

my $w = Atomic::Pipe->from_fh('>&=', $wh);

ok($w->write_burst("aaa"), "write_burst returned true");

my $data = do { local $/ = undef; <$rh> };
is($data, 'aaa', "Got the short message");

ok(!$w->write_burst(("a" x PIPE_BUF) . 'x'), "Message is too long, not written");
$data = do { local $/ = undef; <$rh> };
ok(!defined $data, "No message received");

ok($w->write_burst("a" x PIPE_BUF), "write_burst max-length returned true");
$data = do { local $/ = undef; <$rh> };
is($data, ('a' x PIPE_BUF), "Got the short burst");

done_testing;
