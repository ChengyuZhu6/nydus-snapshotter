#!/usr/bin/env bash
# Copyright (c) 2023. Nydus Developers. All rights reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o pipefail
set -o nounset

# Container runtime config, the default container runtime is containerd
CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-containerd}"
CONTAINER_RUNTIME_CONFIG="${CONTAINER_RUNTIME_CONFIG:-/etc/containerd/config.toml}"

# Common nydus snapshotter config options
FS_DRIVER="${FS_DRIVER:-fusedev}"
SNAPSHOTTER_GRPC_SOCKET="${SNAPSHOTTER_GRPC_SOCKET:-/run/containerd-nydus/containerd-nydus-grpc.sock}"

# The directory about nydus and nydus snapshotter
NYDUS_CONFIG_DIR="${NYDUS_CONFIG_DIR:-/etc/nydus}"
NYDUS_LIB_DIR="${NYDUS_LIB_DIR:-/var/lib/containerd-nydus}"
NYDUS_BINARY_DIR="${NYDUS_BINARY_DIR:-/usr/local/bin}"
SNAPSHOTTER_SCRYPT_DIR="${SNAPSHOTTER_SCRYPT_DIR:-/opt/nydus}"

# The binary about nydus-snapshotter
SNAPSHOTTER_BINARY="${SNAPSHOTTER_BINARY:-${NYDUS_BINARY_DIR}/containerd-nydus-grpc}"
# The config about nydus snapshotter
SNAPSHOTTER_CONFIG="${SNAPSHOTTER_CONFIG:-${NYDUS_CONFIG_DIR}/config.toml}"
# If true, the script would enable the "runtime specific snapshotter" in containerd config.
ENABLE_RUNTIME_SPECIFIC_SNAPSHOTTER="${ENABLE_RUNTIME_SPECIFIC_SNAPSHOTTER:-false}"

COMMANDLINE=""

# If we fail for any reason a message will be displayed
die() {
    msg="$*"
    echo "ERROR: $msg" >&2
    exit 1
}

function fs_driver_handler() {

    case "${FS_DRIVER}" in
    fusedev) 
        sed -i -e "s|nydusd_config = .*|nydusd_config = ${NYDUS_CONFIG_DIR}/nydusd-fusedev.json|" "${SNAPSHOTTER_CONFIG}" 
        sed -i -e "s|fs_driver = .*|fs_driver = \"fusedev\"|" "${SNAPSHOTTER_CONFIG}" 
        sed -i -e "s|daemon_mode = .*|daemon_mode = \"multiple\"|" "${SNAPSHOTTER_CONFIG}" 
        ;;
    fscache) 
        sed -i -e "s|nydusd_config = .*|nydusd_config = ${NYDUS_CONFIG_DIR}/nydusd-fscache.json|" "${SNAPSHOTTER_CONFIG}" 
        sed -i -e "s|fs_driver = .*|fs_driver = \"fscache\"|" "${SNAPSHOTTER_CONFIG}"
        sed -i -e "s|daemon_mode = .*|daemon_mode = \"multiple\"|" "${SNAPSHOTTER_CONFIG}"  
        ;;
    blockdev) 
        sed -i -e "s|fs_driver = .*|fs_driver = \"blockdev\"|" "${SNAPSHOTTER_CONFIG}" 
        sed -i -e "s|enable_kata_volume = .*|enable_kata_volume = true|" "${SNAPSHOTTER_CONFIG}" 
        sed -i -e "s|enable_tarfs = .*|enable_tarfs = true|" "${SNAPSHOTTER_CONFIG}" 
        sed -i -e "s|daemon_mode = .*|daemon_mode = \"none\"|" "${SNAPSHOTTER_CONFIG}"  
        sed -i -e "s|export_mode = .*|export_mode = \"layer_block_with_verity\"|" "${SNAPSHOTTER_CONFIG}"  
        ;;
    proxy) 
        sed -i -e "s|fs_driver = .*|fs_driver = \"proxy\"|" "${SNAPSHOTTER_CONFIG}" 
        sed -i -e "s|enable_kata_volume = .*|enable_kata_volume = true|" "${SNAPSHOTTER_CONFIG}" 
        sed -i -e "s|daemon_mode = .*|daemon_mode = \"none\"|" "${SNAPSHOTTER_CONFIG}"  
        ;;
    *) die "invalid fs driver ${FS_DRIVER}" ;;
    esac
    COMMANDLINE+=" --config ${SNAPSHOTTER_CONFIG}"
}

