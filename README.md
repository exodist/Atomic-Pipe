# NAME

Atomic::Pipe - Send atomic messages from multiple writers across a POSIX pipe.

# DESCRIPTION

Normally if you write to a pipe from multiple processes/threads, the messages
will come mixed together unpredictably. Some messages may be interrupted by
parts of messages from other writers. This module takes advantage of some POSIX
specifications to allow multiple writers to send arbitrary data down a pipe in
atomic chunks to avoid the issue.

**NOTE:** This only works for POSIX compliant pipes on POSIX compliant systems.
Also some features may not be available on older systems, or some platforms.

Also: [https://man7.org/linux/man-pages/man7/pipe.7.html](https://man7.org/linux/man-pages/man7/pipe.7.html)

    POSIX.1 says that write(2)s of less than PIPE_BUF bytes must be
    atomic: the output data is written to the pipe as a contiguous
    sequence.  Writes of more than PIPE_BUF bytes may be nonatomic: the
    kernel may interleave the data with data written by other processes.
    POSIX.1 requires PIPE_BUF to be at least 512 bytes.  (On Linux,
    PIPE_BUF is 4096 bytes.) [...]

Under the hood this module will split your message into small sections of
slightly smaller than the PIPE\_BUF limit. Each message will be sent as 1 atomic
chunk with a 4 byte prefix indicating what process id it came from, what thread
id it came from, a chunk ID (in descending order, so if there are 3 chunks the
first will have id 2, the second 1, and the final chunk is always 0 allowing a
flush as it knows it is done) and then 1 byte with the length of the data
section to follow.

On the receiving end this module will read chunks and re-assemble them based on
the header data. So the reader will always get complete messages. Note that
message order is not guarenteed when messages are sent from multiple processes
or threads. Though all messages from any given thread/process should be in
order.

# SYNOPSIS

    use Atomic::Pipe;

    my ($r, $w) = Atomic::Pipe->pair;

    # Chunks will be set to the number of atomic chunks the message was split
    # into. It is fine to ignore the value returned, it will always be an
    # integer 1 or larger.
    my $chunks = $w->send_message("Hello");

    # $msg now contains "Hello";
    my $msg = $r->read_message;

    # Note, you can set the reader to be non-blocking:
    $r->blocking(0);

    # $msg2 will be undef as no messages were sent, and blocking is turned off.
    my $msg2 = $r->read_message;

Fork example from tests:

    use Test2::V0;
    use Test2::Require::RealFork;
    use Test2::IPC;
    use Atomic::Pipe;

    my ($r, $w) = Atomic::Pipe->pair;

    # For simplicty
    $SIG{CHLD} = 'IGNORE';

    # Forks and runs your coderef, then exits.
    sub worker(&) { ... }

    worker { is($w->write_message("aa" x $w->PIPE_BUF), 3, "$$ Wrote 3 chunks") };
    worker { is($w->write_message("bb" x $w->PIPE_BUF), 3, "$$ Wrote 3 chunks") };
    worker { is($w->write_message("cc" x $w->PIPE_BUF), 3, "$$ Wrote 3 chunks") };

    my @messages = ();
    push @messages => $r->read_message for 1 .. 3;

    is(
        [sort @messages],
        [sort(('aa' x PIPE_BUF), ('bb' x PIPE_BUF), ('cc' x PIPE_BUF))],
        "Got all 3 long messages, not mangled or mixed, order not guarenteed"
    );

    done_testing;

# METHODS

## CLASS METHODS

- $bytes = Atomic::Pipe->PIPE\_BUF

    Get the maximum number of bytes for an atomic write to a pipe.

- ($r, $w) = Atomic::Pipe->pair

    Create a pipe, returns a list consisting of a reader and a writer.

- $p = Atomic::Pipe->new

    If you really must have a `new()` method it is here for you to abuse. The
    returned pipe has both handles, it is your job to then turn it into 2 clones
    one with the reader and one with the writer. It is also your job to make you do
    not have too many handles floating around preventing an EOF.

- $p = Atomic::Pipe->from\_fh($fh)
- $p = Atomic::Pipe->from\_fh($mode, $fh)

    Create an instance around an existing filehandle (A clone of the handle will be
    made and kept internally).

    This will fail if the handle is not a pipe.

    If no mode is provided this constructor will determine the mode (reader or
    writer) for you from the given handle. **Note:** This works on linux, but not
    BSD or Solaris, on most platforms your must provide a mode.

    Valid modes:

    - '>&'

        Write-only.

    - '>&='

        Write-only and reuse fileno.

    - '<&'

        Read-only.

    - '<&='

        Read-only and reuse fileno.

- $p = Atomic::Pipe->from\_fd($mode, $fd)

    `$fd` must be a file descriptor number.

    This will fail if the fd is not a pipe.

    You must specify one of these modes (as a string):

    - '>&'

        Write-only.

    - '>&='

        Write-only and reuse fileno.

    - '<&'

        Read-only.

    - '<&='

        Read-only and reuse fileno.

## OBJECT METHODS

### PRIMARY INTERFACE

- $p->write\_message($msg)

    Send a message in atomic chunks.

- $msg = $p->read\_message

    Get the next message. This will block until a message is received unless you
    set `$p->blocking(0)`. If blocking is turned off, and no message is ready,
    this will return undef. This will also return undef when the pipe is closed
    (EOF).

- $p->blocking($bool)
- $bool = $p->blocking

    Get/Set blocking status.

- $bool = $p->eof

    True if EOF (all writers are closed).

- $p->close

    Close this end of the pipe (or both ends if this is not yet split into
    reader/writer pairs).

### RESIZING THE PIPE BUFFER

On some newer linux systems it is possible to get/set the pipe size. On
supported systems these allow you to do that, on other systems they are no-ops,
and any that return a value will return undef.

**Note:** This has nothing to do with the similarly named `PIPE_BUF` which
cannot be changed. This simply effects how much data can sit in a pipe before
the writers block, it does not effect the max size of atomic writes.

- $bytes = $p->size

    Current size of the pipe buffer.

- $bytes = $p->max\_size

    Maximum size, or undef if that cannot be determined. (Linux only for now).

- $p->resize($bytes)

    Attempt to set the pipe size in bytes. It may not work, so check
    `$p->size`.

- $p->resize\_or\_max($bytes)

    Attempt to set the pipe to the specified size, but if the size is larger than
    the maximum fall back to the maximum size instead.

### SPLITTING THE PIPE INTO READER AND WRITER

If you used `Atomic::Pipe->new()` you need to now split the one object
into readers and writers. These help you do that.

- $bool = $p->is\_reader

    This returns true if this instance is ONLY a reader.

- $p->is\_writer

    This returns true if this instance is ONLY a writer.

- $p->clone\_reader

    This copies the object into a reader-only copy.

- $p->clone\_writer

    This copies the object into a writer-only copy.

- $p->reader

    This turnes the object into a reader-only. Note that if you have no
    writer-copies then effectively makes it impossible to write to the pipe as you
    cannot get a writer anymore.

- $p->writer

    This turnes the object into a writer-only. Note that if you have no
    reader-copies then effectively makes it impossible to read from the pipe as you
    cannot get a reader anymore.

# SOURCE

The source code repository for Atomic-Pipe can be found at
[http://github.com/exodist/Atomic-Pipe](http://github.com/exodist/Atomic-Pipe).

# MAINTAINERS

- Chad Granum <exodist@cpan.org>

# AUTHORS

- Chad Granum <exodist@cpan.org>

# COPYRIGHT

Copyright 2020 Chad Granum <exodist7@gmail.com>.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

See [http://dev.perl.org/licenses/](http://dev.perl.org/licenses/)
