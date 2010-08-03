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
my $VERSION   = q{Version 0.0.0};
my $AUTHOR    = q{David Goh <david@goh.id.au> - http://goh.id.au/~david/};
my $SOURCE    = q{GIT: http://github.com/thorfi/nagios-bind9-plugin};
my $LICENSE =
    q{Licensed as GPLv3 or later - http://www.gnu.org/licenses/gpl.html};

# Force all stderr to stdout
*STDERR = *STDOUT;

use strict;
use warnings;
use Carp ();
use English;
use Getopt::Long;
use Socket;
use IO::Socket;

eval {
    use Time::HiRes;
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
my $NAGIOS_EXIT_OKAY     = $NAGIOS_EXIT_OK;
my $NAGIOS_EXIT_WARNING  = 1;
my $NAGIOS_EXIT_CRITICAL = 2;
my $NAGIOS_EXIT_UNKNOWN  = 3;

my %OPTIONS = (
    q{qtype}     => 'NS',
    q{qname}     => '.',
    q{resolver}  => '127.0.0.1',
    q{tries}     => 3,
    q{warning}   => 10,
    q{critical}  => 100,
    q{timeout}   => 1000,
    q{source-ip} => '0.0.0.0',
);

my $print_help_sref = sub {
    print qq{Usage: $PROGRAM_NAME
        --qtype: NS/A/TXT/MX (Default: $OPTIONS{'qtype'})
        --qname: domainname to query (Default: $OPTIONS{'qname'})
     --resolver: hostname or ip.ad.re.ss (Default: $OPTIONS{'resolver'})
        --tries: queries to perform and average (Default: $OPTIONS{'tries'})
      --warning: time to return warning (Default: $OPTIONS{'warning'} msec)
     --critical: time to return critical (Default: $OPTIONS{'critical'} msec)
      --timeout: timeout (Default: $OPTIONS{'timeout'} msec)
    --source-ip: address to send queries from (Default: $OPTIONS{'source-ip'})
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
    "version" => sub { $print_version_sref->(); exit $NAGIOS_EXIT_UNKNOWN; },
    "help" => sub { $print_help_sref->(); exit $NAGIOS_EXIT_UNKNOWN; },
);
if ( not $getopt_result ) {
    $print_help_sref->();
    exit $NAGIOS_EXIT_UNKNOWN;
}

my @TRY_TIMES    = ();
my $AVERAGE_TIME = 0.0;

# Also the first item for performance data is average_time as a float
# these are all integers
my @NUMKEYS = qw(
    queries_sent responses_recv
);
my @BYTEKEYS = qw(
    udp_sent tcp_sent
    udp_recv tcp_recv
);
my @PERFKEYS = ( @NUMKEYS, @BYTEKEYS );
my %PERFDATA = map { $_ => 0 } @PERFKEYS;

my $exit_message = q{};

my $SOURCE_IPADDR = gethostbyname( $OPTIONS{'source-ip'} );
if ( not defined $SOURCE_IPADDR ) {
    print qq{Error: gethostbyname(--source-ip $OPTIONS{'source-ip'}): $!\n};
    $print_help_sref->();
    exit $NAGIOS_EXIT_UNKNOWN;
}

my $RESOLVER_IPADDR = gethostbyname( $OPTIONS{'resolver'} );
if ( not defined $RESOLVER_IPADDR ) {
    print qq{Error: gethostbyname(--source-ip $OPTIONS{'resolver'}): $!\n};
    $print_help_sref->();
    exit $NAGIOS_EXIT_UNKNOWN;
}

my %QTYPE_MAP = (
    q{A}   => 1,
    q{NS}  => 2,
    q{MX}  => 15,
    q{TXT} => 16,
);

my $QTYPE_INT = $QTYPE_MAP{ $OPTIONS{'qtype'} };
if ( not defined $QTYPE_INT ) {
    print qq{Error: Unknown --qtype $OPTIONS{'qtype'}\n};
    $print_help_sref->();
    exit $NAGIOS_EXIT_UNKNOWN;
}

# We only have "IN" query class
my $QCLASS_INT = 1;

# Trailing header chunk, representing a query which we
# have requested recursive resolution.
my $QUERY_HEADER_WIRE = pack q{B16n4}, q{0} x 7 . q{1} . q{0} x 8, 0, 0, 0, 0;

my $QUERY_TAIL = pack q{n2}, $QTYPE_INT, $QCLASS_INT;

# epoch time in seconds plus a bit of fiddling
my $first_id = time ^ $PID ^ $UID;
for my $try ( 1 .. $OPTIONS{'tries'} ) {
    my $expect_id = $first_id + $try;
    my $query = pack q{n}, $expect_id;
    $query .= $QUERY_HEADER_WIRE;
    $query .= qname2wire( $OPTIONS{'qname'} );
    $query .= $QUERY_TAIL;

    #$SIG{'ALRM'} = sub {
    #Carp::cluck(q{BIND9 plugin timed out});
    #exit $NAGIOS_EXIT_WARNING;
##};
    #alarm $OPTIONS{'timeout'};
}

my $exit_code = $NAGIOS_EXIT_OKAY;
if ( length $exit_message ) {
    $exit_code = $NAGIOS_EXIT_WARNING;
}
else {
    $exit_message = 'OKAY';
}

for my $try_time (@TRY_TIMES) {
    $AVERAGE_TIME += $try_time;
}
$AVERAGE_TIME /= $OPTIONS{'tries'};

print qq{DNS $exit_message ;};
print qq{ AVG $AVERAGE_TIME msec;};
print qq{ $PERFDATA{'responses_recv'}/$PERFDATA{'queries_sent'}};
print q{ responses/queries;};
print qq{ $PERFDATA{'udp_sent'}+$PERFDATA{'tcp_sent'} udp+tcp/sent;};
print qq{ $PERFDATA{'udp_recv'}+$PERFDATA{'tcp_recv'} udp+tcp/recv;};
print qq{ |};

# Generate perfdata in PNP4Nagios format
# http://docs.pnp4nagios.org/pnp-0.6/perfdata_format

print q{ average_time=}, $AVERAGE_TIME, q{ms};
for my $k (@NUMKEYS) {
    print q{ }, $k, q{=}, $PERFDATA{$k};
}
for my $k (@BYTEKEYS) {
    print q{ }, $k, q{=}, $PERFDATA{$k}, q{B};
}
exit $exit_code;

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

