#!/usr/bin/env sh
# Run the production image with the local PGN archive mounted into the container.
#
# Usage:
#   ./prodman-run.sh
#
# The image runs as the "nobody" user (UID/GID 65534) and uses /app as its
# working directory. The application writes completed games to /app/var/games.
set -eu

# Always resolve the archive relative to this script, not the caller's cwd.
cd "$(dirname "$0")"

# Make sure the bind-mount source exists before Podman creates the container.
mkdir -p var/games

# Recreate the container so the mount and environment are applied cleanly.
podman rm -f chess_ex 2>/dev/null || true

# --userns=keep-id:uid=65534,gid=65534 maps the rootless Podman user to the
# container's "nobody" user, so it can write into the bind-mounted directory.
# :Z relabels the directory for SELinux; harmless where SELinux is disabled.
podman run -d --name chess_ex -p 4000:4000 \
  --userns=keep-id:uid=65534,gid=65534 \
  -e CHESS_EX_UI_GAMES_DIR=/app/var/games \
  -v "$PWD/var/games:/app/var/games:Z" \
  localhost/chess_ex
