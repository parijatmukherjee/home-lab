# E2E Test Container for Home CI/CD Server
# Based on Ubuntu 22.04 LTS (Jammy) for better package compatibility
FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install systemd and basic dependencies required for testing
RUN apt-get update && apt-get install -y \
    systemd \
    systemd-sysv \
    sudo \
    curl \
    wget \
    git \
    ca-certificates \
    gnupg \
    iproute2 \
    iputils-ping \
    net-tools \
    vim \
    dnsutils \
    bind9-host \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create test user with sudo access
RUN useradd -m -s /bin/bash -G sudo testuser && \
    echo "testuser:testpassword" | chpasswd && \
    echo "testuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Create deployment directory
RUN mkdir -p /home/testuser/workspace/home-lab

# Configure systemd
RUN cd /lib/systemd/system/sysinit.target.wants/ && \
    ls | grep -v systemd-tmpfiles-setup | xargs rm -f && \
    rm -f /lib/systemd/system/multi-user.target.wants/* && \
    rm -f /etc/systemd/system/*.wants/* && \
    rm -f /lib/systemd/system/local-fs.target.wants/* && \
    rm -f /lib/systemd/system/sockets.target.wants/*udev* && \
    rm -f /lib/systemd/system/sockets.target.wants/*initctl* && \
    rm -f /lib/systemd/system/basic.target.wants/* && \
    rm -f /lib/systemd/system/anaconda.target.wants/*

# Set working directory
WORKDIR /home/testuser/workspace/home-lab

# Expose ports for testing
EXPOSE 80 443 8080 81 19999

# Use systemd as init system
STOPSIGNAL SIGRTMIN+3
ENTRYPOINT ["/sbin/init"]
