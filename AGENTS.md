# VPN SwiftBar menu

A macOS menubar VPN switcher built on [SwiftBar](https://swiftbar.app). Pure Bash, no build step,
no dependencies to install beyond the VPN tools themselves. One click connects a VPN listed in `vpn.conf`.
Two engines:

| Engine    | What it does                                                         |
|-----------|----------------------------------------------------------------------|
| `openvpn` | Runs `sudo -n openvpn --config <.ovpn>` (split/full tunnel = different wrapper profiles) |
| `f5`      | Opens the official `F5 VPN.app` and the F5 portal URL in the browser |

Personal/machine-specific details (usernames, hostnames, absolute paths, the user's actual VPNs) are
deliberately **not** in this file. See [Local instructions](#local-instructions).

## How it runs

```
SwiftBar ──runs every 5s / on open──▶ plugins/<name>.5s.sh   (tiny regular-file shim, lives OUTSIDE this repo)
                                         └─exec─▶ openconnect.sh         (renders the menu)
                                                     └─calls─▶ vpn-manager.sh   (all logic; also a CLI)
                                                                  └─sources─▶ vpn.conf   (the user's VPN list)
```

- `openconnect.sh` prints [xbar/SwiftBar format](https://github.com/swiftbar/SwiftBar#plugin-api): a headline, then `---`, then
  one item per `vpn-manager.sh list` row whose `bash=… param1=connect param2=<id> terminal=false refresh=true`
  runs the manager directly. It holds no VPN logic and no profile ids.
- `swiftbar-openconnect-wrapper.sh` is the template for the plugin shim. The shim must be a **regular file,
  not a symlink** (SwiftBar ignores symlinks), and its filename suffix `5s` is the refresh interval, which is
  what lets the menu notice an asynchronous F5 login finishing.
- Both scripts derive `REPO_DIR` from their own path, so the repo can live anywhere; only the shim holds it.
- `vpn-manager.sh` is the only place that touches VPNs. CLI:
  `vpn-manager.sh {status|profile|list|connect ID|disconnect}` (no arg = `status`).
  `status` prints `connected`/`disconnected`; `profile` prints the active id or nothing;
  `list` prints `id<TAB>title<TAB>label` per configured VPN.

## Configuration (`vpn.conf`)

Gitignored; `vpn.conf.example` is the documented template. It is **sourced by bash** after the manager
defines `vpn()` and the defaults (`OPENVPN`, `F5_APP`), so it may override those. Each VPN is one line:
`vpn ID ENGINE "MENUBAR TITLE" "MENU LABEL" TARGET`. `vpn()` appends to the parallel indexed arrays
`IDS ENGINES TITLES LABELS TARGETS` (bash 3.2 has no associative arrays); `profile_index` looks an id up.
TARGET is a `.ovpn` path for `openvpn` (relative = relative to the repo) and a portal URL for `f5`.

## How `vpn-manager.sh` works

- **Connect** always calls `disconnect_current` first, then by engine:
  - `openvpn`: `start_openvpn` launches `sudo -n openvpn --config <target> --writepid … --log-append …`
    in the background, waits for the pid file, then `wait_for_openvpn` polls the log for
    `Data Channel:` plus a `utun` interface with an IPv4 (fails fast on `AUTH_FAILED`, `Options error`, etc.).
  - `f5`: `launch_f5` opens `F5 VPN.app` and the profile's portal URL in the default browser. The user
    completes login/MFA in the browser; the portal hands off to the client via the `f5-vpn://` handler.
    The script does **not** drive the login and returns immediately; "connected" is detected later by polling.
- **Disconnect**: OpenVPN via `sudo -n killall -TERM openvpn`; F5 via `osascript … quit`.
- **Active-profile detection** (`active_profile`) is polled every 5 s, so keep it cheap and side-effect-light.
  A profile counts as active only if its pid is alive **and** the command line matches its engine
  (`pid_matches_engine`) **and** `tunnel_ready` (any `utun*` with an IPv4 address; for F5 the client
  process must also be running). Stale state is cleaned as a side effect. If the state file is missing, it
  scans all profiles in config order and rewrites it (this is how an externally started F5 tunnel is adopted,
  by the first `f5` profile).
- **State** lives outside git in `~/Library/Application Support/OpenConnectMenuBar/`:
  `current-profile`, `<id>.pid`, `logs/<id>.log` (logs are truncated on each OpenVPN connect).
  The menu's "View VPN log" item opens the active profile's log.

## Profiles (`profiles/*.ovpn`)

Only `profiles/example-*.ovpn` is tracked; everything else in `profiles/` is the user's and gitignored.
Each wrapper is `config <path to the real .ovpn>` plus overrides. The real profile holds
certificate/key material and **must never be copied into this repo**.
- `example-split.ovpn`: ignores the server's `redirect-gateway`, ignores IPv6 DNS pushes, pins two public
  resolvers through the tunnel, `dns-updown force`.
- `example-full.ovpn`: `redirect-gateway def1`, ignores IPv6 DNS pushes, `dns-updown force`.

## Privileges (sudoers)

OpenVPN needs root. `sudoers.example` is the template for a NOPASSWD rule in `/etc/sudoers.d/`
(mode 440) allowing exactly `openvpn` and `killall -TERM openvpn`. **Any new `sudo -n <cmd>` in the
scripts needs a matching sudoers line**, otherwise it silently fails (`sudo -n` never prompts, and
most call sites end in `|| true`). Never edit `/etc/sudoers.d/` yourself; tell the user what to install.

## Repo map

| Path                              | Role                                                         |
|-----------------------------------|--------------------------------------------------------------|
| `vpn-manager.sh`                  | All VPN logic and the CLI                                    |
| `openconnect.sh`                  | SwiftBar menu renderer (xbar output)                         |
| `vpn.conf.example`                | Documented config template (`vpn.conf` itself is gitignored) |
| `swiftbar-openconnect-wrapper.sh` | Template of the plugin shim installed in SwiftBar's plugin dir |
| `profiles/example-*.ovpn`         | OpenVPN wrapper templates (see above)                        |
| `sudoers.example`                 | Template of the sudoers drop-in                              |
| `README.md`                       | Human-facing setup guide                                     |

## Commands

No build, no tests, no CI. Verify with:

```bash
bash -n vpn-manager.sh openconnect.sh                  # syntax check (always do this after an edit)
shellcheck vpn-manager.sh openconnect.sh               # if installed
./vpn-manager.sh status                                # read-only: connected / disconnected
./vpn-manager.sh profile                               # read-only: active profile id or empty
./vpn-manager.sh list                                  # read-only: configured VPNs
./openconnect.sh                                       # read-only: prints the menu SwiftBar would render
tail -n 50 "$HOME/Library/Application Support/OpenConnectMenuBar/logs/<id>.log"
```

`connect` and `disconnect` change the machine's network state; see Boundaries.

## Code style and gotchas

- Target **macOS `/bin/bash` 3.2**: no associative arrays, `mapfile`, `${var,,}`, or `&>>`.
  `[[ ]]`, `+=`, and `< <(…)` are fine. Expanding an empty array under `set -u` fails in 3.2: guard with
  `${#ARR[@]}` first. Keep scripts executable (`chmod +x`).
- Scripts use `set -u` but deliberately **not** `set -e`; failures are handled per call.
  Quote everything; the state dir path contains a space.
- Style: `snake_case` functions, `UPPER_CASE` constants at the top, `case` dispatch at the bottom,
  `printf '%s\n'` over `echo` for data.
- No profile id may be hard-coded in the scripts; everything comes from `vpn.conf`. **Adding an engine**
  means updating `pid_matches_engine`, `tunnel_ready`, `disconnect_current`, `connect_profile`,
  `profile_target` (if its target isn't a path), `vpn.conf.example`, `README.md`, and `sudoers.example`
  if it needs a new sudo command.
- `tunnel_has_ipv4` is true for **any** `utun` with an IPv4 (iCloud Private Relay or another VPN can fool
  it); pid + engine matching is what keeps detection honest. Don't loosen that.

## Boundaries

**Do freely:** read files, run the read-only commands above, `bash -n` / `shellcheck`, edit scripts in this repo.

**Ask first:**
- `vpn-manager.sh connect|disconnect`, or anything that starts/kills `openvpn` or quits F5
  (this drops the user's VPN, possibly mid-work, and opens a browser tab).
- Installing or changing anything in `/etc/sudoers.d/`, `/Applications`, or Homebrew.
- Committing, pushing, deleting files.

**Never:**
- Read, print, copy, or commit credential or key material: any `*-creds` file, the real `.ovpn`
  (private key inside), or anything under the state dir other than logs.
- Put usernames, hostnames, absolute home paths, or employer/client names into `AGENTS.md`, `README.md`,
  `vpn.conf.example`, or any other committed file. This repo is public; such details belong in `vpn.conf`,
  `profiles/` (non-example), or `AGENTS.local.md`.

## Local instructions

If `AGENTS.local.md` exists at the repo root, **read it before starting work**. It is gitignored and
holds this machine's and this user's specifics (accounts, hostnames, paths, personal preferences). Where it
conflicts with this file, it wins. Never copy its contents into committed files. If it is missing, the
setup is generic: ask the user for any environment detail you need rather than guessing.

## Keeping this file current

Update `AGENTS.md` in the same change whenever you add or rename an engine, script, config key, state file, or
sudo command, or change how detection or connection works. Outdated instructions are worse than none.
