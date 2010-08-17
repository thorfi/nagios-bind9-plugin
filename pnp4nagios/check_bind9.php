<?php
# Copyright (C) 2010
# Version 1.0.0
# David Goh <david@goh.id.au> - http://goh.id.au/~david/
# GIT: http://github.com/thorfi/nagios-bind9-plugin
# Licensed as GPLv3 or later - http://www.gnu.org/licenses/gpl.html
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
#
# See http://pnp4nagios.org/
# for what this script is for
$opt[1] = "--vertical-label 'Queries/s' -l0 --title \"BIND Statistics for $hostname / $servicedesc\" ";

$def[1]  = "DEF:success=$RRDFILE[1]:$DS[1]:AVERAGE " ;
$def[1] .= "DEF:referral=$RRDFILE[1]:$DS[2]:AVERAGE " ;
$def[1] .= "DEF:nxrrset=$RRDFILE[1]:$DS[3]:AVERAGE " ;
$def[1] .= "DEF:nxdomain=$RRDFILE[1]:$DS[4]:AVERAGE " ;
$def[1] .= "DEF:recursion=$RRDFILE[1]:$DS[5]:AVERAGE " ;
$def[1] .= "DEF:failure=$RRDFILE[1]:$DS[6]:AVERAGE " ;
$def[1] .= "DEF:duplicate=$RRDFILE[1]:$DS[7]:AVERAGE " ;
$def[1] .= "DEF:dropped=$RRDFILE[1]:$DS[8]:AVERAGE " ;

$def[1] .=   "LINE:success#00ff00:\"Successful\" " ;
$def[1] .= "GPRINT:success:LAST:\"\tCur %5.1lf%sq/s \" " ;
$def[1] .= "GPRINT:success:AVERAGE:\"\tAvg %5.1lf%sq/s \" " ;
$def[1] .= "GPRINT:success:MAX:\"\tMax %5.1lf%sq/s \\n\" " ;

$def[1] .= "LINE:recursion#00ffff:\"Recursion \" " ;
$def[1] .= "GPRINT:recursion:LAST:\"\tCur %5.1lf%sq/s \" " ;
$def[1] .= "GPRINT:recursion:AVERAGE:\"\tAvg %5.1lf%sq/s \" " ;
$def[1] .= "GPRINT:recursion:MAX:\"\tMax %5.1lf%sq/s \\n\" " ;

$def[1] .=  "LINE:referral#0000ff:\"Referral  \" " ;
$def[1] .= "GPRINT:referral:LAST:\"\tCur %5.1lf%sq/s \" " ;
$def[1] .= "GPRINT:referral:AVERAGE:\"\tAvg %5.1lf%sq/s \" " ;
$def[1] .= "GPRINT:referral:MAX:\"\tMax %5.1lf%sq/s \\n\" " ;

$def[1] .=  "LINE:nxdomain#ff6f00:\"No Domain \" " ;
$def[1] .= "GPRINT:nxdomain:LAST:\"\tCur %5.1lf%sq/s \" " ;
$def[1] .= "GPRINT:nxdomain:AVERAGE:\"\tAvg %5.1lf%sq/s \" " ;
$def[1] .= "GPRINT:nxdomain:MAX:\"\tMax %5.1lf%sq/s \\n\" " ;

$def[1] .=   "LINE:nxrrset#ffff00:\"No Record \" " ;
$def[1] .= "GPRINT:nxrrset:LAST:\"\tCur %5.1lf%sq/s \" " ;
$def[1] .= "GPRINT:nxrrset:AVERAGE:\"\tAvg %5.1lf%sq/s \" " ;
$def[1] .= "GPRINT:nxrrset:MAX:\"\tMax %5.1lf%sq/s \\n\" " ;

$def[1] .=   "LINE:failure#ff0000:\"Failure   \" " ;
$def[1] .= "GPRINT:failure:LAST:\"\tCur %5.1lf%sq/s \" " ;
$def[1] .= "GPRINT:failure:AVERAGE:\"\tAvg %5.1lf%sq/s \" " ;
$def[1] .= "GPRINT:failure:MAX:\"\tMax %5.1lf%sq/s \\n\" " ;

