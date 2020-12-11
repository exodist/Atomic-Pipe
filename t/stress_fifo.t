use Test2::V0;
use Test2::Require::RealFork;
use Test2::IPC;
use Atomic::Pipe;

BEGIN { *PIPE_BUF = Atomic::Pipe->can('PIPE_BUF') }

use POSIX qw/mkfifo/;
use File::Temp qw/tempdir/;
use File::Spec;

my $tempdir = tempdir(CLEANUP => 1);
my $fifo = File::Spec->catfile($tempdir, 'fifo');
mkfifo($fifo, 0700) or die "Failed to make fifo: $!";

my $r = Atomic::Pipe->read_fifo($fifo);

$SIG{CHLD} = 'IGNORE';
sub worker(&) {
    my ($code) = @_;
    my $pid = fork // die "Could not fork: $!";
    return $pid if $pid;

    my $ok = eval { $code->(); 1 };
    my $err = $@;
    exit(0) if $ok;
    warn $err;
    exit 255;
}

my $COUNT = 10_000;

worker { my $w = Atomic::Pipe->write_fifo($fifo); $w->write_message("aaa" x PIPE_BUF) for 1 .. $COUNT };
worker { my $w = Atomic::Pipe->write_fifo($fifo); $w->write_message("bbb" x PIPE_BUF) for 1 .. $COUNT };
worker { my $w = Atomic::Pipe->write_fifo($fifo); $w->write_message("ccc" x PIPE_BUF) for 1 .. $COUNT };
worker { my $w = Atomic::Pipe->write_fifo($fifo); $w->write_message("ddd" x PIPE_BUF) for 1 .. $COUNT };
worker { my $w = Atomic::Pipe->write_fifo($fifo); $w->write_message("eee" x PIPE_BUF) for 1 .. $COUNT };

my %seen;
while (my $msg = $r->read_message) {
    is(
        $msg,
        in_set(
            ("aaa" x PIPE_BUF),
            ("bbb" x PIPE_BUF),
            ("ccc" x PIPE_BUF),
            ("ddd" x PIPE_BUF),
            ("eee" x PIPE_BUF),
        ),
        "Message is valid, not mangled"
    );

    $seen{substr($msg, 0, 1)}++;

    last if ++$seen{TOTAL} >= (5 * $COUNT);
}

delete $seen{TOTAL};

is(
    \%seen,
    {a => $COUNT, b => $COUNT, c => $COUNT, d => $COUNT, e => $COUNT},
    "Got all $COUNT messages from each process"
);

done_testing;
