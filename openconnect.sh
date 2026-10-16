#!/bin/bash
# SwiftBar menu for the VPNs configured in vpn.conf and managed by vpn-manager.sh.
# <xbar.title>VPN Status</xbar.title>
# <xbar.version>v4.0</xbar.version>
# <xbar.author>ajeanney</xbar.author>
# <xbar.desc>One-click switcher between OpenVPN and F5 VPN profiles</xbar.desc>
# <swiftbar.refreshOnOpen>true</swiftbar.refreshOnOpen>

set -u

REPO_DIR=$(cd "$(dirname "$0")" && pwd)
MANAGER="$REPO_DIR/vpn-manager.sh"

active_profile=$("$MANAGER" profile 2>/dev/null || true)
headline='VPN'
items=''

while IFS=$'\t' read -r id title label; do
  [ "$id" = "$active_profile" ] && headline="$title 🔒"
  items+="$label | bash='$MANAGER' param1=connect param2=$id terminal=false refresh=true"$'\n'
done < <("$MANAGER" list 2>/dev/null)

[ -n "$items" ] || items="No VPNs configured: copy vpn.conf.example to vpn.conf | href=file://$REPO_DIR"$'\n'

LOG_FILE="$HOME/Library/Application Support/OpenConnectMenuBar/logs/${active_profile:-vpn-manager}.log"

echo "$headline"
echo '---'
printf '%s' "$items"
echo '---'
echo "Disconnect current VPN | bash='$MANAGER' param1=disconnect terminal=false refresh=true"
echo "View VPN log | href=file://$LOG_FILE"
