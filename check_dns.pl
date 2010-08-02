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
    q{tries}     => 3,
    q{warning}   => 10,
    q{critical}  => 100,
    q{timeout}   => 1000,
    q{source-ip} => '0.0.0.0',
);

my $print_help_sref = sub {
    print qq{Usage: $PROGRAM_NAME
        --qtype: NS/A/TXT/MX
        --qname: domainname to query
     --resolver: hostname or ip.ad.re.ss
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
    "resolver=s"  => \$OPTIONS{'qname'},
    "tries=i"     => \$OPTIONS{'tries'},
    "warning=f"   => \$OPTIONS{'warning'},
    "critical=f"  => \$OPTIONS{'critical'},
    "timeout=f"   => \$OPTIONS{'timeout'},
    "source-ip=s" => \$OPTIONS{'source-ip'},
    "version" => sub { $print_version_sref->(); exit $NAGIOS_EXIT_UNKNOWN; },
    "help" => sub { $print_help_sref->(); exit $NAGIOS_EXIT_UNKNOWN; },
);
if ( not $getopt_result ) {
    print qq{Error: Options failure\n};
    $print_help_sref->();
    exit $NAGIOS_EXIT_UNKNOWN;
}

my @TRY_TIMES = ( 5, 7, 11 );
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

#$SIG{'ALRM'} = sub {
#Carp::cluck(q{BIND9 plugin timed out});
#exit $NAGIOS_EXIT_WARNING;
##};
#alarm $OPTIONS{'timeout'};

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
print
    qq{ $PERFDATA{'responses_recv'}/$PERFDATA{'queries_sent'} responses/queries;};
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
