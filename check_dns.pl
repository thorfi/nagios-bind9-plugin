#!/usr/bin/perl
#
# Nagios DNS Monitoring Plugin
#
# Indicate compatibility with the Nagios embedded perl interpreter
# nagios: +epn
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

my $COPYRIGHT = q{Copyright (C) 2010};
my $VERSION   = q{Version 1.0.0};
my $AUTHOR    = q{David Goh <david@goh.id.au> - http://goh.id.au/~david/};
my $SOURCE    = q{GIT: http://github.com/thorfi/nagios-bind9-plugin};
my $LICENSE =
    q{Licensed as GPLv3 or later - http://www.gnu.org/licenses/gpl.html};

# Force all stderr to stdout
*STDERR = *STDOUT;

#use strict;
#use warnings;
use Carp ();
use English;
use Getopt::Long;
use Socket;
use IO::Socket;
use IO::Select;
use POSIX ();

my $have_time_hires = 0;
eval {
    use Time::HiRes;
    $have_time_hires = 1;
};

# nagios exit codes
#0       OK      UP
#1       WARNING UP or DOWN/UNREACHABLE*
#2       CRITICAL        DOWN/UNREACHABLE
#3       UNKNOWN DOWN/UNREACHABLE
# Note: If the use_aggressive_host_checking option is enabled, return codes of
# 1 will result in a host state of DOWN or UNREACHABLE. Otherwise return codes
# of 1 will result in a host state of UP.
my $NAGIOS_EXIT_OK       = 0;
my $NAGIOS_EXIT_WARNING  = 1;
my $NAGIOS_EXIT_CRITICAL = 2;
my $NAGIOS_EXIT_UNKNOWN  = 3;

my %OPTIONS = (
    q{qtype}     => q{NS},
    q{qname}     => q{.},
    q{resolver}  => q{127.0.0.1},
    q{tries}     => 5,
    q{warning}   => 10,
    q{critical}  => 100,
    q{timeout}   => 1000,
    q{source-ip} => q{0.0.0.0},
    q{protocol}  => q{tcpfallback},
    q{select}    => 1 / 1_000.0,
    q{timehires} => $have_time_hires,
);

my $print_help_sref = sub {
    print qq{Usage: $PROGRAM_NAME
        --qtype: NS/A/TXT/MX/ANY/... (Default: $OPTIONS{'qtype'})
        --qname: domainname to query (Default: $OPTIONS{'qname'})
     --resolver: hostname or ip.ad.re.ss (Default: $OPTIONS{'resolver'})
        --tries: queries to perform and average (Default: $OPTIONS{'tries'})
      --warning: time to return warning (Default: $OPTIONS{'warning'} msec)
     --critical: time to return critical (Default: $OPTIONS{'critical'} msec)
      --timeout: timeout (Default: $OPTIONS{'timeout'} msec)
    --source-ip: address to send queries from (Default: $OPTIONS{'source-ip'})
     --protocol: both/udp/tcp/tcpfallback (Default: $OPTIONS{'protocol'})
       --select: time to wait for select tries (Default: $OPTIONS{'select'} sec)
      --version: print version and exit
         --help: print this help and exit

$PROGRAM_NAME is a Nagios Plugin which can be used to monitor a DNS server.

It forms DNS queries with the --qtype and --qname and sends them directly to
the --dns-server.

The queries will originate from --source-ip and be performed sequentially
using a new socket each time, not in parallel.

It will perform --tries queries and average the timing results.

Queries which take longer than --timeout will be abandoned and measured as if
they took --timeout milliseconds.

The average timing will be compared against --warning and --critical to return
an appropriate exit status.

Average Timing, Queries Sent, Responses Received,
Total UDP Sent Size, Total TCP Sent Size,
Total UDP Received Size, Total TCP Received Size
are also returned as performance data.

Note: If the script cannot use Time::HiRes it will use select() to do
timing. --select is used as the granularity of the timer. Timing may be 
wildly inaccurate if select() is unable to return that quickly.

$COPYRIGHT
$VERSION
$AUTHOR
$SOURCE
$LICENSE
};
};

my $print_version_sref = sub {
    print qq{$VERSION - $COPYRIGHT - $AUTHOR};
};

my $getopt_result = GetOptions(
    "qtype=s"     => \$OPTIONS{'qtype'},
    "qname=s"     => \$OPTIONS{'qname'},
    "resolver=s"  => \$OPTIONS{'resolver'},
    "tries=i"     => \$OPTIONS{'tries'},
    "warning=f"   => \$OPTIONS{'warning'},
    "critical=f"  => \$OPTIONS{'critical'},
    "timeout=f"   => \$OPTIONS{'timeout'},
    "source-ip=s" => \$OPTIONS{'source-ip'},
    "protocol=s"  => \$OPTIONS{'protocol'},
    "timehires!"  => \$OPTIONS{'timehires'},
    "version" => sub { $print_version_sref->(); exit $NAGIOS_EXIT_UNKNOWN; },
    "help" => sub { $print_help_sref->(); exit $NAGIOS_EXIT_UNKNOWN; },
);
if ( not $getopt_result ) {
    $print_help_sref->();
    exit $NAGIOS_EXIT_UNKNOWN;
}

if ( $OPTIONS{'protocol'} !~ m/^(udp|tcp|both|tcpfallback)$/ ) {
    print qq{Error: --protocol $OPTIONS{'protocol'} unknown\n};
    $print_help_sref->();
    exit $NAGIOS_EXIT_UNKNOWN;
}

my @TRY_TIMES = ();

# Also the first item for performance data is average_time as a float
# these are all integers
my @NUMKEYS = qw(
    udp_queries udp_responses
    tcp_queries tcp_responses
);
my @BYTEKEYS = qw(
    udp_sent tcp_sent
    udp_recv tcp_recv
);
my @PERFKEYS = ( @NUMKEYS, @BYTEKEYS );
my %PERFDATA = map { $_ => 0 } @PERFKEYS;

$PERFDATA{'error_message'} = q{};

my $SOURCE_IPADDR = gethostbyname( $OPTIONS{'source-ip'} );
if ( not defined $SOURCE_IPADDR ) {
    print
        qq{Error: gethostbyname(--source-ip $OPTIONS{'source-ip'}): $ERRNO\n};
    $print_help_sref->();
    exit $NAGIOS_EXIT_UNKNOWN;
}
$OPTIONS{'source-ipaddr'} = $SOURCE_IPADDR;

my $RESOLVER_IPADDR = gethostbyname( $OPTIONS{'resolver'} );
if ( not defined $RESOLVER_IPADDR ) {
    print
        qq{Error: gethostbyname(--source-ip $OPTIONS{'resolver'}): $ERRNO\n};
    $print_help_sref->();
    exit $NAGIOS_EXIT_UNKNOWN;
}
$OPTIONS{'resolver-ipaddr'} = $RESOLVER_IPADDR;

# MAP data OBTAINED FROM CPAN Net::DNS
my %QTYPE_MAP = (
    'SIGZERO'    => 0,     # RFC2931 consider this a pseudo type
    'A'          => 1,     # RFC 1035, Section 3.4.1
    'NS'         => 2,     # RFC 1035, Section 3.3.11
    'MD'         => 3,     # RFC 1035, Section 3.3.4 (obsolete)
    'MF'         => 4,     # RFC 1035, Section 3.3.5 (obsolete)
    'CNAME'      => 5,     # RFC 1035, Section 3.3.1
    'SOA'        => 6,     # RFC 1035, Section 3.3.13
    'MB'         => 7,     # RFC 1035, Section 3.3.3
    'MG'         => 8,     # RFC 1035, Section 3.3.6
    'MR'         => 9,     # RFC 1035, Section 3.3.8
    'NULL'       => 10,    # RFC 1035, Section 3.3.10
    'WKS'        => 11,    # RFC 1035, Section 3.4.2 (deprecated)
    'PTR'        => 12,    # RFC 1035, Section 3.3.12
    'HINFO'      => 13,    # RFC 1035, Section 3.3.2
    'MINFO'      => 14,    # RFC 1035, Section 3.3.7
    'MX'         => 15,    # RFC 1035, Section 3.3.9
    'TXT'        => 16,    # RFC 1035, Section 3.3.14
    'RP'         => 17,    # RFC 1183, Section 2.2
    'AFSDB'      => 18,    # RFC 1183, Section 1
    'X25'        => 19,    # RFC 1183, Section 3.1
    'ISDN'       => 20,    # RFC 1183, Section 3.2
    'RT'         => 21,    # RFC 1183, Section 3.3
    'NSAP'       => 22,    # RFC 1706, Section 5
    'NSAP_PTR'   => 23,    # RFC 1348 (obsolete by RFC 1637)
    'SIG'        => 24,    # RFC 2535, Section 4.1 impemented in Net::DNS::SEC
    'KEY'        => 25,    # RFC 2535, Section 3.1 impemented in Net::DNS::SEC
    'PX'         => 26,    # RFC 2163,
    'GPOS'       => 27,    # RFC 1712 (obsolete ?)
    'AAAA'       => 28,    # RFC 1886, Section 2.1
    'LOC'        => 29,    # RFC 1876
    'NXT'        => 30,    # RFC 2535, Section 5.2 obsoleted by RFC3755
    'EID'        => 31,    # draft-ietf-nimrod-dns-xx.txt
    'NIMLOC'     => 32,    # draft-ietf-nimrod-dns-xx.txt
    'SRV'        => 33,    # RFC 2052
    'ATMA'       => 34,    # non-standard
    'NAPTR'      => 35,    # RFC 2168
    'KX'         => 36,    # RFC 2230
    'CERT'       => 37,    # RFC 2538
    'A6'         => 38,    # RFC3226, RFC2874. See RFC 3363 made A6 exp.
    'DNAME'      => 39,    # RFC 2672
    'SINK'       => 40,    # non-standard
    'OPT'        => 41,    # RFC 2671
    'APL'        => 42,    # RFC 3123
    'DS'         => 43,    # RFC 4034
    'SSHFP'      => 44,    # RFC 4255
    'IPSECKEY'   => 45,    # RFC 4025
    'RRSIG'      => 46,    # RFC 4034
    'NSEC'       => 47,    # RFC 4034
    'DNSKEY'     => 48,    # RFC 4034
    'DHCID'      => 49,    # RFC4701
    'NSEC3'      => 50,    # RFC5155
    'NSEC3PARAM' => 51,    # RFC5155

    # 52-54 are unassigned
    'HIP'   => 55,         # RFC5205
    'NINFO' => 56,         # non-standard
    'RKEY'  => 57,         # non-standard

    # 58-98 are unassigned
    'SPF'    => 99,        # RFC 4408
    'UINFO'  => 100,       # non-standard
    'UID'    => 101,       # non-standard
    'GID'    => 102,       # non-standard
    'UNSPEC' => 103,       # non-standard

    # 104-248 are unassigned
    'TKEY'  => 249,        # RFC 2930
    'TSIG'  => 250,        # RFC 2931
    'IXFR'  => 251,        # RFC 1995
    'AXFR'  => 252,        # RFC 1035
    'MAILB' => 253,        # RFC 1035 (MB, MG, MR)
    'MAILA' => 254,        # RFC 1035 (obsolete - see MX)
    'ANY'   => 255,        # RFC 1035
    'TA'    => 32768,      # non-standard
    'DLV'   => 32769,      # RFC 4431
);

my $QTYPE_INT = $QTYPE_MAP{ uc $OPTIONS{'qtype'} };
if ( not defined $QTYPE_INT ) {
    print qq{Error: Unknown --qtype $OPTIONS{'qtype'}\n};
    $print_help_sref->();
    exit $NAGIOS_EXIT_UNKNOWN;
}

# We only have "IN" query class
my $QCLASS_INT = 1;

# Trailing header chunk, representing a query which we
# have requested recursive resolution, and saying we have one query.
my $QUERY_HEADER_WIRE = pack q{B16n4}, q{0} x 7 . q{1} . q{0} x 8, 1, 0, 0, 0;

my $QUERY_TAIL = pack q{n2}, $QTYPE_INT, $QCLASS_INT;

my $send_query_sref;
if ( $OPTIONS{'timehires'} ) {

    # Time::HiRes exists, do this
    $send_query_sref = \&sendrecv_time_hires;
}
else {

    # No Time::HiRes, we have to rely on evil hackery with select.
    $send_query_sref = \&sendrecv_select;
}

# epoch time in seconds plus a bit of fiddling
#my $first_id = time ^ $PID ^ $UID;
my $first_id = 0xaaa9;
for my $try ( 1 .. int $OPTIONS{'tries'} ) {
    my $query_id = $first_id + $try;
    my $query = pack q{n}, $query_id;
    $query .= $QUERY_HEADER_WIRE;
    $query .= qname2wire( $OPTIONS{'qname'} );
    $query .= $QUERY_TAIL;

    my $start_time = Time::HiRes::time();
    my ( $msec_taken, $perfdata_href ) =
        $send_query_sref->( $query, $query_id, \%OPTIONS );
    my $end_time = Time::HiRes::time();
    my $hires_tt = $end_time - $start_time;

    #print "ZZZ $msec_taken $hires_tt\n";
    push @TRY_TIMES, $msec_taken;
    for my $k (@PERFKEYS) {
        $PERFDATA{$k} += $perfdata_href->{$k};
    }
}

my $exit_code = $NAGIOS_EXIT_OK;
if ( length $PERFDATA{'error_message'} ) {

    # Already got a warning
    $exit_code = $NAGIOS_EXIT_WARNING;
}
my $average_msec = 0.0;
for my $try_time (@TRY_TIMES) {
    $average_msec += $try_time;
}
$average_msec /= $OPTIONS{'tries'};

if ( $average_msec > $OPTIONS{'critical'} ) {
    $PERFDATA{'error_message'}
        .= qq{CRITICAL AVG > $OPTIONS{'critical'}msec\n};
    $exit_code = $NAGIOS_EXIT_CRITICAL;
}
elsif ( $average_msec > $OPTIONS{'warning'} ) {
    $PERFDATA{'error_message'} .= qq{WARNING AVG > $OPTIONS{'warning'}msec\n};
    $exit_code = $NAGIOS_EXIT_WARNING;
}

if ( length $PERFDATA{'error_message'} < 1 ) {
    $PERFDATA{'error_message'} = 'OK';
}
else {
    chomp $PERFDATA{'error_message'};
    $PERFDATA{'error_message'} =~ s/\n/,/g;
    $PERFDATA{'error_message'} =~ s/\s+/ /g;
}

print qq{DNS $PERFDATA{'error_message'};};
printf q{ AVG %.3f msec}, $average_msec;
if ($OPTIONS{'timehires'}) {
    print qq{;};
}
else {
    print qq{ (INACCURATE - No Time::HiRes);};
}
print qq{ $PERFDATA{'udp_responses'}+$PERFDATA{'tcp_responses'}};
print qq{/$PERFDATA{'udp_queries'}+$PERFDATA{'tcp_queries'}};
print q{ udp+tcp responses/queries;};
print qq{ $PERFDATA{'udp_sent'}b+$PERFDATA{'tcp_sent'}b udp+tcp/sent;};
print qq{ $PERFDATA{'udp_recv'}b+$PERFDATA{'tcp_recv'}b udp+tcp/recv;};
print qq{ |};

# Generate perfdata in PNP4Nagios format
# http://docs.pnp4nagios.org/pnp-0.6/perfdata_format

printf q{ average_time=%.3fms }, $average_msec;
for my $k (@NUMKEYS) {
    print q{ }, $k, q{=}, $PERFDATA{$k};
}
for my $k (@BYTEKEYS) {
    print q{ }, $k, q{=}, $PERFDATA{$k}, q{B};
}
print q{ have_time_hires=}, $OPTIONS{'timehires'};
exit $exit_code;

sub udp_socket {
    my ($options_href) = @_;
    my $proto = getprotobyname('udp') or return undef;
    my $local_in = sockaddr_in( 0, $options_href->{'source-ipaddr'} );
    my $sock_obj = new IO::Socket;
    socket $sock_obj, PF_INET, SOCK_DGRAM, $proto or return undef;
    bind $sock_obj, $local_in or return undef;
    return $sock_obj;
}

sub udp_send {
    my ( $query, $options_href ) = @_;
    my $sock_obj = udp_socket($options_href) or return undef;
    my $peer_in = sockaddr_in( 53, $options_href->{'resolver-ipaddr'} );
    send $sock_obj, $query, 0, $peer_in or return undef;
    return $sock_obj;
}

sub tcp_socket {
    my ($options_href) = @_;
    my $proto = getprotobyname('tcp') or return undef;
    my $local_in = sockaddr_in( 0, $options_href->{'source-ipaddr'} );
    my $sock_obj = new IO::Socket;
    socket $sock_obj, PF_INET, SOCK_STREAM, $proto or return undef;
    bind $sock_obj, $local_in or return undef;
    return $sock_obj;
}

sub tcp_send {
    my ( $query, $options_href ) = @_;
    my $sock_obj = tcp_socket($options_href);
    if ( not defined $sock_obj ) {
        return undef;
    }
    my $peer_in = sockaddr_in( 53, $options_href->{'resolver-ipaddr'} );
    connect $sock_obj, $peer_in or return undef;
    my $tcp_msg = pack q{n}, length $query;
    $tcp_msg .= $query;
    my $idx = 0;
    my $len = length $tcp_msg;

    while ( $idx < $len ) {
        my $result = send $sock_obj, $tcp_msg, 0, $peer_in;
        if ( not defined $result ) {
            return undef;
        }
        $idx += $result;
    }
    return $sock_obj;
}

sub tcp_sysread {
    my ( $sock_obj, $expect_octets ) = @_;
    my $buf    = '';
    my $bufidx = 0;
    while ( $bufidx < $expect_octets ) {
        my $retval = sysread $sock_obj, $buf, ( $expect_octets - $bufidx ),
            $bufidx;
        if ( not defined $retval ) {
            last;
        }
        $bufidx += $retval;
    }
    return $buf;
}

sub tcp_sysread_timeout {
    my ( $sock_obj, $expect_octets, $io_s, $time_left, $select ) = @_;
    my $buf        = '';
    my $bufidx     = 0;
    my $time_taken = 0.0;
    while ( $bufidx < $expect_octets ) {
        my ( $ready_time, @ready ) =
            timed_can_read( $io_s, $time_left, $select );
        $time_taken += $ready_time;
        $time_left -= $ready_time;
        if ( $time_left <= 0 ) {
            last;
        }
        if ( int @ready < 1 ) {
            next;
        }
        my $retval = sysread $sock_obj, $buf, ( $expect_octets - $bufidx ),
            $bufidx;
        if ( not defined $retval ) {
            last;
        }
        $bufidx += $retval;
    }
    return ( $buf, $time_taken );
}

sub unpack_header {
    my ($dns_packet) = @_;

    #print map {' ' . unpack 'b8', $_} split '', $dns_packet;
    my @r_keys = qw(id bitfield qdcount ancount nscount arcount);
    my @r_values = unpack q{nB16nnnn}, $dns_packet;
    if ( int @r_values != int @r_keys ) {
        return undef;
    }
    my %r_data;
    @r_data{@r_keys} = @r_values;
    my $bitfield = $r_data{'bitfield'};
    $r_data{'qr'}     = substr $bitfield, 0,  1;
    $r_data{'opcode'} = substr $bitfield, 1,  4;
    $r_data{'aa'}     = substr $bitfield, 5,  1;
    $r_data{'tc'}     = substr $bitfield, 6,  1;
    $r_data{'rd'}     = substr $bitfield, 7,  1;
    $r_data{'ra'}     = substr $bitfield, 8,  1;
    $r_data{'z'}      = substr $bitfield, 9,  3;
    $r_data{'rcode'}  = substr $bitfield, 12, 4;
    return \%r_data;
}

sub timed_can_write {
    my ( $io_s, $timeout, $select_interval ) = @_;
    my $time_taken = 0.0;
    my @ready      = ();
    while ( int @ready < 1 and $time_taken < $timeout ) {
        @ready = $io_s->can_write($select_interval);
        $time_taken += $select_interval;
    }
    return ( $time_taken, @ready );
}

sub timed_can_read {
    my ( $io_s, $timeout, $select_interval ) = @_;
    my $time_taken = 0.0;
    my @ready      = ();
    while ( int @ready < 1 and $time_taken < $timeout ) {
        @ready = $io_s->can_read($select_interval);
        $time_taken += $select_interval;
    }
    return ( $time_taken, @ready );
}

sub sendrecv_select {
    my ( $query, $query_id, $options_href ) = @_;
    my $peer_in = sockaddr_in( 53, $options_href->{'resolver-ipaddr'} );
    my %perfdata = map { $_ => 0, } @PERFKEYS;
    $perfdata{'timed_out'}     = 0;
    $perfdata{'error_message'} = '';

    my $time_taken = 0.0;
    my $time_left  = $options_href->{'timeout'} / 1000.0;

    if ( $options_href->{'protocol'} ne q{tcp} ) {

        # protocol is udp or tcpfallback
        my $sock_obj = udp_socket($options_href);
        if ( not defined $sock_obj ) {
            $perfdata{'error_message'} .= qq{udp_socket $ERRNO\n};
            return ( $options_href->{'timeout'}, \%perfdata );
        }
        $sock_obj->blocking(0);
        my $io_s = IO::Select->new();
        $io_s->add($sock_obj);
        my ( $ready_time, @ready ) =
            timed_can_write( $io_s, $time_left, $options_href->{'select'} );

        # Making the assumption that the UDP send will not take
        # a significant amount of time, and in addition we can't
        # really do non-blocking IO on udp packets anyway
        $time_left -= $ready_time;
        $time_taken += $ready_time;
        if ( $time_left <= 0 ) {
            $perfdata{'timed_out'} = 1;
            return ( $options_href->{'timeout'}, \%perfdata );
        }
        if ( not send $sock_obj, $query, 0, $peer_in ) {
            $perfdata{'error_message'} .= qq{udp_send $ERRNO\n};
            return ( $options_href->{'timeout'}, \%perfdata );
        }

        $perfdata{'udp_queries'} += 1;
        $perfdata{'udp_sent'} += length $query;
        my $response = '';
        ( $ready_time, @ready ) =
            timed_can_read( $io_s, $time_left, $options_href->{'select'} );
        $time_left -= $ready_time;
        $time_taken += $ready_time;
        if ( $time_left <= 0 ) {
            $perfdata{'timed_out'} = 1;
            return ( $options_href->{'timeout'}, \%perfdata );
        }
        if ( not defined recv $sock_obj, $response, 65535, 0 ) {
            if ( not $perfdata{'timed_out'} ) {
                $perfdata{'error_message'} .= qq{udp_recv $ERRNO\n};
            }
            return ( $options_href->{'timeout'}, \%perfdata );
        }
        close $sock_obj;

        my $r_data_href = unpack_header($response);
        if ( $r_data_href->{'id'} != $query_id ) {
            $perfdata{'error_message'} .= qq{udp_recv bad response id\n};
            return ( $options_href->{'timeout'}, \%perfdata );
        }

        if ( ( not $r_data_href->{'tc'} )  and
            ( $r_data_href->{'ancount'} < 1 ) ) {
            # Not truncated, and we got no answers
            # so return as failure
            $perfdata{'error_message'} .= qq{udp_recv no answers\n};
            return ( $options_href->{'timeout'}, \%perfdata );
        }

        $perfdata{'udp_responses'} += 1;
        $perfdata{'udp_recv'} += length $response;

        if (( $options_href->{'protocol'} eq 'udp' )
            or (    ( $options_href->{'protocol'} eq 'tcpfallback' )
                and ( not $r_data_href->{'tc'} ) )
            )
        {

            # protocol udp only
            # or tcpfallback and the packet is not truncated
            # so our work is done
            return ( $time_taken, \%perfdata );
        }
    }

    # protocol is both, tcp or tcpfallback
    #
    my $sock_obj = tcp_socket($options_href);
    if ( not defined $sock_obj ) {
        $perfdata{'error_message'} .= qq{tcp_socket $ERRNO\n};
        return ( $options_href->{'timeout'}, \%perfdata );
    }
    $sock_obj->blocking(0);
    $ERRNO = 0;
    connect $sock_obj, $peer_in;
    if ( $ERRNO != POSIX::EINPROGRESS ) {

        # Connect should return operation in progress
        $perfdata{'error_message'} .= qq{tcp_connect $ERRNO\n};
        return ( $options_href->{'timeout'}, \%perfdata );
    }

    my $io_s = IO::Select->new();
    $io_s->add($sock_obj);

    my $tcp_msg = pack q{n}, length $query;
    $tcp_msg .= $query;
    my $idx = 0;
    my $len = length $tcp_msg;

    while ( $idx < $len ) {
        my ( $ready_time, @ready ) =
            timed_can_write( $io_s, $time_left, $options_href->{'select'} );
        $time_left -= $ready_time;
        $time_taken += $ready_time;
        if ( $time_left <= 0 ) {
            $perfdata{'timed_out'} = 1;
            return ( $options_href->{'timeout'}, \%perfdata );
        }
        my $result = send $sock_obj, $tcp_msg, 0, $peer_in;
        if ( not defined $result ) {
            $perfdata{'error_message'} .= qq{tcp_send $ERRNO\n};
            return ( $options_href->{'timeout'}, \%perfdata );
        }
        $idx += $result;
    }

    $perfdata{'tcp_queries'} += 1;
    $perfdata{'tcp_sent'} += length $query;
    my ( $chunk, $c_read_time ) =
        tcp_sysread_timeout( $sock_obj, 2, $io_s, $time_left,
        $options_href->{'select'} );
    $time_left -= $c_read_time;
    $time_taken += $c_read_time;
    if ( $time_left <= 0 ) {
        $perfdata{'timed_out'} = 1;
        return ( $options_href->{'timeout'}, \%perfdata );
    }
    my $resp_length = unpack q{n}, $chunk;
    my ( $response, $r_read_time ) =
        tcp_sysread_timeout( $sock_obj, $resp_length, $io_s, $time_left,
        $options_href->{'select'} );
    $time_left -= $r_read_time;
    $time_taken += $r_read_time;
    if ( $time_left <= 0 ) {
        $perfdata{'timed_out'} = 1;
        return ( $options_href->{'timeout'}, \%perfdata );
    }
    my $r_data_href = unpack_header($response);
    if ( $r_data_href->{'id'} != $query_id ) {
        $perfdata{'error_message'} .= qq{tcp_sysread bad response id\n};
        return ( $options_href->{'timeout'}, \%perfdata );
    }
    if ( $r_data_href->{'ancount'} < 1 ) {
        $perfdata{'error_message'} .= qq{tcp_sysread no answers\n};
        return ( $options_href->{'timeout'}, \%perfdata );
    }
    $perfdata{'tcp_responses'} += 1;
    $perfdata{'tcp_recv'} += length $response;
    close $sock_obj;
    return ( 1000 * $time_taken, \%perfdata );
}

sub sendrecv_time_hires {
    my ( $query, $query_id, $options_href ) = @_;
    my %perfdata = map { $_ => 0, } @PERFKEYS;
    $perfdata{'timed_out'}     = 0;
    $perfdata{'error_message'} = '';

    $SIG{'ALRM'} = sub {
        $perfdata{'timed_out'} = 1;
    };
    Time::HiRes::alarm( $options_href->{'timeout'} / 1000.0 );
    my $start_time = Time::HiRes::time();

    sendrecv_alarmed_( \%perfdata, $query, $query_id, $options_href );
    if ( length $perfdata{'error_message'} ) {
        return ( $options_href->{'timeout'}, \%perfdata );
    }

    my $end_time   = Time::HiRes::time();
    my $time_taken = ( $end_time - $start_time );

    return ( 1000 * $time_taken, \%perfdata );
}

sub sendrecv_alarmed_ {
    my ( $perfdata_href, $query, $query_id, $options_href ) = @_;

    if ( $options_href->{'protocol'} ne q{tcp} ) {

        # protocol is udp or tcpfallback
        my $sock_obj = udp_send( $query, $options_href );
        if ( not defined $sock_obj ) {
            $perfdata_href->{'error_message'} .= qq{udp_send $ERRNO\n};
            return;
        }
        $perfdata_href->{'udp_queries'} += 1;
        $perfdata_href->{'udp_sent'} += length $query;
        my $response = '';
        if ( not defined recv $sock_obj, $response, 65535, 0 ) {
            if ( not $perfdata_href->{'timed_out'} ) {
                $perfdata_href->{'error_message'} .= qq{udp_recv $ERRNO\n};
            }
            return;
        }
        close $sock_obj;

        my $r_data_href = unpack_header($response);
        if ( $r_data_href->{'id'} != $query_id ) {
            $perfdata_href->{'error_message'}
                .= qq{udp_recv bad response id\n};
            return;
        }

        if ( ( not $r_data_href->{'tc'} )  and
            ( $r_data_href->{'ancount'} < 1 ) ) {
            # Not truncated, and we got no answers
            # so return as failure
            $perfdata{'error_message'} .= qq{udp_recv no answers\n};
            return;
        }

        $perfdata_href->{'udp_responses'} += 1;
        $perfdata_href->{'udp_recv'} += length $response;

        if (( $options_href->{'protocol'} eq 'udp' )
            or (    ( $options_href->{'protocol'} eq 'tcpfallback' )
                and ( not $r_data_href->{'tc'} ) )
            )
        {

            # protocol udp only
            # or tcpfallback and the packet is not truncated
            # so our work is done
            return;
        }
    }

    # protocol is both, tcp or tcpfallback
    #
    my $sock_obj = tcp_send( $query, $options_href );
    if ( not defined $sock_obj ) {
        $perfdata_href->{'error_message'} .= qq{tcp_send $!\n};
        return;
    }

    $perfdata_href->{'tcp_queries'} += 1;
    $perfdata_href->{'tcp_sent'} += length $query;
    my $chunk = tcp_sysread( $sock_obj, 2 );
    if ( $perfdata_href->{'timed_out'} ) {
        return;
    }
    my $resp_length = unpack q{n}, $chunk;
    my $response = tcp_sysread( $sock_obj, $resp_length );
    if ( $perfdata_href->{'timed_out'} ) {
        return;
    }
    my $r_data_href = unpack_header($response);
    if ( $r_data_href->{'id'} != $query_id ) {
        $perfdata_href->{'error_message'}
            .= qq{tcp_sysread bad response id\n};
        return;
    }
    if ( $r_data_href->{'ancount'} < 1 ) {
        $perfdata{'error_message'} .= qq{tcp_sysread no answers\n};
        return ( $options_href->{'timeout'}, \%perfdata );
    }
    $perfdata_href->{'tcp_responses'} += 1;
    $perfdata_href->{'tcp_recv'} += length $response;
    close $sock_obj;
}

#
# CODE OBTAINED FROM CPAN Net::DNS
#
sub wire2presentation {
    my $wire         = shift;
    my $presentation = "";
    my $length       = length($wire);

    # There must be a nice regexp to do this.. but since I failed to
    # find one I scan the name string until I find a '\', at that time
    # I start looking forward and do the magic.

    my $i = 0;

    while ( $i < $length ) {
        my $char = unpack( "x" . $i . "C1", $wire );
        if ( $char < 33 || $char > 126 ) {
            $presentation .= sprintf( "\\%03u", $char );
        }
        elsif ( $char == ord("\"") ) {
            $presentation .= "\\\"";
        }
        elsif ( $char == ord("\$") ) {
            $presentation .= "\\\$";
        }
        elsif ( $char == ord("(") ) {
            $presentation .= "\\(";
        }
        elsif ( $char == ord(")") ) {
            $presentation .= "\\)";
        }
        elsif ( $char == ord(";") ) {
            $presentation .= "\\;";
        }
        elsif ( $char == ord("@") ) {
            $presentation .= "\\@";
        }
        elsif ( $char == ord("\\") ) {
            $presentation .= "\\\\";
        }
        elsif ( $char == ord(".") ) {
            $presentation .= "\\.";
        }
        else {
            $presentation .= chr($char);
        }
        $i++;
    }

    return $presentation;

}

# in: $dname a string with a domain name in presentation format (1035
# sect 5.1)
# out: an array of labels in wire format.

sub name2labels {
    my $dname = shift;
    my @names;
    my $j = 0;
    while ($dname) {
        ( $names[$j], $dname ) = presentation2wire($dname);
        $j++;
    }

    return @names;
}

# Will parse the input presentation format and return everything before
# the first non-escaped "." in the first element of the return array and
# all that has not been parsed yet in the 2nd argument.

sub presentation2wire {
    my $presentation = shift;
    my $wire         = "";
    my $length       = length $presentation;

    my $i = 0;

    while ( $i < $length ) {
        my $char = unpack( "x" . $i . "C1", $presentation );
        if ( $char == ord('.') ) {
            return ( $wire, substr( $presentation, $i + 1 ) );
        }
        if ( $char == ord('\\') ) {

            #backslash found
            pos($presentation) = $i + 1;
            if ( $presentation =~ /\G(\d\d\d)/ ) {
                $wire .= pack( "C", $1 );
                $i += 3;
            }
            elsif ( $presentation =~ /\Gx([0..9a..fA..F][0..9a..fA..F])/ ) {
                $wire .= pack( "H*", $1 );
                $i += 3;
            }
            elsif ( $presentation =~ /\G\./ ) {
                $wire .= "\.";
                $i += 1;
            }
            elsif ( $presentation =~ /\G@/ ) {
                $wire .= "@";
                $i += 1;
            }
            elsif ( $presentation =~ /\G\(/ ) {
                $wire .= "(";
                $i += 1;
            }
            elsif ( $presentation =~ /\G\)/ ) {
                $wire .= ")";
                $i += 1;
            }
            elsif ( $presentation =~ /\G\\/ ) {
                $wire .= "\\";
                $i += 1;
            }
        }
        else {
            $wire .= pack( "C", $char );
        }
        $i++;
    }

    return $wire;
}

#
# CODE OBTAINED FROM CPAN Net::DNS::Packet
# Modified to be:
# 1. non-OO
# 2. not do compression
# 3. renamed from dn_comp

sub qname2wire {
    my ($name)   = @_;
    my @names    = name2labels($name);
    my $wirename = '';

    while (@names) {
        my $label = shift @names;
        my $length = length $label || next;    # skip if null
        if ( $length > 63 ) {

            # Truncated if more than 63 octets
            $length = 63;
            $label = substr( $label, 0, $length );
        }
        $wirename .= pack( 'C a*', $length, $label );
    }

    $wirename .= pack( 'C', 0 ) unless @names;

    return $wirename;
}

