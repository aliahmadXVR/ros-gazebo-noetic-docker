#!/usr/bin/env bash
# ============================================================================
# run.sh — convenience wrapper for the ROS Noetic + Gazebo container
# Usage:
#   ./run.sh build      # build the image (first time or after Dockerfile edits)
#   ./run.sh up         # start the container in the background
#   ./run.sh shell      # open a new bash shell inside the running container
#   ./run.sh stop       # stop the container
#   ./run.sh down       # stop + remove the container (image kept)
#   ./run.sh rebuild    # down + build --no-cache + up
#   ./run.sh logs       # tail container logs
#   ./run.sh status     # is it running?
#
# DO NOT run this script with sudo. Add your user to the `docker` group instead:
#   sudo usermod -aG docker $USER && newgrp docker
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

SERVICE="ros-noetic"
CONTAINER="ros-noetic-gazebo"
XAUTH=/tmp/.docker.xauth

# ---------- Refuse to run under sudo ----------------------------------------
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "ERROR: do not run this script with sudo or as root." >&2
    echo "" >&2
    echo "Docker should be runnable by your normal user. To enable that:" >&2
    echo "  sudo usermod -aG docker \$USER" >&2
    echo "  newgrp docker     # or log out and back in" >&2
    echo "" >&2
    echo "Then re-run:  ./run.sh ${1:-build}" >&2
    exit 1
fi

# Export host UID/GID so docker-compose build args pick them up.
export HOST_UID="$(id -u)"
export HOST_GID="$(id -g)"

if [ "${HOST_UID}" -eq 0 ] || [ "${HOST_GID}" -eq 0 ]; then
    echo "ERROR: HOST_UID or HOST_GID is 0 (root). Refusing to build." >&2
    echo "Run this script as your normal user, not root." >&2
    exit 1
fi

# Create host-side cache dirs so the compose volume mounts don't auto-create
# them as root.
mkdir -p "${SCRIPT_DIR}/.cache/gazebo" \
         "${SCRIPT_DIR}/.cache/ros" \
         "${SCRIPT_DIR}/catkin_ws/src"
touch    "${SCRIPT_DIR}/.cache/bash_history"

# ---------- X11 / xauth setup (needed for RViz + Gazebo GUIs) ---------------
# This must run BEFORE any `docker compose` command. Otherwise the compose
# volume mount at /tmp/.docker.xauth auto-creates the path as a directory.
#
# Common ways this gets broken:
#  1. The path exists as a directory (created by a stray `docker compose up`
#     before xauth was set up).
#  2. The path exists as a root-owned file (legacy from an old `sudo` run).
# Both cases require root to clean up. We auto-recover when we can.
setup_xauth() {
    # Case 1: it's a directory (docker auto-created)
    if [ -d "${XAUTH}" ]; then
        echo "Note: ${XAUTH} exists as a directory — fixing automatically..."
        if ! rm -rf "${XAUTH}" 2>/dev/null; then
            echo "ERROR: cannot remove ${XAUTH} — needs sudo." >&2
            echo "Run:  sudo rm -rf ${XAUTH}" >&2
            echo "Then re-run this script." >&2
            exit 1
        fi
    fi

    # Case 2: file exists but isn't writable by us (root-owned legacy)
    if [ -e "${XAUTH}" ] && [ ! -w "${XAUTH}" ]; then
        echo "Note: ${XAUTH} is not writable — fixing automatically..."
        if ! rm -f "${XAUTH}" 2>/dev/null; then
            echo "ERROR: cannot remove ${XAUTH} — needs sudo." >&2
            echo "Run:  sudo rm -f ${XAUTH}" >&2
            echo "Then re-run this script." >&2
            exit 1
        fi
    fi

    # At this point the path is either gone or a writable file we own.
    [ -e "${XAUTH}" ] || touch "${XAUTH}"

    # Merge host's xauth cookie with a wildcard hostname so the container
    # can use it regardless of its hostname.
    xauth nlist "${DISPLAY:-:0}" 2>/dev/null \
        | sed -e 's/^..../ffff/' \
        | xauth -f "${XAUTH}" nmerge - 2>/dev/null || true
    chmod 644 "${XAUTH}"

    # Allow local docker connections to the X server (scoped to local user).
    xhost +local:docker >/dev/null 2>&1 || \
        echo "warning: xhost not available — GUIs may not display"
}

case "${1:-help}" in
    build)
        setup_xauth
        echo "Building with HOST_UID=${HOST_UID} HOST_GID=${HOST_GID}"
        docker compose build
        ;;
    up)
        setup_xauth
        docker compose up -d
        echo ""
        echo "Container is up. Open a shell with:  ./run.sh shell"
        ;;
    shell|exec)
        setup_xauth
        if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
            echo "Container not running — starting it..."
            docker compose up -d
            sleep 1
        fi
        docker exec -it "${CONTAINER}" bash
        ;;
    stop)
        docker compose stop
        ;;
    down)
        docker compose down
        ;;
    rebuild)
        setup_xauth
        docker compose down || true
        docker compose build --no-cache
        docker compose up -d
        ;;
    logs)
        docker compose logs -f
        ;;
    status)
        docker compose ps
        ;;
    help|*)
        sed -n '2,18p' "$0"
        ;;
esac