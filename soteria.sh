#!/bin/sh

[ "`id -u`" = "0" ] && {
  echo "Do not run this script as a root user!"
  exit 1
}

[ -f /etc/soteria.conf ] && . /etc/soteria.conf

[ -n "$DNS_PARTS" ] || DNS_PARTS="hsr hsn jur jun rtl"
[ -n "$DNSMASQ_HOSTS" ] || DNSMASQ_HOSTS=/usr/share/soteria/hosts

TINYSRV_ARGS=/run/tinysrv/tinysrv.args
DEV=soteria
DNS_HOSTS=/tmp/soteria
PIDOF=`which pidof`
SUDO=`which sudo`

get_pid() {
  local _pid
  _pid=
  [ -n "$2" ] && [ -f "$2" ] && kill -0 `cat "$2"` 2>/dev/null && _pid=`cat "$2"`
  [ -z "$_pid" ] && [ -n "$PIDOF" ] && _pid=`$PIDOF "$1"`
  echo "$_pid"
}

hup() {
  [ -n "$1" ] || return 0
  ${SUDO:+$SUDO -u dnsmasq} /bin/kill -HUP "$1"
}

dnsmasq_pid() {
  get_pid dnsmasq "$DNSMASQ_PIDFILE"
}

tinysrv_pid() {
  get_pid tinysrv "$TINYSRV_PIDFILE"
}

remove_file() {
  [ -n "$1" ] && [ -f "$1" ] && rm -f "$1"
}

is_running() {
  [ -n "$1" ] && return 0
  return 1
}

append_hosts() {
  [ -n "$1" ] && [ -n "$2" ] || return 0
  local _url="${SRC_LIST%/}/$1"
  echo "Downloading from URL: $_url ... and appending domains to IP: $2"
  wget --no-check-certificate -q -O - "$_url" | sed "s/^/$2\t/" >>$DNS_HOSTS
}

update_hosts() {
  [ -n "$DNS_HOSTS" ] || return 1
  >$DNS_HOSTS
  chgrp soteria $DNS_HOSTS
  chmod 640 $DNS_HOSTS
  [ -L "$DNSMASQ_HOSTS" ] || {
    remove_file "$DNSMASQ_HOSTS"
    ln -s "$DNS_HOSTS" "$DNSMASQ_HOSTS"
  }
  [ -n "$HSN_IP" ] && {
    for _i in ads.txt analytics.txt; do
      append_hosts "$_i" "$HSN_IP"
    done
  }
  [ -n "$HSR_IP" ] && {
    for _i in affiliate.txt enrichments.txt fake.txt widgets.txt; do
      append_hosts "$_i" "$HSR_IP"
    done
  }
}

refresh_hosts() {
  update_hosts
  PID=`dnsmasq_pid`
  is_running "$PID" && hup "$PID"
}

start_tinysrv() {
  [ -n "$TINYSRV_PIDFILE" ] || return 1

  PID=`tinysrv_pid`
  is_running "$PID" || remove_file "$TINYSRV_PIDFILE"

  [ -n "$WWW_DIR" ] && {
    [ -d "$WWW_DIR" ] || mkdir -p "$WWW_DIR"
  }
  [ -n "$CRT_DIR" ] && {
    [ -d "$CRT_DIR" ] || mkdir -p "$CRT_DIR"
  }

  ADDR=`ip address show`
  for _dns_part in $DNS_PARTS; do
    eval IP=\$`echo "$_dns_part" | tr "[a-z]" "[A-Z]"`_IP
    [ -n "$IP" ] || continue
    echo $ADDR | grep -q "inet $IP" || unset `echo "$_dns_part" | tr "[a-z]" "[A-Z]"`_IP
  done

  echo "ARGS=-u tinysrv -P \"$TINYSRV_PIDFILE\"\
${HSR_IP:+ -k 443 \"$HSR_IP\" -p 80 \"$HSR_IP\"}\
${HSN_IP:+ -k 443 -R \"$HSN_IP\" -p 80 -R \"$HSN_IP\"}\
${JUR_IP:+ -p 80 -c \"$JUR_IP\"}\
${JUN_IP:+ -p 80 -c -R \"$JUN_IP\"}\
${RTL_IP:+${WWW_DIR:+ -p 80 -S \"$WWW_DIR\" \"$RTL_IP\"${CRT_DIR:+ -p 443 -S \"$WWW_DIR\" -C \"$CRT_DIR\" \"$RTL_IP\"}}}" >"$TINYSRV_ARGS"
}

populate_dns_parts() {
  ip link show "$DEV" >/dev/null 2>&1 || return 1
  _ips=`ip address show dev "$DEV" | awk '/inet / {split($2, a, /\//); print a[1]}' | tr "\n" " "`
  for _dns_part in $DNS_PARTS; do
    _ip="${_ips%% *}"
    _ips="${_ips#* }"
    eval `echo "$_dns_part" | tr "[a-z]" "[A-Z]"`_IP="$_ip"
  done
  return 0
}

case "$1" in

dnsmasq)
  populate_dns_parts
  refresh_hosts
  ;;

tinysrv)
  populate_dns_parts
  start_tinysrv
;;

*)
  echo "Unknown command"
  ;;

esac
