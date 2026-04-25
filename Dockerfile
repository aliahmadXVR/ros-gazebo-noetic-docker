# ============================================================================
# ROS Noetic + Gazebo 11 development container
# Base: Ubuntu 20.04 (Focal) — the official pairing for ROS Noetic
# Target: Intel integrated GPU host, Ubuntu 22.04, no NVIDIA
# ============================================================================
FROM ubuntu:20.04

ARG USERNAME=rosdev
ARG USER_UID=1000
ARG USER_GID=1000
ARG ROS_DISTRO=noetic

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    ROS_DISTRO=${ROS_DISTRO}

RUN apt-get update && apt-get install -y --no-install-recommends \
        locales tzdata ca-certificates gnupg2 lsb-release curl wget \
        sudo software-properties-common apt-utils dialog && \
    locale-gen en_US.UTF-8 && \
    update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 && \
    rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake git git-lfs \
        vim nano tmux htop tree less file unzip zip \
        net-tools iputils-ping iproute2 openssh-client \
        python3 python3-pip python3-dev python3-venv python3-setuptools \
        x11-apps mesa-utils \
        bash-completion man-db && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.asc \
        -o /etc/apt/keyrings/ros-archive-keyring.asc && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/ros-archive-keyring.asc] http://packages.ros.org/ros/ubuntu focal main" \
        > /etc/apt/sources.list.d/ros1.list && \
    apt-get update

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3-rosdep \
        python3-rosinstall \
        python3-rosinstall-generator \
        python3-wstool \
        python3-argcomplete \
        python3-catkin-tools \
        python3-osrf-pycommon && \
    rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing \
        ros-noetic-desktop-full \
        ros-noetic-gazebo-ros-pkgs \
        ros-noetic-gazebo-ros-control \
        ros-noetic-gazebo-plugins \
    && dpkg --configure -a \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
        ros-noetic-moveit \
        ros-noetic-moveit-visual-tools \
        ros-noetic-moveit-resources \
        ros-noetic-moveit-servo \
        ros-noetic-navigation \
        ros-noetic-move-base \
        ros-noetic-amcl \
        ros-noetic-gmapping \
        ros-noetic-map-server \
        ros-noetic-slam-toolbox \
        ros-noetic-robot-localization \
        ros-noetic-teleop-twist-keyboard \
        ros-noetic-teleop-twist-joy \
        ros-noetic-joy \
        ros-noetic-joint-state-publisher \
        ros-noetic-joint-state-publisher-gui \
        ros-noetic-robot-state-publisher \
        ros-noetic-xacro \
        ros-noetic-rqt \
        ros-noetic-rqt-common-plugins \
        ros-noetic-rqt-robot-plugins \
        ros-noetic-tf2-tools \
        ros-noetic-urdf-tutorial \
    && rm -rf /var/lib/apt/lists/*

RUN rosdep init || true

RUN set -eux; \
    (getent group render >/dev/null || groupadd --system --gid 109 render 2>/dev/null || groupadd --system render); \
    (getent group ${USER_GID} >/dev/null || groupadd --gid ${USER_GID} ${USERNAME}); \
    (id -u ${USERNAME} >/dev/null 2>&1 || useradd -s /bin/bash --uid ${USER_UID} --gid ${USER_GID} -m ${USERNAME}); \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME}; \
    chmod 0440 /etc/sudoers.d/${USERNAME}; \
    usermod -aG video,render,audio,dialout,plugdev ${USERNAME}

# ============================================================================
# Modern Mesa drivers (kisak PPA) — for recent Intel GPUs
# ----------------------------------------------------------------------------
# Your GPU has PCI ID 0xa721 = Intel UHD Graphics (Alder Lake-P, 12th gen).
# Ubuntu 20.04's stock Mesa (20.x) is too old; it knows nothing about this
# chip and falls back to llvmpipe (software rendering).
#
# kisak/kisak-mesa backports current Mesa releases (24.x+) to Focal.
# We use `dist-upgrade` instead of `upgrade` because Mesa upgrades often
# involve package replacements (e.g. libgl1-mesa-glx → libglx-mesa0) that
# `upgrade` won't perform but `dist-upgrade` will.
#
# We also install i965-va-driver and intel-media-va-driver explicitly so
# the iris DRI bits get pulled in cleanly.
# ============================================================================
RUN add-apt-repository -y ppa:kisak/kisak-mesa && \
    apt-get update && \
    apt-get -y --with-new-pkgs upgrade && \
    apt-get -y dist-upgrade && \
    apt-get install -y --no-install-recommends \
        libgl1-mesa-dri \
        libglx-mesa0 \
        libegl-mesa0 \
        libegl1 \
        libgles2 \
        libglapi-mesa \
        libglx0 \
        libgl1 \
        mesa-va-drivers \
        mesa-vulkan-drivers \
        mesa-utils \
        i965-va-driver \
        intel-media-va-driver \
    && rm -rf /var/lib/apt/lists/*

# Show in build log which Mesa version we ended up with — useful for debugging
RUN dpkg -l | grep -E '^ii  (libgl1-mesa-dri|mesa-vulkan-drivers|libegl-mesa0)' || true

USER ${USERNAME}
WORKDIR /home/${USERNAME}

RUN rosdep update

RUN echo "source /opt/ros/${ROS_DISTRO}/setup.bash" >> /home/${USERNAME}/.bashrc && \
    echo "if [ -f /home/${USERNAME}/catkin_ws/devel/setup.bash ]; then source /home/${USERNAME}/catkin_ws/devel/setup.bash; fi" >> /home/${USERNAME}/.bashrc && \
    echo "export ROS_HOSTNAME=localhost" >> /home/${USERNAME}/.bashrc && \
    echo "export ROS_MASTER_URI=http://localhost:11311" >> /home/${USERNAME}/.bashrc && \
    echo "export GAZEBO_MODEL_PATH=\$GAZEBO_MODEL_PATH:/home/${USERNAME}/catkin_ws/src" >> /home/${USERNAME}/.bashrc && \
    echo "export PS1='\[\e[1;32m\][ros-noetic]\[\e[0m\] \u@\h:\w\$ '" >> /home/${USERNAME}/.bashrc

RUN mkdir -p /home/${USERNAME}/catkin_ws/src

CMD ["/bin/bash"]