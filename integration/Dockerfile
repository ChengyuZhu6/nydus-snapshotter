ARG CONTAINERD_VER=1.6.15
ARG CONTAINERD_PROJECT=/containerd
ARG RUNC_VERSION=1.1.4
ARG NYDUS_SNAPSHOTTER_PROJECT=/nydus-snapshotter
ARG DOWNLOADS_MIRROR="https://github.com"
ARG NYDUS_VER=2.2.4
ARG NERDCTL_VER=1.7.6
ARG DELVE_VER=1.23.0

FROM golang:1.21.12-bookworm AS golang-base

ARG CONTAINERD_VER
ARG CONTAINERD_PROJECT
ARG RUNC_VERSION
ARG NYDUS_SNAPSHOTTER_PROJECT
ARG DOWNLOADS_MIRROR
ARG NYDUS_VER
ARG NERDCTL_VER
ARG DELVE_VER

# RUN echo '\
# deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bullseye main contrib non-free\n\
# deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bullseye-updates main contrib non-free\n\
# deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bullseye-backports main contrib non-free\n\
# deb https://mirrors.tuna.tsinghua.edu.cn/debian-security bullseye-security main contrib non-free\n' > /etc/apt/sources.list

RUN apt-get update -qq && apt-get install -qq libbtrfs-dev libseccomp-dev sudo psmisc jq lsof net-tools

RUN go install github.com/go-delve/delve/cmd/dlv@v"$DELVE_VER"

# Install containerd
RUN wget -q ${DOWNLOADS_MIRROR}/containerd/containerd/releases/download/v${CONTAINERD_VER}/containerd-${CONTAINERD_VER}-linux-amd64.tar.gz && \
  tar xzf containerd-${CONTAINERD_VER}-linux-amd64.tar.gz && \
  install -D -m 755 bin/* /usr/local/bin/
COPY misc/example/containerd-config.toml /etc/containerd/config.toml

# Install runc
RUN wget -q ${DOWNLOADS_MIRROR}/opencontainers/runc/releases/download/v${RUNC_VERSION}/runc.amd64 && \
  install -D -m 755 runc.amd64 /usr/local/bin/runc

# Install nydusd nydus-image
RUN  wget -q ${DOWNLOADS_MIRROR}/dragonflyoss/nydus/releases/download/v${NYDUS_VER}/nydus-static-v${NYDUS_VER}-linux-amd64.tgz && \
  tar xzf nydus-static-v${NYDUS_VER}-linux-amd64.tgz && \
  install -D -m 755 nydus-static/nydusd /usr/local/bin/nydusd && \
  install -D -m 755 nydus-static/nydus-image /usr/local/bin/nydus-image && \
  install -D -m 755 nydus-static/nydusctl /usr/local/bin/nydusctl

# Install nerdctl
RUN wget -q ${DOWNLOADS_MIRROR}/containerd/nerdctl/releases/download/v${NERDCTL_VER}/nerdctl-${NERDCTL_VER}-linux-amd64.tar.gz && \
  tar xzf nerdctl-${NERDCTL_VER}-linux-amd64.tar.gz && \
  install -D -m 755 nerdctl /usr/local/bin/nerdctl

# Install fscache driver configuration file
COPY misc/snapshotter/nydusd-config.fscache.json /etc/nydus/nydusd-config.fscache.json
COPY misc/snapshotter/nydusd-config-localfs.json /etc/nydus/nydusd-config-localfs.json
COPY misc/snapshotter/config.toml /etc/nydus/config.toml

VOLUME [ "/var/lib" ]

COPY integration/entrypoint.sh /

WORKDIR /nydus-snapshotter

ENV PATH="${PATH}:/usr/local/bin/"

# Prevent git from complaining about ownership
RUN git config --global --add safe.directory /nydus-snapshotter

ENTRYPOINT [ "/bin/bash",  "-c",  "make install && /entrypoint.sh"]