function configure_snapshotter() {

    echo "configuring snapshotter"
    if [ "${CONTAINER_RUNTIME}" != "containerd" ]; then
        die "not supported container runtime: ${CONTAINER_RUNTIME}"
    fi

    # Copy the container runtime config to a backup
    cp "$CONTAINER_RUNTIME_CONFIG" "$CONTAINER_RUNTIME_CONFIG".bak.nydus


    # When trying to edit the config file that is mounted by docker with `sed -i`, the error would happend:
    # sed: cannot rename /etc/containerd/config.tomlpmdkIP: Device or resource busy  
    # The reason is that `sed`` with option `-i` creates new file, and then replaces the old file with the new one, 
    # which definitely will change the file inode. But the file is mounted by docker, which means we are not allowed to 
    # change its inode from within docker container.
    # 
    # So we copy the original file to a backup, make changes to the backup, and then overwrite the original file with the backup.
    cp "$CONTAINER_RUNTIME_CONFIG" "$CONTAINER_RUNTIME_CONFIG".bak
    # Check and add nydus proxy plugin in the config
    if grep -q '\[proxy_plugins.nydus\]' "$CONTAINER_RUNTIME_CONFIG".bak; then
        echo "the config has configured the nydus proxy plugin!"
    else
        echo "Not found nydus proxy plugin!"
        cat <<EOF >>"$CONTAINER_RUNTIME_CONFIG".bak
        
    [proxy_plugins.nydus]
        type = "snapshot"
        address = "$SNAPSHOTTER_GRPC_SOCKET"
EOF
    fi

    if grep -q 'disable_snapshot_annotations' "$CONTAINER_RUNTIME_CONFIG".bak; then
        sed -i -e "s|disable_snapshot_annotations = .*|disable_snapshot_annotations = false|" \
                "${CONTAINER_RUNTIME_CONFIG}".bak
    else
        sed -i '/\[plugins\..*\.containerd\]/a\disable_snapshot_annotations = false' \
			"${CONTAINER_RUNTIME_CONFIG}".bak
    fi
    if grep -q 'discard_unpacked_layers' "$CONTAINER_RUNTIME_CONFIG".bak; then
        sed -i -e "s|discard_unpacked_layers = .*|discard_unpacked_layers = false|" \
                "${CONTAINER_RUNTIME_CONFIG}".bak
    else
        sed -i '/\[plugins\..*\.containerd\]/a\discard_unpacked_layers = false' \
			"${CONTAINER_RUNTIME_CONFIG}".bak
    fi

    if [ "${ENABLE_RUNTIME_SPECIFIC_SNAPSHOTTER}" == "false" ]; then
        sed -i -e '/\[plugins\..*\.containerd\]/,/snapshotter =/ s/snapshotter = "[^"]*"/snapshotter = "nydus"/' "${CONTAINER_RUNTIME_CONFIG}".bak
    fi
    cat "${CONTAINER_RUNTIME_CONFIG}".bak >  "${CONTAINER_RUNTIME_CONFIG}"
    nsenter -t 1 -m systemctl -- restart containerd.service
}

function deploy_snapshotter() {
    echo "deploying snapshotter"
    COMMANDLINE="${SNAPSHOTTER_BINARY}"
    fs_driver_handler
    configure_snapshotter
    ${COMMANDLINE} &
}
