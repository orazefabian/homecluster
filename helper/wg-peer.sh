#!/usr/bin/env bash
#
# Manage WireGuard peers of the in-cluster server (apps/wireguard).
#
# Peers are declared in the PEERS env var of apps/wireguard/manifests/deployment.yaml.
#   Add:    append a name (letters/digits only) to PEERS, merge, wait for the pod,
#           then `wg-peer.sh show <name>` and scan the QR code in the WireGuard app.
#   Remove: delete the name from PEERS and merge — the peer can no longer connect.
#           Then `wg-peer.sh purge <name>` so its keys are gone for good (otherwise
#           re-adding the same name later brings back the same keys and IP).
#
# Usage:
#   wg-peer.sh list            peers on disk: IP, active?, last handshake
#   wg-peer.sh show  <name>    QR code (scan with the phone app)
#   wg-peer.sh conf  <name>    client config as text (desktop import); contains the private key
#   wg-peer.sh purge <name>    delete a removed peer's keys and configs
#   wg-peer.sh regen           re-render the server config (after editing server-template.yaml)
#
# Needs kubectl with access to the halo namespace.

set -euo pipefail

NS=halo
DEPLOY=deploy/wireguard
CTR=wireguard

die() { echo "error: $*" >&2; exit 1; }
wx() { kubectl -n "$NS" exec "$DEPLOY" -c "$CTR" -- "$@"; }

valid_name() {
  [[ "${1:-}" =~ ^[[:alnum:]]+$ ]] || die "peer name must be letters/digits only, got '${1:-}'"
}

declared_peers() {
  kubectl -n "$NS" get "$DEPLOY" -o jsonpath='{.spec.template.spec.containers[?(@.name=="wireguard")].env[?(@.name=="PEERS")].value}' | tr ',' '\n'
}

require_peer_dir() {
  wx test -f "/config/peer_$1/peer_$1.conf" || die "no peer '$1' on the server (see: $0 list)"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  list)
    declared=$(declared_peers)
    wx sh -c '
      hs=$(wg show wg0 latest-handshakes 2>/dev/null || true)
      now=$(date +%s)
      printf "%-16s %-14s %-8s %s\n" PEER IP ACTIVE "LAST HANDSHAKE"
      for d in /config/peer_*; do
        [ -d "$d" ] || continue
        n=${d##*/peer_}
        ip=$(grep -m1 "^Address" "$d/peer_$n.conf" 2>/dev/null | awk "{print \$NF}")
        pub=$(cat "$d/publickey-peer_$n" 2>/dev/null || true)
        if grep -q "^# peer_$n\$" /config/wg_confs/wg0.conf 2>/dev/null; then act=yes; else act=no; fi
        t=$(echo "$hs" | awk -v k="$pub" "\$1==k {print \$2}")
        if [ -z "$t" ] || [ "$t" = 0 ]; then last=never; else last="$(( (now - t) / 60 )) min ago"; fi
        printf "%-16s %-14s %-8s %s\n" "$n" "${ip:--}" "$act" "$last"
      done'
    echo
    echo "declared in PEERS: $(echo "$declared" | paste -sd, -)"
    ;;
  show)
    valid_name "${1:-}"; require_peer_dir "$1"
    wx sh -c "qrencode -t ansiutf8 < /config/peer_$1/peer_$1.conf"
    ;;
  conf)
    valid_name "${1:-}"; require_peer_dir "$1"
    echo "# contains the peer's private key — import it, don't paste it anywhere" >&2
    wx cat "/config/peer_$1/peer_$1.conf"
    ;;
  purge)
    valid_name "${1:-}"
    if declared_peers | grep -Fxq -- "$1"; then
      die "'$1' is still in PEERS — remove it from deployment.yaml and merge first"
    fi
    if wx grep -q "^# peer_$1\$" /config/wg_confs/wg0.conf; then
      die "'$1' is still in the running server config — wait for the pod to restart after the merge"
    fi
    wx test -d "/config/peer_$1" || die "no keys for '$1' on the server"
    read -r -p "Delete keys and configs of peer '$1' permanently? [y/N] " a
    [ "$a" = y ] || [ "$a" = Y ] || { echo "aborted"; exit 1; }
    wx rm -rf "/config/peer_$1"
    echo "deleted /config/peer_$1"
    ;;
  regen)
    echo "Re-rendering wg_confs/wg0.conf from the template; this restarts the VPN (all peers reconnect)."
    read -r -p "Continue? [y/N] " a
    [ "$a" = y ] || [ "$a" = Y ] || { echo "aborted"; exit 1; }
    wx rm -f /config/wg_confs/wg0.conf
    kubectl -n "$NS" rollout restart "$DEPLOY"
    kubectl -n "$NS" rollout status "$DEPLOY" --timeout=180s
    ;;
  *)
    sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
