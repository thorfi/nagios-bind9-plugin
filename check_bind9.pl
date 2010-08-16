#!/usr/bin/perl 
#
# host_check_bind.pl - Nagios BIND9 Monitoring Plugin - Host Check
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
use Fcntl qw(:seek);
use Getopt::Long;
use IO::Handle;
use IO::File;

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
    q{ps-path}    => q{ps},
    q{pid-path}   => q{/var/run/named.pid},
    q{rndc-path}  => q{rndc},
    q{rndc-args}  => q{},
    q{sudo-path}  => q{},
    q{stats-path} => q{/var/run/named.stats},
    q{stats-seek} => 20480,
    q{timeout}    => 30,
);

# Options to supply to ps command
# These commands are presumed to result in lines with the PID in
# column two (whitespace separated).
# Column two will be expected to match the whitespace trimmed contents
# of the --pid-path
my %PS_OPTS_FOR_OS = (
    q{darwin}  => q{auxww},
    q{freebsd} => q{auxww},
    q{linux}   => q{auxww},
    q{hpux}    => q{-ef},
    q{irix}    => q{-ef},
    q{openbsd} => q{auxww},
    q{solaris} => q{-ef},
    q{sunos}   => q{auxww},
);

my $PS_OPTIONS = $PS_OPTS_FOR_OS{$OSNAME} || q{auxww};

