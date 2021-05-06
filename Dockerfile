FROM debian:stable
ARG NORDVPN_VERSION=3.9.2-1
RUN apt update && \
  apt install -y curl && \
  curl https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/nordvpn-release_1.0.0_all.deb -o /tmp/nordrepo.deb && \
  apt install -y /tmp/nordrepo.deb && \
  apt update && \
  apt install -y nordvpn=$NORDVPN_VERSION && \
  apt remove -y nordvpn-release && \
  rm -rf /tmp/* /var/lib/apt/lists/*

COPY ./scripts/nordvpn.sh /usr/bin
RUN chmod +x /usr/bin/nordvpn.sh
ENTRYPOINT ["/usr/bin/nordvpn.sh"]

# interval: wait 5 minutes before starting to check, and 5 minutes after each previous check completes
# timeout: wait 20 seconds for a check to complete, before considering it failed
# start-period: wait 1 minute for the container to bootstrap before we count failures toward max retries
HEALTHCHECK --interval=5m --timeout=20s --start-period=1m \
	CMD if test $( curl -m 10 -s https://api.nordvpn.com/vpn/check/full | jq -r '.["status"]' ) = "Protected" ; then exit 0; else nordvpn disconnect; nordvpn connect ${CONNECT} ; exit $?; fi