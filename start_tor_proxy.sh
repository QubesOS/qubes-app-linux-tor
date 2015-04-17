#!/bin/bash
#
# The Qubes OS Project, http://www.qubes-os.org
#
# Copyright (C) 2012-2014 Abel Luck <abel@outcomedubious.im>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#

# run only if qubes-tor service enabled
[ -r /var/run/qubes-service/qubes-tor ] || exit 0

killall tor &> /dev/null

# Qubes R3
if which qubesdb-read > /dev/null; then
    QUBESDB=qubesdb
    PREFIX='/'

# Qubes R2
else
    QUBESDB=xenstore
    PREFIX=''
fi

# defaults torrc variables - overridable by user
QUBES_IP=$(${QUBESDB}-read ${PREFIX}qubes-ip)
TOR_TRANS_PORT=9040 # maximum circuit isolation
TOR_SOCKS_PORT=9050 # less circuit isolation
TOR_SOCKS_ISOLATED_PORT=9049 # maximum circuit isolation
TOR_CONTROL_PORT=0 # 0 = disabled
VIRTUAL_ADDR_NET=172.16.0.0/12
DATA_DIRECTORY=/rw/usrlocal/lib/qubes-tor
RUNDIR=/var/run/tor
TOR_USER=`id -u -n _tor 2>/dev/null || id -u -n toranon 2>/dev/null || id -u -n debian-tor 2>/dev/null || echo root`

VARS="QUBES_IP TOR_TRANS_PORT TOR_SOCKS_PORT TOR_SOCKS_ISOLATED_PORT TOR_CONTROL_PORT VIRTUAL_ADDR_NET DATA_DIRECTORY"

# command line arguments - not overrideable
DEFAULT_RC=/usr/lib/qubes-tor/torrc
DEFAULT_RC_TEMPLATE=/usr/lib/qubes-tor/torrc.tpl
USER_RC=/rw/config/qubes-tor/torrc
PID=$RUNDIR/qubes-tor.pid


# $1 = space delimited vars
# $2 = template file
function replace_vars()
{
    for var in $1; do
        expressions+=("-e s|$var|${!var}|g")
    done

    sed "${expressions[@]}" $2
}

