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
$opt[1] = "--vertical-label 'Time' -l0 --title \"Response Time for $hostname / $servicedesc\" ";

$def[1]  = "DEF:time=$RRDFILE[1]:$DS[1]:AVERAGE " ;

$def[1] .=   "LINE:time#ff00ff:\"Time\" " ;
$def[1] .= "GPRINT:time:LAST:\"\tCur %5.3lf$UNIT[1] \" " ;
$def[1] .= "GPRINT:time:AVERAGE:\"\tAvg %5.3lf$UNIT[1] \" " ;
$def[1] .= "GPRINT:time:MAX:\"\tMax %5.3lf$UNIT[1] \\n\" " ;

$opt[2] = "--vertical-label 'Packets' -l0 --title \"DNS Packets for $hostname / $servicedesc\" ";

$def[2]  = "DEF:udp_queries=$RRDFILE[1]:$DS[2]:AVERAGE " ;
$def[2] .= "DEF:udp_responses=$RRDFILE[1]:$DS[3]:AVERAGE " ;
$def[2] .= "DEF:tcp_queries=$RRDFILE[1]:$DS[4]:AVERAGE " ;
$def[2] .= "DEF:tcp_responses=$RRDFILE[1]:$DS[5]:AVERAGE " ;

$def[2] .=   "LINE:udp_queries#008800:\"UDP Queries  \" " ;
$def[2] .= "GPRINT:udp_queries:LAST:\"\tCur %5.0lf \" " ;
$def[2] .= "GPRINT:udp_queries:AVERAGE:\"\tAvg %5.0lf \" " ;
$def[2] .= "GPRINT:udp_queries:MAX:\"\tMax %5.0lf \\n\" " ;

$def[2] .= "LINE:udp_responses#00ff00:\"UDP Responses\" " ;
$def[2] .= "GPRINT:udp_responses:LAST:\"\tCur %5.0lf \" " ;
$def[2] .= "GPRINT:udp_responses:AVERAGE:\"\tAvg %5.0lf \" " ;
$def[2] .= "GPRINT:udp_responses:MAX:\"\tMax %5.0lf \\n\" " ;

$def[2] .=   "LINE:tcp_queries#000088:\"TCP Queries  \" " ;
$def[2] .= "GPRINT:tcp_queries:LAST:\"\tCur %5.0lf \" " ;
$def[2] .= "GPRINT:tcp_queries:AVERAGE:\"\tAvg %5.0lf \" " ;
$def[2] .= "GPRINT:tcp_queries:MAX:\"\tMax %5.0lf \\n\" " ;

$def[2] .= "LINE:tcp_responses#0000ff:\"TCP Responses\" " ;
$def[2] .= "GPRINT:tcp_responses:LAST:\"\tCur %5.0lf \" " ;
$def[2] .= "GPRINT:tcp_responses:AVERAGE:\"\tAvg %5.0lf \" " ;
$def[2] .= "GPRINT:tcp_responses:MAX:\"\tMax %5.0lf \\n\" " ;

$opt[3] = "--vertical-label 'Bytes' -l0 --title \"DNS Bytes for $hostname / $servicedesc\" ";

$def[3]  = "DEF:udp_sent=$RRDFILE[1]:$DS[6]:AVERAGE " ;
$def[3] .= "DEF:udp_recv=$RRDFILE[1]:$DS[7]:AVERAGE " ;
$def[3] .= "DEF:tcp_sent=$RRDFILE[1]:$DS[8]:AVERAGE " ;
$def[3] .= "DEF:tcp_recv=$RRDFILE[1]:$DS[9]:AVERAGE " ;

$def[3] .= "LINE:udp_sent#008800:\"UDP Sent\" " ;
$def[3] .= "GPRINT:udp_sent:LAST:\"\tCur %5.1lf%s$UNIT[6] \" " ;
$def[3] .= "GPRINT:udp_sent:AVERAGE:\"\tAvg %5.1lf%s$UNIT[6] \" " ;
$def[3] .= "GPRINT:udp_sent:MAX:\"\tMax %5.1lf%s$UNIT[6] \\n\" " ;

$def[3] .= "LINE:udp_recv#00ff00:\"UDP Recv\" " ;
$def[3] .= "GPRINT:udp_recv:LAST:\"\tCur %5.1lf%s$UNIT[7] \" " ;
$def[3] .= "GPRINT:udp_recv:AVERAGE:\"\tAvg %5.1lf%s$UNIT[7] \" " ;
$def[3] .= "GPRINT:udp_recv:MAX:\"\tMax %5.1lf%s$UNIT[7] \\n\" " ;

$def[3] .= "LINE:tcp_sent#000088:\"TCP Sent\" " ;
$def[3] .= "GPRINT:tcp_sent:LAST:\"\tCur %5.1lf%s$UNIT[8] \" " ;
$def[3] .= "GPRINT:tcp_sent:AVERAGE:\"\tAvg %5.1lf%s$UNIT[8] \" " ;
$def[3] .= "GPRINT:tcp_sent:MAX:\"\tMax %5.1lf%s$UNIT[8] \\n\" " ;

$def[3] .= "LINE:tcp_recv#0000ff:\"TCP Recv\" " ;
$def[3] .= "GPRINT:tcp_recv:LAST:\"\tCur %5.1lf%s$UNIT[9] \" " ;
$def[3] .= "GPRINT:tcp_recv:AVERAGE:\"\tAvg %5.1lf%s$UNIT[9] \" " ;
$def[3] .= "GPRINT:tcp_recv:MAX:\"\tMax %5.1lf%s$UNIT[9] \\n\" " ;


?>
