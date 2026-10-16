#!/bin/bash
# Copy (don't symlink: SwiftBar ignores symlinks) into your SwiftBar plugin folder as
# vpn.5s.sh, and set the path below to this repo. "5s" is the refresh interval.
exec "$HOME/path/to/this/repo/openconnect.sh" "$@"
