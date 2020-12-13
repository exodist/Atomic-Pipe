use Test2::V0;
use Test2::IPC;
use Atomic::Pipe;

BEGIN { *PIPE_BUF = Atomic::Pipe->can('PIPE_BUF') }

BEGIN {
    my $path = __FILE__;
    $path =~ s{[^/]+\.t$}{worker.pm};
    require "./$path";
}

my ($r, $w) = Atomic::Pipe->pair;

worker { $w->write_message("aaa") };
worker { $w->write_message("bbb") };
worker { $w->write_message("ccc") };

my @messages;
push @messages => $r->read_message for 1 .. 3;

is(
    [sort @messages],
    [sort qw/aaa bbb ccc/],
    "Got all 3 short messages"
);

worker { is($w->write_message("aa" x PIPE_BUF), 3, "$$ Wrote 3 chunks") };
worker { is($w->write_message("bb" x PIPE_BUF), 3, "$$ Wrote 3 chunks") };
worker { is($w->write_message("cc" x PIPE_BUF), 3, "$$ Wrote 3 chunks") };

sleep 2 if $^O eq 'MSWin32';

@messages = ();
push @messages => $r->read_message for 1 .. 3;

is(
    [sort @messages],
    [sort(('aa' x PIPE_BUF), ('bb' x PIPE_BUF), ('cc' x PIPE_BUF))],
    "Got all 3 long messages, not mangled or mixed"
);

cleanup();
done_testing;
