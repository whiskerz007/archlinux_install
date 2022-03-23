#!/usr/bin/env bash
set -euo pipefail

err() { echo $@ >&2; }

# Check for required applications
readonly RequiredApplications=(
    genfstab
    networkctl
    pacstrap
    sed
)
for app in ${RequiredApplications[@]}; do
    command -v $app > /dev/null || MissingApplications+=( $app )
done
if declare -p MissingApplications &> /dev/null; then
    err "The following applications need to be installed before using this script."
    err "\n\t${MissingApplications[@]}\n\n"
    exit 1
fi

# Offer configuring WiFi, if WiFi adapter is present

# Check for internet connection
echo -n "Checking for internet connection..."
for i in {5..1}; do
    NetworkStatus=$(networkctl status -n 0 | sed -n -e 's/^[ \t]*Online state: \(.*\)/\1/p')
    [ 'online' == "$NetworkStatus" ] && break
    echo -n "$i..."
    sleep 1
done; echo
if [ 'online' != "$NetworkStatus" ]; then
    err "An internet connection was not detected."
    exit 1
fi

# Disk and partition

# Mounts
readonly MountPointRoot=/mnt
readonly MountPointBoot=${MountPointRoot}/boot
if ! mount | awk '{print $3}' | grep $MountPointRoot > /dev/null; then
    err "Nothing is mounted to '$MountPointRoot'. Doing nothing."
    exit 1
fi

# Select packages to install
Packages+=( linux linux-firmware )
Packages+=(  )

# Sort quickest mirrors

# Enable pacman parallel downloads
sed -E '/ParallelDownloads/ { s/^#//; s/[[:digit:]]+/10/ }' /etc/pacman.conf > /tmp/pacman.conf
mv /{tmp,etc}/pacman.conf

# Install OS
pacstrap $MountPointRoot base ${Packages[@]}

# Generate fstab
genfstab -U ${MountPointRoot} >> ${MountPointRoot}/etc/fstab

# Configure first boot parameters
readonly SystemdFirstbootOverridePath=${MountPointRoot}/etc/systemd/system/systemd-firstboot.service.d/override.conf
mkdir $(dirname $SystemdFirstbootOverridePath)
cat << EOF > $SystemdFirstbootOverridePath
[Service]
ExecStart=
ExecStart=/usr/bin/systemd-firstboot --force --prompt

[Install]
WantedBy=sysinit.target
EOF
rm ${MountPointRoot}/etc/machine-id
systemctl --root=${MountPointRoot} enable systemd-firstboot.service

# Configure systemd-networkd default DHCP behavior
cat << EOF > ${MountPointRoot}/etc/systemd/network/80-dhcp.network
[Match]
Type=ether wlan

[Network]
DHCP=yes
IPv6PrivacyExtensions=yes
EOF

# Setup boot manager
