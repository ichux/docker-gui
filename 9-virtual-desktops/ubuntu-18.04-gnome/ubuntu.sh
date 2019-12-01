#!/bin/bash
#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
# 
#   http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#

BIN=$(cd $(dirname $0); echo ${PWD%docker-gui*})docker-gui/bin
. $BIN/docker-command.sh
. $BIN/docker-xauth.sh

# The X11 DISPLAY number of the nested Xephyr X server.
NESTED_DISPLAY=:1

IMAGE=ubuntu-gnome:18.04
CONTAINER=ubuntu

# Create initial /etc/passwd /etc/shadow /etc/group credentials if they
# don't already exist in this path. We use template files from a container
# spawned from the image we'll be using in the main run so that users and
# groups will be correct. If we copy from the host we may see problems if
# the host distro is different to the container distro, so don't do that.
# Note that the command below creates a new user and group in the cloned
# credentials files that match the user running this script.
if ! test -f "etc.tar.gz"; then
    echo "Creating /etc/passwd /etc/shadow and /etc/group for container."
    $DOCKER_COMMAND run --rm -it \
        -v $PWD:/mnt \
        $IMAGE sh -c 'adduser --uid '$(id -u)' --no-create-home '$(id -un)'; usermod -aG sudo '$(id -un)'; tar zcf /mnt/etc.tar.gz -C / ./etc/passwd ./etc/shadow ./etc/group'
fi

# Create home directory
if ! test -d $(id -un); then
    cp -R /etc/skel/. $(id -un)
    rm -rf $(id -un)/.mozilla
    echo "export DISPLAY=unix$NESTED_DISPLAY" >> $(id -un)/.profile
    echo "export XAUTHORITY=$DOCKER_XAUTHORITY" >> $(id -un)/.profile
    echo "DISPLAY=:0 Xephyr $NESTED_DISPLAY -resizeable -ac -reset -terminate 2> /dev/null&" >> $(id -un)/.profile
    echo -e "\nif ! test -d \"Desktop\"; then\n    gsettings set org.gnome.shell enabled-extensions \"['ubuntu-dock@ubuntu.com']\"\n    gsettings set org.gnome.desktop.background show-desktop-icons true\n    gsettings set org.gnome.nautilus.desktop home-icon-visible false\n    gsettings set org.gnome.nautilus.icon-view default-zoom-level 'small'\n    gsettings set org.gnome.desktop.interface gtk-theme 'Ambiance'\n    gsettings set org.gnome.desktop.interface cursor-theme 'DMZ-White'\n    gsettings set org.gnome.desktop.interface icon-theme 'Humanity'\nfi\n\n/etc/X11/Xsession" >> $(id -un)/.profile
fi

# Launch container as root to init core Linux services.
# --ipc=host is set to allow Xephyr to use SHM XImages
$DOCKER_COMMAND run --rm -d \
    --name $CONTAINER \
    --ipc=host \
    --shm-size 2g \
    --security-opt apparmor=unconfined \
    --cap-add=SYS_ADMIN --cap-add=SYS_BOOT -v /sys/fs/cgroup:/sys/fs/cgroup \
    -v $PWD/$(id -un):/home/$(id -un) \
    $X11_XAUTH \
    -v /tmp/.X11-unix/X0:/tmp/.X11-unix/X0:ro \
    $IMAGE /sbin/init

# cp credentials bundle to container
cat etc.tar.gz | $DOCKER_COMMAND cp - $CONTAINER:/

# exec login to the container
$DOCKER_COMMAND exec -it $CONTAINER login

