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
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

SERVICE="ros-noetic"
CONTAINER="ros-noetic-gazebo"

# Export host UID/GID so docker-compose build args pick them up.
# Note: bash's $UID is readonly, so we use HOST_UID / HOST_GID instead.
export HOST_UID="$(id -u)"
export HOST_GID="$(id -g)"

# Create host-side cache dirs so the compose volume mounts don't auto-create them as root
mkdir -p "${SCRIPT_DIR}/.cache/gazebo" \
         "${SCRIPT_DIR}/.cache/ros" \
         "${SCRIPT_DIR}/catkin_ws/src"
touch    "${SCRIPT_DIR}/.cache/bash_history"

# ---------- X11 / xauth setup (needed for RViz + Gazebo GUIs) ---------------
setup_xauth() {
    local XAUTH=/tmp/.docker.xauth
    touch "${XAUTH}"
    # Merge host's xauth cookie with a wildcard hostname so the container can use it
    xauth nlist "${DISPLAY:-:0}" 2>/dev/null \
        | sed -e 's/^..../ffff/' \
        | xauth -f "${XAUTH}" nmerge - 2>/dev/null || true
    chmod 644 "${XAUTH}"

    # Allow local docker connections to the X server (scoped to local user)
    xhost +local:docker >/dev/null 2>&1 || \
        echo "warning: xhost not available — GUIs may not display"
}

case "${1:-help}" in
    build)
        setup_xauth
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
        # If container isn't running, start it first
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
        docker compose down || true
        docker compose build --no-cache
        setup_xauth
        docker compose up -d
        ;;
    logs)
        docker compose logs -f
        ;;
    status)
        docker compose ps
        ;;
    help|*)
        sed -n '2,15p' "$0"
        ;;
esac