$def[1] .= "LINE:duplicate#aa0000:\"Duplicate \" " ;
$def[1] .= "GPRINT:duplicate:LAST:\"\tCur %5.1lf%sq/s \" " ;
$def[1] .= "GPRINT:duplicate:AVERAGE:\"\tAvg %5.1lf%sq/s \" " ;
$def[1] .= "GPRINT:duplicate:MAX:\"\tMax %5.1lf%sq/s \\n\" " ;

$def[1] .=   "LINE:dropped#440000:\"Dropped   \" " ;
$def[1] .= "GPRINT:dropped:LAST:\"\tCur %5.1lf%sq/s \" " ;
$def[1] .= "GPRINT:dropped:AVERAGE:\"\tAvg %5.1lf%sq/s \" " ;
$def[1] .= "GPRINT:dropped:MAX:\"\tMax %5.1lf%sq/s \\n\" " ;

$opt[2] = "-l0 --title \"BIND Status for $hostname / $servicedesc\" ";

$def[2]  = "DEF:cpus=$RRDFILE[1]:$DS[9]:AVERAGE " ;
$def[2] .= "DEF:workers=$RRDFILE[1]:$DS[10]:AVERAGE " ;
$def[2] .= "DEF:zones=$RRDFILE[1]:$DS[11]:AVERAGE " ;
$def[2] .= "DEF:debug=$RRDFILE[1]:$DS[12]:AVERAGE " ;

$def[2] .=    "LINE:cpus#000088:\"CPUs   \" " ;
$def[2] .= "GPRINT:cpus:LAST:\"\tCur %5.0lf%s \" " ;
$def[2] .= "GPRINT:cpus:AVERAGE:\"\tAvg %5.0lf%s \" " ;
$def[2] .= "GPRINT:cpus:MAX:\"\tMax %5.0lf%s \\n\" " ;

$def[2] .= "LINE:workers#0000ff:\"Workers\" " ;
$def[2] .= "GPRINT:workers:LAST:\"\tCur %5.0lf%s \" " ;
$def[2] .= "GPRINT:workers:AVERAGE:\"\tAvg %5.0lf%s \" " ;
$def[2] .= "GPRINT:workers:MAX:\"\tMax %5.0lf%s \\n\" " ;

$def[2] .=   "LINE:zones#00ff00:\"Zones  \" " ;
$def[2] .= "GPRINT:zones:LAST:\"\tCur %5.0lf%s \" " ;
$def[2] .= "GPRINT:zones:AVERAGE:\"\tAvg %5.0lf%s \" " ;
$def[2] .= "GPRINT:zones:MAX:\"\tMax %5.0lf%s \\n\" " ;

$def[2] .=   "LINE:debug#ff0000:\"Debug  \" " ;
$def[2] .= "GPRINT:debug:LAST:\"\tCur %5.0lf \" " ;
$def[2] .= "GPRINT:debug:AVERAGE:\"\tAvg %5.0lf \" " ;
$def[2] .= "GPRINT:debug:MAX:\"\tMax %5.0lf \\n\" " ;

$opt[3] = "--vertical-label 'Connections' -l0 --title \"BIND Connections for $hostname / $servicedesc\" ";

$def[3]  = "DEF:xfers_running=$RRDFILE[1]:$DS[13]:AVERAGE " ;
$def[3] .= "DEF:xfers_deferred=$RRDFILE[1]:$DS[14]:AVERAGE " ;
$def[3] .= "DEF:soa_running=$RRDFILE[1]:$DS[15]:AVERAGE " ;
$def[3] .= "DEF:udp_running=$RRDFILE[1]:$DS[16]:AVERAGE " ;
$def[3] .= "DEF:tcp_running=$RRDFILE[1]:$DS[19]:AVERAGE " ;

