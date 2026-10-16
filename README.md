# VPN SwiftBar menu

Switch your VPNs from the macOS menubar: one click to connect, one to disconnect, and the menu shows which tunnel is up. It is plain Bash on top of [SwiftBar](https://swiftbar.app), with no build step.

Two kinds of VPN are supported:

- **OpenVPN** (`openvpn` engine): any `.ovpn` profile, run with `sudo -n openvpn`. You can define
  several entries for the same server, for example a split tunnel and a full tunnel.
- **F5 BIG-IP SSL VPN** (`f5` engine): the menu opens the official `F5 VPN.app` and your portal URL in the
  browser. You log in there (password, MFA, whatever your portal asks), and the portal hands off to the F5
  client. The menu notices when the tunnel comes up.

## Setup

1. Install [SwiftBar](https://swiftbar.app), plus `brew install openvpn` and/or the F5 VPN client.
2. Copy `vpn.conf.example` to `vpn.conf` and list your VPNs. `vpn.conf` is gitignored.
3. For each OpenVPN entry, copy `profiles/example-split.ovpn` or `profiles/example-full.ovpn` and point its
   `config` line at the real profile your admin gave you. Keep the real profile **outside** this repo,
   because it usually holds your private key. Your own files in `profiles/` are gitignored.
4. OpenVPN needs root. Copy `sudoers.example`, fill in your user name, and install it with
   `sudo visudo -f /etc/sudoers.d/vpn-menubar`. It allows only `openvpn` and `killall -TERM openvpn`.
5. Copy `swiftbar-openconnect-wrapper.sh` into your SwiftBar plugin folder as `vpn.5s.sh` and edit the
   path inside it. It has to be a regular file, because SwiftBar ignores symlinks. The `5s` sets the refresh
   interval, which is how the menu picks up an F5 login finishing in the browser.

## Command line

```bash
./vpn-manager.sh status            # connected / disconnected
./vpn-manager.sh profile           # id of the active VPN, or nothing
./vpn-manager.sh list              # configured VPNs
./vpn-manager.sh connect ID
./vpn-manager.sh disconnect
```

Logs and state live in `~/Library/Application Support/OpenConnectMenuBar/`. Use "View VPN log" in the menu
to open the active one.

## Limits

- Only one VPN is up at a time. Connecting one disconnects the others.
- "Connected" means the process is alive and some `utun` interface has an IPv4 address. Another VPN or
  iCloud Private Relay can also create one; process matching keeps this mostly honest.
- An F5 tunnel started outside the menu is attributed to the first `f5` entry in `vpn.conf`.