function setup_firewall
{
    echo "0" > /proc/sys/net/ipv4/ip_forward
    /sbin/iptables -F
    /sbin/iptables -P INPUT DROP
    /sbin/iptables -P FORWARD DROP
    /sbin/iptables -P OUTPUT ACCEPT
    /sbin/iptables -A INPUT -i vif+ -p udp -m udp --dport 53 -j ACCEPT
    /sbin/iptables -A INPUT -i vif+ -p tcp -m tcp --dport $TOR_TRANS_PORT -j ACCEPT
    /sbin/iptables -A INPUT -i vif+ -p tcp -m tcp --dport $TOR_SOCKS_PORT -j ACCEPT
    /sbin/iptables -A INPUT -i vif+ -p tcp -m tcp --dport $TOR_SOCKS_ISOLATED_PORT -j ACCEPT
    if [ "$TOR_CONTROL_PORT" != "0" ]; then
        /sbin/iptables -A INPUT -i vif+ -p tcp -m tcp --dport $TOR_CONTROL_PORT -j ACCEPT
    fi
    /sbin/iptables -A INPUT -i vif+ -p udp -m udp -j DROP
    /sbin/iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
    /sbin/iptables -A INPUT -i lo -j ACCEPT
    /sbin/iptables -A INPUT -j REJECT --reject-with icmp-host-prohibited

    # prevent kernel bug transproxy leak
    # https://lists.torproject.org/pipermail/tor-talk/2014-March/032507.html
    #/sbin/iptables -A OUTPUT -m conntrack --ctstate INVALID -j LOG --log-prefix "Transproxy ctstate leak blocked: " --log-uid
    /sbin/iptables -A OUTPUT -m conntrack --ctstate INVALID -j DROP
    #/sbin/iptables -A OUTPUT -m state --state INVALID -j LOG --log-prefix "Transproxy state leak blocked: " --log-uid
    /sbin/iptables -A OUTPUT -m state --state INVALID -j DROP
    #/sbin/iptables -A OUTPUT ! -o lo ! -d 127.0.0.1 ! -s 127.0.0.1 -p tcp -m tcp --tcp-flags ACK,FIN ACK,FIN -j LOG --log-prefix "Transproxy leak blocked: " --log-uid
    #/sbin/iptables -A OUTPUT ! -o lo ! -d 127.0.0.1 ! -s 127.0.0.1 -p tcp -m tcp --tcp-flags ACK,RST ACK,RST -j LOG --log-prefix "Transproxy leak blocked: " --log-uid
    /sbin/iptables -A OUTPUT ! -o lo ! -d 127.0.0.1 ! -s 127.0.0.1 -p tcp -m tcp --tcp-flags ACK,FIN ACK,FIN -j DROP
    /sbin/iptables -A OUTPUT ! -o lo ! -d 127.0.0.1 ! -s 127.0.0.1 -p tcp -m tcp --tcp-flags ACK,RST ACK,RST -j DROP

    # nat rules
    /sbin/iptables -t nat -F
    /sbin/iptables -t nat -P PREROUTING ACCEPT
    /sbin/iptables -t nat -P INPUT ACCEPT
    /sbin/iptables -t nat -P OUTPUT ACCEPT
    /sbin/iptables -t nat -P POSTROUTING ACCEPT
    /sbin/iptables -t nat -A PREROUTING -i vif+ -p udp -m udp --dport 53 -j DNAT --to-destination $QUBES_IP:53
    /sbin/iptables -t nat -A PREROUTING -i vif+ -p tcp -m tcp --dport $TOR_SOCKS_ISOLATED_PORT -j DNAT --to-destination $QUBES_IP:$TOR_SOCKS_ISOLATED_PORT
    /sbin/iptables -t nat -A PREROUTING -i vif+ -p tcp -m tcp --dport $TOR_SOCKS_PORT -j DNAT --to-destination $QUBES_IP:$TOR_SOCKS_PORT
    /sbin/iptables -t nat -A PREROUTING -i vif+ -p tcp -j DNAT --to-destination $QUBES_IP:$TOR_TRANS_PORT

    # completely disable ipv6
    /sbin/ip6tables -P INPUT DROP
    /sbin/ip6tables -P OUTPUT DROP
    /sbin/ip6tables -P FORWARD DROP
    /sbin/ip6tables -F

    for iface in `ls /proc/sys/net/ipv6/conf/vif*/disable_ipv6 2> /dev/null`; do
        echo "1" > $iface
    done
}

# function to print error and setup firewall rules to prevent traffic leaks
function exit_error()
{
    echo "qubes-tor: $1" 1>&2
    setup_firewall
    exit 1
}

# double check we've got an ip address
if [ X$QUBES_IP == X ]; then
    QUBES_IP="127.0.0.1"
    exit_error "Error getting qubes ip"
fi


# make the data directory if it doesn't exist
if [ ! -d "$DATA_DIRECTORY" ]; then
    mkdir -p $DATA_DIRECTORY || exit_error "Error creating data directory"
fi
chown -R $TOR_USER:$TOR_USER $DATA_DIRECTORY

if [ ! -d "$RUNDIR" ]; then
    mkdir -p $RUNDIR || exit_error "Error creating run directory"
fi
chown -R $TOR_USER:$TOR_USER $RUNDIR
chmod 0755 $RUNDIR

# pass the -f option only when config file exists
if [ -r "$USER_RC" ]; then
    USER_RC_OPTION="-f $USER_RC"
fi

# update the default torrc file with current values
(replace_vars "$VARS" $DEFAULT_RC_TEMPLATE) > $DEFAULT_RC  || exit_error "Error writing default torrc: $DEFAULT_RC"

# verify config file is useable
/usr/bin/tor \
    --defaults-torrc $DEFAULT_RC \
    $USER_RC_OPTION --verify-config \
    --user $TOR_USER \
    || exit_error "Error in Tor configuration"

# start tor
/usr/bin/tor \
    --defaults-torrc $DEFAULT_RC \
    $USER_RC_OPTION \
    --user $TOR_USER \
    --RunAsDaemon 1 \
    --Log "notice syslog" \
    --PIDFile $PID \
    || exit_error "Error starting Tor!"

# if we get here tor is running
setup_firewall