$def[3] .=  "LINE:xfers_running#ff0000:\"Xfers Running \" " ;
$def[3] .= "GPRINT:xfers_running:LAST:\"\tCur %5.1lf%s \" " ;
$def[3] .= "GPRINT:xfers_running:AVERAGE:\"\tAvg %5.1lf%s \" " ;
$def[3] .= "GPRINT:xfers_running:MAX:\"\tMax %5.1lf%s \\n\" " ;

$def[3] .= "LINE:xfers_deferred#880000:\"Xfers Deferred\" " ;
$def[3] .= "GPRINT:xfers_deferred:LAST:\"\tCur %5.1lf%s \" " ;
$def[3] .= "GPRINT:xfers_deferred:AVERAGE:\"\tAvg %5.1lf%s \" " ;
$def[3] .= "GPRINT:xfers_deferred:MAX:\"\tMax %5.1lf%s \\n\" " ;

$def[3] .=   "LINE:soa_running#ffff00:\"SOA Running   \" " ;
$def[3] .= "GPRINT:soa_running:LAST:\"\tCur %5.1lf%s \" " ;
$def[3] .= "GPRINT:soa_running:AVERAGE:\"\tAvg %5.1lf%s \" " ;
$def[3] .= "GPRINT:soa_running:MAX:\"\tMax %5.1lf%s \\n\" " ;

$def[3] .=   "LINE:udp_running#00ff00:\"UDP Running   \" " ;
$def[3] .= "GPRINT:udp_running:LAST:\"\tCur %5.1lf%s \" " ;
$def[3] .= "GPRINT:udp_running:AVERAGE:\"\tAvg %5.1lf%s \" " ;
$def[3] .= "GPRINT:udp_running:MAX:\"\tMax %5.1lf%s \\n\" " ;

$def[3] .=   "LINE:tcp_running#0000ff:\"TCP Running   \" " ;
$def[3] .= "GPRINT:tcp_running:LAST:\"\tCur %5.1lf%s \" " ;
$def[3] .= "GPRINT:tcp_running:AVERAGE:\"\tAvg %5.1lf%s \" " ;
$def[3] .= "GPRINT:tcp_running:MAX:\"\tMax %5.1lf%s \\n\" " ;

$opt[4] = "--vertical-label 'Connections' -l0 --title \"BIND Limits for $hostname / $servicedesc\" ";

$def[4]  = "DEF:udp_soft_limit=$RRDFILE[1]:$DS[17]:AVERAGE " ;
$def[4] .= "DEF:udp_hard_limit=$RRDFILE[1]:$DS[18]:AVERAGE " ;
$def[4] .= "DEF:tcp_hard_limit=$RRDFILE[1]:$DS[20]:AVERAGE " ;

$def[4] .= "LINE:udp_soft_limit#446600:\"UDP Soft Limit\" " ;
$def[4] .= "GPRINT:udp_soft_limit:LAST:\"\tCur %5.0lf%s \" " ;
$def[4] .= "GPRINT:udp_soft_limit:AVERAGE:\"\tAvg %5.0lf%s \" " ;
$def[4] .= "GPRINT:udp_soft_limit:MAX:\"\tMax %5.0lf%s \\n\" " ;

$def[4] .= "LINE:udp_hard_limit#44aa00:\"UDP Hard Limit\" " ;
$def[4] .= "GPRINT:udp_hard_limit:LAST:\"\tCur %5.0lf%s \" " ;
$def[4] .= "GPRINT:udp_hard_limit:AVERAGE:\"\tAvg %5.0lf%s \" " ;
$def[4] .= "GPRINT:udp_hard_limit:MAX:\"\tMax %5.0lf%s \\n\" " ;

$def[4] .= "LINE:tcp_hard_limit#4400aa:\"TCP Hard Limit\" " ;
$def[4] .= "GPRINT:tcp_hard_limit:LAST:\"\tCur %5.0lf%s \" " ;
$def[4] .= "GPRINT:tcp_hard_limit:AVERAGE:\"\tAvg %5.0lf%s \" " ;
$def[4] .= "GPRINT:tcp_hard_limit:MAX:\"\tMax %5.0lf%s \\n\" " ;

?>
