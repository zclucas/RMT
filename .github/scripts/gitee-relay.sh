#!/bin/bash
set -euo pipefail
umask 077
dir=$(mktemp -d)
trap 'rm -rf -- "$dir"' EXIT
printf '%s\n' "$RELAY_KEY" > "$dir/key"
unset RELAY_KEY
printf '%s\n' "$KNOWN_HOST" > "$dir/known_hosts"
host=${KNOWN_HOST%% *}
[[ $host =~ ^[0-9]+(\.[0-9]+){3}$ ]]
ssh -T -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile="$dir/known_hosts" -o ConnectTimeout=15 \
  -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -i "$dir/key" "rmt-release@$host"
