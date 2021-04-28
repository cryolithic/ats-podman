#! /bin/sh

set -e

apt update

# required for apt-key
apt install -y gnupg2

# enable buster-backports repository
echo 'deb http://deb.debian.org/debian buster-backports main' > /etc/apt/sources.list.d/buster-backports.list

# enable Untangle's buster/latest repository
echo deb http://foo:foo@updates.untangle.com/public/buster 16.2.0 main > /etc/apt/sources.list.d/ngfw-stable.list
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 0B9D6AE3627BF103

# enable OpenSUSE's Kubic repository
echo 'deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/Debian_10/ /' > /etc/apt/sources.list.d/kubic-podman-stable.list
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 4D64390375060AA4

# update cache and install packages
apt update
apt install -y podman cri-o-runc dnsmasq libseccomp2/buster-backports linux-image-4.19.0-11-untangle-amd64 python3-jinja2

# use only docker.io repository for now (quay.io is another default
# starting in podman 3.0)
perl -i -pe 's/(?<=^unqualified-search-registries = ).*/["docker.io"]/' /etc/containers/registries.conf

# remove non-Untangle kernels 
DEBIAN_FRONTEND=noninteractive apt purge -y $(dpkg -l | awk '/ii  linux-image/ && !/untangle/ { print $2}')

# set some sysctls (https://bugzilla.redhat.com/show_bug.cgi?id=1829596)
SYSCTLS_PODMAN=/etc/sysctl.d/99-podman.conf
cat <<EOF > $SYSCTLS_PODMAN
fs.inotify.max_queued_events = 1048576
fs.inotify.max_user_instances = 1048576
fs.inotify.max_user_watches = 1048576
EOF
sysctl -p $SYSCTLS_PODMAN

# notify reboot on the Untangle kernel
uname -a | grep -qi untangle  || echo "You need to reboot on the Untangle kernel"