my $print_help_sref = sub {
    print qq{Usage: $PROGRAM_NAME
  --pid-path: /path/to/named.pid (Default: $OPTIONS{'pid-path'})
--stats-path: /path/to/named.stats (Default: $OPTIONS{'stats-path'})
   --ps-path: /path/to/bin/ps (Default: $OPTIONS{'ps-path'})
 --rndc-path: /path/to/sbin/rndc (Default: $OPTIONS{'rndc-path'})
 --sudo-path: /path/to/bin/sudo (Default: None)
--stats-seek: bytes to seek backwards to read last stats (Default: $OPTIONS{'stats-seek'})
 --rndc-args: additional args to rndc (Default: None)
   --timeout: seconds to wait before dying (Default: $OPTIONS{'timeout'})
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

    if ( not defined $PS_OPTS_FOR_OS{$OSNAME} ) {
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
};

my $print_version_sref = sub {
    print qq{$VERSION - $COPYRIGHT - $AUTHOR};
};

my $getopt_result = GetOptions(
    "pid-path=s"   => \$OPTIONS{'pid-path'},
    "rndc-path=s"  => \$OPTIONS{'rndc-path'},
    "sudo-path=s"  => \$OPTIONS{'sudo-path'},
    "stats-path=s" => \$OPTIONS{'stats-path'},
    "stats-seek=i" => \$OPTIONS{'stats-seek'},
    "rndc-args=s"  => \$OPTIONS{'rndc-args'},
    "temp-path=s"  => \$OPTIONS{'temp-path'},
    "timeout=i"    => \$OPTIONS{'timeout'},
    "version" => sub { $print_version_sref->(); exit $NAGIOS_EXIT_UNKNOWN; },
    "help" => sub { $print_help_sref->(); exit $NAGIOS_EXIT_UNKNOWN; },
);
if ( not $getopt_result ) {
    print qq{Error: Options failure\n};
    $print_help_sref->();
    exit $NAGIOS_EXIT_UNKNOWN;
}

$SIG{'ALRM'} = sub {
    Carp::cluck(q{BIND9 plugin timed out});
    exit $NAGIOS_EXIT_WARNING;
};
alarm $OPTIONS{'timeout'};

my @RNDC_ARGV = ();
if ( length $OPTIONS{'sudo-path'} ) {
    push @RNDC_ARGV, $OPTIONS{'sudo-path'};
}
push @RNDC_ARGV, $OPTIONS{'rndc-path'};
if ( length $OPTIONS{'rndc-args'} ) {
    my $args = $OPTIONS{'rndc-args'};
    $args =~ s/[;<>|&]//g;
    push @RNDC_ARGV, split /\s+/, $args;
}

my @RNDC_STATS  = ( @RNDC_ARGV, q{stats}, );
my @RNDC_STATUS = ( @RNDC_ARGV, q{status}, );

my @STATS_KEYS = qw(
    success referral nxrrset nxdomain recursion failure duplicate dropped
);
my %STATS_ENDMAP = (
    'queries resulted in successful answer'        => 'success',
    'queries resulted in referral answer'          => 'referral',
    'queries resulted in non authoritative answer' => 'referral',
    'queries resulted in nxrrset'                  => 'nxrrset',
    'queries resulted in NXDOMAIN'                 => 'nxdomain',
    'queries caused recursion'                     => 'recursion',
    'queries resulted in SERVFAIL'                 => 'failure',
    'duplicate queries received'                   => 'duplicate',
    'queries dropped'                              => 'dropped',
);

# Regular expressions used to
# parse rndc stats data
my $STATS_RESET_RE = quotemeta q{+++ Statistics Dump +++};

my $STATS_STARTS_RE =
    q{^(} . ( join q{|}, map { quotemeta $_ } @STATS_KEYS ) . q{)};
my $STATS_ENDS_RE =
    q{(} . ( join q{|}, map { quotemeta $_ } keys %STATS_ENDMAP ) . q{)$};

my @STATUS_KEYS = qw(
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

my @PERFKEYS = ( @STATS_KEYS, @STATUS_KEYS, );
my %PERFDATA = map { ( $_ => 0, ) } @PERFKEYS;

sub slurp_command {
    my $fh = new IO::Handle;
    open $fh, q{-|}, @_ or die qq{$!};
    return $fh->getlines();
}

my $BIND_PID;
if ( $OPTIONS{'pid-path'} ) {
    my $path = $OPTIONS{'pid-path'};
    if ( -f $path ) {
        my $fh = new IO::File $path, q{r};
        if ( not defined $fh ) {
            print qq{BIND9 PID file at $path failed to open\n};
            exit $NAGIOS_EXIT_CRITICAL;
        }
        my $fh_line = $fh->getline();
        if ( not defined $fh_line ) {
            print qq{BIND9 PID file $path is empty\n};
            exit $NAGIOS_EXIT_CRITICAL;
        }
        $BIND_PID = $fh_line;
        $BIND_PID =~ s/^\s+//;
        $BIND_PID =~ s/\s+$//;
        if ( $BIND_PID !~ m/^\d+$/ ) {
            print qq{BIND9 PID file $path did not contain a number\n};
            exit $NAGIOS_EXIT_CRITICAL;
        }
        my @ps_lines = slurp_command( $OPTIONS{'ps-path'}, $PS_OPTIONS );
        my $ps_found = 0;
        for my $ps_line (@ps_lines) {
            $ps_line =~ s/^\s+//;
            my @bits = split /\s+/, $ps_line;
            if ( ( int @bits ) < 2 ) {
                next;
            }
            if ( $bits[1] eq $BIND_PID ) {
                $ps_found = 1;
                last;
            }
        }
        if ( not $ps_found ) {
            print
                qq{BIND9 PID file $path contains not-running PID $BIND_PID\n};
            exit $NAGIOS_EXIT_CRITICAL;
        }
    }
    else {
        print qq{BIND9 PID file $path not found\n};
        exit $NAGIOS_EXIT_CRITICAL;
    }
}

my $exit_message = q{};

# Run rndc stats to put latest data in the stats-path
system @RNDC_STATS;

# and slurp the latest data from stats-path
my $stats_fh = new IO::File $OPTIONS{'stats-path'}, q{r};
if ( not defined $stats_fh ) {
    $exit_message .= qq{Failed to open --stats-path };
    $exit_message .= $OPTIONS{'stats-path'};
    $exit_message .= qq{: $!.};
}
else {

    # We have a stats file, so seek backwards in it and read it out.

    $stats_fh->seek( -$OPTIONS{'stats-seek'}, SEEK_END );
    my $found_stats_start = 0;

    while ( my $stats_line = $stats_fh->getline() ) {
        chomp $stats_line;
        $stats_line =~ s/^\s+//;
        $stats_line =~ s/\s+$//;
        if ( $stats_line =~ m/$STATS_RESET_RE/i ) {

            # Reset the stats, we have a new block

            $found_stats_start = 1;
            for my $k (@STATS_KEYS) {
                $PERFDATA{$k} = 0;
            }
            next;
        }
        if ( $stats_line =~ m/$STATS_STARTS_RE/i ) {
            my $k      = $1;
            my @bits   = split /\s+/, $stats_line;
            my $number = $bits[-1];
            if ( $number =~ m/^\d+$/ ) {
                $PERFDATA{$k} += $number;
            }
            next;
        }
        if ( $stats_line =~ m/$STATS_ENDS_RE/i ) {
            my $k = $STATS_ENDMAP{$1};
            if ( not defined $k ) {
                next;
            }
            my @bits = split /\s+/, $stats_line;
            my $number = $bits[0];
            if ( $number =~ m/^\d+$/ ) {
                $PERFDATA{$k} += $number;
            }
            next;
        }
    }
    if ( not $found_stats_start ) {
        $exit_message .= q{Failed to find statistics block in --stats-path };
        $exit_message .= $OPTIONS{'stats-path'};
        $exit_message .= q{.};
    }
}

my $found_status_data = 0;

# Run rndc status to slurp the bind9 status info
for my $status_line ( slurp_command(@RNDC_STATUS) ) {
    if ( $status_line =~ m/CPUs found: (\d+)/i ) {
        $PERFDATA{'cpus'} = $1;
    }
    elsif ( $status_line =~ m/worker threads: (\d+)/i ) {
        $PERFDATA{'workers'} = $1;
    }
    elsif ( $status_line =~ m/number of zones: (\d+)/i ) {
        $PERFDATA{'zones'} = $1;
    }
    elsif ( $status_line =~ m/debug level: (\d+)/i ) {
        $PERFDATA{'debug'} = $1;
    }
    elsif ( $status_line =~ m/xfers running: (\d+)/i ) {
        $PERFDATA{'xfers_running'} = $1;
    }
    elsif ( $status_line =~ m/xfers deferred: (\d+)/i ) {
        $PERFDATA{'xfers_deferred'} = $1;
    }
    elsif ( $status_line =~ m/soa queries in progress: (\d+)/i ) {
        $PERFDATA{'soa_running'} = $1;
    }
    elsif ( $status_line =~ m/recursive clients: (\d+)\/(\d+)\/(\d+)/i ) {
        $PERFDATA{'udp_running'}    = $1;
        $PERFDATA{'udp_soft_limit'} = $2;
        $PERFDATA{'udp_hard_limit'} = $3;
    }
    elsif ( $status_line =~ m/tcp clients: (\d+)\/(\d+)/i ) {
        $PERFDATA{'tcp_running'}    = $1;
        $PERFDATA{'tcp_hard_limit'} = $2;
    }
    else {

        # Skip if we didn't match anything
        next;
    }

    # If we did match something, say so
    $found_status_data = 1;
}

if ( not $found_status_data ) {
    $exit_message .= q{Failed to find status data in: '};
    $exit_message .= $OPTIONS{'rndc-path'};
    if ( length $OPTIONS{'rndc-args'} ) {
        $exit_message .= q{ };
        $exit_message .= $OPTIONS{'rndc-args'};
    }
    $exit_message .= q{ status'.};
}

my $exit_code = $NAGIOS_EXIT_OK;
if ( length $exit_message > 0 ) {
    $exit_code = $NAGIOS_EXIT_WARNING;
    $exit_message =~ s/[\r\n]/ /g;
}
else {
    $exit_message = 'OK';
}

print qq{BIND9 $exit_message ;};
if ( defined $BIND_PID ) {
    print qq{ PID $BIND_PID ;};
}
print q{ Running:};
print qq{ $PERFDATA{'udp_running'}/$PERFDATA{'udp_soft_limit'}};
print qq{/$PERFDATA{'udp_hard_limit'} UDP,};
print qq{ $PERFDATA{'tcp_running'}/$PERFDATA{'tcp_hard_limit'} TCP,};
print qq{ $PERFDATA{'xfers_running'} xfers;};
print qq{ $PERFDATA{'xfers_deferred'} deferred xfers;};
print qq{ $PERFDATA{'zones'} zones ;};
print qq{ |};

# Generate perfdata in PNP4Nagios format
# http://docs.pnp4nagios.org/pnp-0.6/perfdata_format

# Stats keys are all 'Counter' data
for my $k (@STATS_KEYS) {
    print q{ } , $k , q{=} , $PERFDATA{$k} , q{c};
}
my %EXTRAS = (
    q{debug} => ';1',    # Warning if in debug
);
if ( $PERFDATA{'udp_soft_limit'} + $PERFDATA{'udp_hard_limit'} > 0 ) {

    # Running at soft limit is warning, running at hard limit is critical

    $EXTRAS{'udp_running'} = q{;}
        . ( $PERFDATA{'udp_soft_limit'} || q{} ) . q{;}
        . ( $PERFDATA{'udp_hard_limit'} || q{} );
}
if ( $PERFDATA{'tcp_hard_limit'} ) {

    # Running at hard limit is critical
    $EXTRAS{'tcp_running'} = q{;;} . $PERFDATA{'tcp_hard_limit'};
}

for my $k (@STATUS_KEYS) {
    print q{ } , $k , q{=} , $PERFDATA{$k};
    if ( defined $EXTRAS{$k} ) {
        print $EXTRAS{$k};
    }
}
exit $exit_code;
