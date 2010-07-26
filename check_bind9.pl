#!/usr/bin/perl 
#
# host_check_bind.pl - Nagios BIND9 Monitoring Plugin - Host Check
#
my $COPYRIGHT = q{Copyright (C) 2010}
my $VERSION = q{Version 0.1};
my $AUTHOR = q{David Goh <david@goh.id.au> - http://goh.id.au/~david/};
my $SOURCE = q{GIT: http://github.com/thorfi/nagios-bind9-plugin};
my $LICENSE == q{Licensed as GPLv3 or later - http://www.gnu.org/licenses/gpl.html};
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

use strict;
use warnings;
use English;

# nagios exit codes
#0       OK      UP
#1       WARNING UP or DOWN/UNREACHABLE*
#2       CRITICAL        DOWN/UNREACHABLE
#3       UNKNOWN DOWN/UNREACHABLE
# Note: If the use_aggressive_host_checking option is enabled, return codes of
# 1 will result in a host state of DOWN or UNREACHABLE. Otherwise return codes
# of 1 will result in a host state of UP.
my $NAGIOS_EXIT_OK = 0
my $NAGIOS_EXIT_WARNING = 1
my $NAGIOS_EXIT_CRITICAL = 2
my $NAGIOS_EXIT_UNKNOWN = 3

use Getopt::Long;
use IPC::Open2;
use IO::File;

my %OPTIONS = (
    q{ps-path} => q{/bin/ps},
    q{pid-path} => q{/var/run/named.pid},
    q{rndc-path} => q{/usr/sbin/rndc},
    q{rndc-args} => q{},
    q{sudo-path} => q{},
    q{stats-path} => q{/var/cache/bind/named.stats},
    q{verbose} => 0,
);

# Options to supply to ps command
# These commands are presumed to result in lines with the PID in 
# column two (whitespace separated).
# Column two will be expected to match the whitespace trimmed contents
# of the --pid-path
my %PS_OPTS_FOR_OS = (
    q{darwin} => q{auxww},
    q{freebsd} => q{auxww},
    q{linux} => q{auxww},
    q{hpux} => q{-ef},
    q{irix} => q{-ef},
    q{openbsd} => q{auxww},
    q{solaris} => q{-ef},
    q{sunos} => q{auxww},
);

my $PS_OPTIONS = $PS_OPTS_FOR_OS{$OSNAME} || q{auxww};

sub print_help {
    print qq{Usage: $PROGRAM_NAME
   --ps-path: /.pid (Default: $OPTIONS{'pid-path'})
  --pid-path: /path/to/named.pid (Default: $OPTIONS{'pid-path'})
 --rndc-path: /path/to/sbin/rndc (Default: $OPTIONS{'rndc-path'})
 --sudo-path: /path/to/bin/sudo (Default: None)
--stats-path: /path/to/named.stats (Default: $OPTIONS{'stats-path'})
 --rndc-args: additional args to rndc (Default: None)
   --verbose: print additional verbose data to stderr
   --version: print version and exit
      --help: print this help and exit

$PROGRAM_NAME is a Nagios Plugin which checks that BIND9 is working
by checking the contents of --pid-path and checking that that process
is alive.

If --rndc-args is set, the argument will have any semicolons, ampersands,
angle brackets and pipe characters removed, and then bit split on whitespace
and supplied as individual arguments in between 'rndc' and 'stats'

If --pid-path is set to empty string or a non-existent file, no check
will be done.

It also calls rndc status, rndc stats, and reports the latest statistics found
in --stats-path as well as gathered from rndc status

If --sudo-path is specified then it will be used to call rndc
};

    if ( not defined $PS_OPTS_FOR_OS{$OSNAME}) {
        print qq{
Unknown \$OSNAME $OSNAME, please report to $AUTHOR with OSNAME and ps options
that will result in lines with the PID in column two (whitespace separated).
Column two of the output from ps will be expected to match the whitespace
trimmed contents of --pid-path
};
    }

    print qq{
$COPYRIGHT
$VERSION
$AUTHOR
$SOURCE
$LICENSE
};
}

sub print_version {
    print qq{$VERSION - $COPYRIGHT - $AUTHOR};
}

my $getopt_result = GetOptions (
    "pid-path=s" => \$OPTIONS{'pid-path'},
    "rndc-path=s" => \$OPTIONS{'rndc-path'},
    "sudo-path=s" => \$OPTIONS{'sudo-path'},
    "stats-path=s" => \$OPTIONS{'stats-path'},
    "rndc-args=s" => \$OPTIONS{'rndc-args'},
    "temp-path=s" => \$OPTIONS{'temp-path'},
    "verbose!"  => \$OPTIONS{'verbose'},
    "version"  => sub { print_version(); exit $NAGIOS_EXIT_UNKNOWN; },
    "help"  => sub { print_help(); exit $NAGIOS_EXIT_UNKNOWN; },
);
if ($getopt_result) {
    print qq{Error: Options failure\n};
    print_help();
    exit $NAGIOS_EXIT_UNKNOWN;
}

my @RNDC_ARGV = ();
if (len($OPTIONS{'sudo-path'})) {
    push @RNDC_ARGV, $OPTIONS{'sudo-path'};
}
push @RNDC_ARGV, $OPTIONS{'rndc-path'};
if (len($OPTIONS{'rndc-args'})) {
    my $args = $OPTIONS{'rndc-args'};
    $args =~ s/[;<>|&]//g;
    push @RNDC_ARG, split /\s+/, $args;
}

my @RNDC_STATS = (@RNDC_ARGV, q{stats},);
my @RNDC_STATUS = (@RNDC_ARGV, q{status},);

my @PERFKEYS = qw(
success referral nxrrset nxdomain recursion failure duplicate dropped
cpus
workers
zones
debug
xfers_running
xfers_deferred
soa_running
udp_running
udp_soft_limit
udp_hard_limit
tcp_running
tcp_hard_limit
);

my %PERFDATA = map { ($_ => 0,) } @PERFKEYS;

my $EXPECTED_BIND_PID;
if ($OPTIONS{'pid-path'}) {
    my $path = $OPTIONS{'pid-path'};
    if (-f $path) {
        my $fh = new IO::File $path, q{r};
        if (not defined $fh) {
            print qq{BIND9 PID file at $path failed to open\n};
            exit $NAGIOS_EXIT_CRITICAL;
        }
        my $fh_line = $fh->getline();
        $EXPECTED_BIND_PID = $fh_line;
        $EXPECTED_BIND_PID =~ s/^\s+//;
        $EXPECTED_BIND_PID =~ s/\s+$//;
        if ( $EXPECTED_BIND_PID !~ m/^\d+$/ ) {
            print qq{BIND9 PID file $path did not contain a number\n};
            exit $NAGIOS_EXIT_CRITICAL;
        }
    } else {
        print qq{BIND9 PID file $path not found\n};
        exit $NAGIOS_EXIT_CRITICAL;
    }
}

# Run rndc stats to put latest data in the stats-path
system @RNDC_STATS;

my @RNDC_STATUS = (@RNDC_ARGV, q{status},);

print q{BIND9 OK. Running:};
print qq{ $PERFDATA{'udp_running'} UDP,};
print qq{ $PERFDATA{'tcp_running'} TCP,};
print qq{ $PERFDATA{'xfers_running'} xfers,};
print qq{ $PERDATA{'zones'} zones,};
print qq{ |};
for my $k (@PERFKEYS) {
    print qq{ '$k'=$PERFDATA{$k}}
}
exit $NAGIOS_EXIT_OKAY;
