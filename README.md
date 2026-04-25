# ROS Noetic + Gazebo 11 Container (Ubuntu 22.04 host, Intel iGPU)

A robust, Ubuntu-feel dev container for ROS1 Noetic + Gazebo 11 simulation.
Includes MoveIt, the Navigation stack, teleop, and common sensor/rqt tooling.

## Prerequisites (install once on the host)

```bash
# Docker Engine
sudo apt update
sudo apt install -y docker.io docker-compose-v2 xauth
sudo usermod -aG docker $USER
# log out & back in after this, or run: newgrp docker
```

Verify Docker works without sudo: `docker ps` should print an empty table.

## Project layout

```
ros-noetic-gazebo/
├── Dockerfile           # Ubuntu 20.04 + ROS Noetic + Gazebo 11 + extras
├── docker-compose.yml   # Container definition (X11, Intel GPU, mounts)
├── run.sh               # Helper script — use this for everything
├── catkin_ws/           # Your workspace (bind-mounted, edit from host)
│   └── src/
└── .cache/              # Persistent bash history, gazebo models, ~/.ros
```

## First-time setup

```bash
chmod +x run.sh
./run.sh build          # ~10-15 min the first time
./run.sh up             # start the container
./run.sh shell          # drop into a bash shell inside
```

You should see the prompt change to `[ros-noetic] rosdev@ros-noetic:~$`.

## Quick sanity checks (inside the container)

```bash
# ROS is sourced automatically:
echo $ROS_DISTRO                # noetic
roscore &                       # starts fine, Ctrl+C to stop

# RViz GUI:
rviz

# Gazebo GUI with a demo world:
roslaunch gazebo_ros empty_world.launch

# Turtlebot3-style sanity (if you add a robot pkg later):
rosrun rviz rviz
```

If RViz/Gazebo windows don't appear, see the Troubleshooting section below.

## Daily workflow

```bash
./run.sh shell          # open a terminal inside the container
# ...do ROS stuff...
exit                    # leave the shell (container keeps running)

./run.sh shell          # open another one (as many as you want)

./run.sh stop           # stop when done for the day
./run.sh up             # start again tomorrow
```

To open multiple terminals into the same container, just run `./run.sh shell`
in each new host terminal.

## Building your catkin workspace

Your host `./catkin_ws/` is mounted at `/home/rosdev/catkin_ws/` inside.
Drop packages into `catkin_ws/src/` on the host, then inside the container:

```bash
cd ~/catkin_ws
catkin build            # or: catkin_make
source devel/setup.bash # .bashrc does this automatically next shell
```

## Adding packages later

Inside the container you have full `sudo` (no password) and normal `apt`:

```bash
sudo apt update
sudo apt install ros-noetic-<whatever-you-need>
```

To bake packages into the image permanently, add them to the Dockerfile and
run `./run.sh rebuild`.

## Graphics notes (Intel iGPU, no NVIDIA)

- The compose file mounts `/dev/dri` so Mesa can use your Intel GPU for
  hardware OpenGL. Gazebo runs at usable speeds for most worlds.
- If you see `libGL error` spam or a black Gazebo window, uncomment
  `LIBGL_ALWAYS_SOFTWARE=1` in `docker-compose.yml` to force the software
  renderer (slower but always works). Then `./run.sh down && ./run.sh up`.
- Verify hardware GL from inside the container:
  ```bash
  glxinfo | grep "OpenGL renderer"
  # Should say "Mesa Intel(R) ..." — NOT "llvmpipe"
  ```

## Troubleshooting

**"cannot open display" or no GUI windows**
Run on the host (not in the container):
```bash
xhost +local:docker
```
The `run.sh` script does this automatically, but it resets on reboot.

**Permissions errors on files in catkin_ws/**
The container user's UID is baked in at build time to match your host user.
If you've changed users or moved the project, do: `./run.sh rebuild`.

**Gazebo crashes or is extremely slow**
First run downloads models from the Gazebo model server — give it a minute.
If it persists, enable software rendering (see Graphics notes above).

**Container won't start: "port is already allocated"**
`network_mode: host` means ROS's port 11311 is shared with the host. Make
sure no other `roscore` is running on the host.

## Cleaning up

```bash
./run.sh down                          # remove the container
docker rmi ros-noetic-gazebo:latest    # remove the image (frees ~4 GB)
rm -rf .cache/                         # remove cached gazebo models etc.
```
# ros-gazebo-noetic-docker
