use Test2::V0;
use Atomic::Pipe;

my ($r, $w) = Atomic::Pipe->pair;

$w->write_message("hello");
is($r->read_message, "hello", "intact message ok");

# A truncated header: fewer raw bytes than the 16-byte message header, then
# EOF. This must raise, not read as a clean EOF (silent data loss).
syswrite($w->wh, "\x01\x02\x03\x04\x05\x06\x07\x08") or die "syswrite: $!";
$w->close;

like(
    dies {
        # First call may consume the partial bytes before EOF is visible.
        $r->read_message for 1 .. 5;
    },
    qr/invalid state/i,
    "truncated header at EOF throws instead of looking like clean EOF",
);

# Clean EOF (no trailing garbage) still reads as undef.
my ($r2, $w2) = Atomic::Pipe->pair;
$w2->write_message("x");
$w2->close;
is($r2->read_message, "x",   "got message");
is($r2->read_message, undef, "clean EOF returns undef");

done_testing;
