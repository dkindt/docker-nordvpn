#!/usr/bin/env bash

# [[ -n ${DEBUG:-} ]] && set -x
set -x

NAME="nordvpn"
DAEMON="/usr/sbin/${NAME}d"
DAEMON_LOG_FILE="/var/log/nordvpn/daemon.log"
SOCKET_DIR="/run/$NAME"
SOCKET_FILE="${SOCKET_DIR}/${NAME}d.sock"

DOCKER_IPV4_NET="$(ip -o addr show dev eth0 | awk '$3 == "inet" {print $4}')"
DOCKER_IPV6_NET="$(ip -o addr show dev eth0 | awk '$3 == "inet6" {print $4}')"

return_route() { # Add a route back to your network, so that return traffic works
	local network="$1" gw=$(ip route | awk '/default/ {print $3}')
	ip route | grep -q "$network" || ip route add to "$network" via "$gw" dev eth0
	iptables --append INPUT -s "$network" -j ACCEPT
	iptables --append FORWARD -d "$network" -j ACCEPT
	iptables --append FORWARD -s "$network" -j ACCEPT
	iptables --append OUTPUT -d "$network" -j ACCEPT
}

configure_ipv4_rules() {
  # start with a clean slate.
  iptables --flush
	iptables --delete-chain

  # block all inbound/outbound requests by default.
	iptables --policy INPUT DROP
	iptables --policy FORWARD DROP
	iptables --policy OUTPUT DROP

  # incoming request rules.
  local match_conntrack="--match conntrack --ctstate ESTABLISHED,RELATED"
	iptables --append INPUT ${match_conntrack} -j ACCEPT
	iptables --append INPUT -i lo -j ACCEPT
	iptables --append FORWARD ${match_conntrack} -j ACCEPT
	iptables --append FORWARD -i lo -j ACCEPT

  # outbound request rules.
	iptables --append OUTPUT ${match_conntrack} -j ACCEPT
	iptables --append OUTPUT -o lo -j ACCEPT

	iptables --append OUTPUT -o tap+ -j ACCEPT
	iptables --append OUTPUT -o tun+ -j ACCEPT
  iptables --append OUTPUT -o nordlynx -j ACCEPT

  iptables --table nat -A POSTROUTING -o tap+ -j MASQUERADE
	iptables --table nat -A POSTROUTING -o tun+ -j MASQUERADE
	iptables --table nat -A POSTROUTING -o nordlynx -j MASQUERADE

  iptables --append OUTPUT -p udp -m udp --dport 53    -j ACCEPT
  iptables --append OUTPUT -p udp -m udp --dport 51820 -j ACCEPT
  iptables --append OUTPUT -p tcp -m tcp --dport 1194  -j ACCEPT
  iptables --append OUTPUT -p udp -m udp --dport 1194  -j ACCEPT
  iptables --append OUTPUT -p tcp -m tcp --dport 443   -j ACCEPT

	if [[ -n ${DOCKER_NET} ]]; then
		iptables --append INPUT -s "${DOCKER_NET}" --jump ACCEPT
		iptables --append FORWARD -d "${DOCKER_NET}" --jump ACCEPT
		iptables --append FORWARD -s "${DOCKER_NET}" --jump ACCEPT
		iptables --append OUTPUT -d "${DOCKER_NET}" --jump ACCEPT
	fi

	if [[ -n ${NETWORK} ]]; then 
    for net in ${NETWORK//[;,]/ }; do
      return_route "${net}"
    done
  fi
}

create_tun_interface() {
  mkdir -p /dev/net
  [[ -c /dev/net/tun ]] || mknod -m 0666 c 10 200
}

start_nordvpn_daemon() {
  service nordvpn start
  while [ ! -S $SOCKET_FILE ]; do
    sleep 0.15
  done
}

graceful_stop() {
  nordvpn disconnect
  service nordvpn stop
  trap - SIGTERM SIGINT EXIT
  exit 0
}
trap graceful_stop SIGTERM SIGQUIT EXIT

start_nordvpn_daemon
create_tun_interface

nordvpn login -u "${USER}" -p "${PASS}"
# TODO: read nordvpn config/env_vars

nordvpn connect ${CONNECT} || exit 1
nordvpn status

tail -f --pid="$(pidof nordvpnd)" $DAEMON_LOG_FILE & wait $!