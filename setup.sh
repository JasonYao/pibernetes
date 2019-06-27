#!/usr/bin/env bash

set -e # Fails immediately if a line fails

##
# Setup script for any node in a raspberry
# kubernetes setup
##

##
# Pretty-print formatting
##

function info () {
	printf "\r  [ \033[00;34m..\033[0m ] %s\n" "$1"
}

function user () {
	printf "\r  [ \033[0;33m??\033[0m ] %s " "$1"
}

function success () {
	printf "\r\033[2K  [ \033[00;32mOK\033[0m ] %s\n" "$1"
}

function warn () {
	printf "\r\033[2K  [\033[0;31mWARN\033[0m] %s\n" "$1"
}

function fail () {
	printf "\r\033[2K  [\033[0;31mFAIL\033[0m] %s\n" "$1"
	echo ''
	exit 1
}

# We're technically running on debian 9 (stretch),
# though kubeadm is only in xenial right now
distribution="xenial"
user="jason"

# Docker setup
if [[ $(command -v docker) == "" ]]; then
    info "Docker: Docker not found, installing now"
    if curl -sSL get.docker.com | sh ; then
        success "Docker: Successfully installed docker"
    else
        fail "Docker: Failed to install docker"
    fi

    # Sets up user to use docker
    info "Docker: Adding user ${user} to docker group"
    if sudo usermod "${user}" -aG docker ; then
        success "Docker: Successfully added user ${user} to docker group"
    else
        fail "Docker: Failed to add user ${user} to docker group"
    fi
else
    success "Docker: Already installed docker"
fi

if [[ -f /etc/docker/daemon.json ]]; then
    success "Docker: Daemon configuration file already setup"
else
    info "Docker: Daemon configuration file not setup yet, setting up now"
    if {
        echo "{"
        echo "  \"exec-opts\": [\"native.cgroupdriver=systemd\"],"
        echo "  \"log-driver\": \"json-file\","
        echo "  \"log-opts\": {"
        echo "    \"max-size\": \"100m\""
        echo "  },"
        echo "  \"storage-driver\": \"overlay2\""
        echo "}"
    } | sudo tee /etc/docker/daemon.json > /dev/null \
    && sudo mkdir -p /etc/systemd/system/docker.service.d \
    && sudo systemctl daemon-reload \
    && sudo systemctl restart docker; then
        success "Docker: Daemon configuration file successfully setup"
    else
        fail "Docker: Failed to setup daemon configuration file"
    fi
fi

# Swap file
if [[ $(sudo swapon |  awk '{print $3}' | sed -n 2p) == "" ]]; then
    success "Swap: Swapfiles are already disabled"
else
    info "Swap: Swapfiles are currently enabled, disabling now"

    if sudo dphys-swapfile swapoff && sudo dphys-swapfile uninstall && sudo update-rc.d dphys-swapfile remove ; then
        success "Swap: Swapfiles are now disabled"
    else
        fail "Swap: Swapfiles failed to be disabled"
    fi
fi

# Adding kubernetes to the key ring
if [[ $(sudo apt-key list | grep "Google Cloud Packages Automatic Signing Key") == "" ]]; then
    info "APT Key: Google's kubernetes signing key has not been added yet, adding now"
    if curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add - ; then
        success "APT Key: Google's kubernetes signing key has now been added"
    else
        fail "APT Key: Failed to add Google's kubernetes signing key"
    fi
else
    success "APT Key: Google's kubernetes signing key is already added"
fi

# Adds the kubernetes repo
if [[ -f /etc/apt/sources.list.d/kubernetes.list ]]; then
    success "Repo: Kubernetes repo already added"
else
    info "Repo: Kubernetes repo has not been added yet, adding now"
    if echo "deb http://apt.kubernetes.io/ kubernetes-${distribution} main" | sudo tee /etc/apt/sources.list.d/kubernetes.list ; then
        success "Repo: Kubernetes repo is now added"
    else
        fail "Repo: Failed to add Kubernetes repo"
    fi
fi

# Installs kube admin cli
if [[ $(command -v kubeadm) == "" ]]; then
    info "Kube Admin: Kubernetes administration CLI not installed yet, installing now"
    if sudo apt-get update -q && sudo apt-get install -qy kubeadm ; then
        success "Kube Admin: Successfully installed kubeadm"
    else
        fail "Kube Admin: Failed to install kubeadm"
    fi
else
    success "Kube Admin: Already installed kubeadm"
fi

if [[ $(sudo grep "cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory" /boot/cmdline.txt) == "" ]]; then
    info "Permissions: Cgroup permissions not yet updated, updating now"
    if sudo cp /boot/cmdline.txt /boot/cmdline.txt.backup ; then
        success "Permissions: Successfully backed up old cmdline boot file"
    else
        fail "Permissions: Failed to back up old cmdline boot file"
    fi

    old_boot_file="$(head -n1 /boot/cmdline.txt)"
    if echo "${old_boot_file} cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory swapaccount=1" | sudo tee /boot/cmdline.txt &>/dev/null; then
        success "Permissions: Successfully updated cgroup permissions in boot file"
    else
        fail "Permissions: Failed to update cgroup permissions in boot file"
    fi

    warn "Permissions: Successfully updated permissions, rebooting in 5 seconds"
    sleep 5
    sudo reboot now
else
    success "Permissions: Cgroup permissions have already been updated"
fi

# Installs kubelet API firewall rule (required for all master/worker nodes)
all_ufw_apps="$(sudo ufw app list)"
ufw_pibernetes_config_file="/etc/ufw/applications.d/pibernetes"

function add_ufw_pibernetes_inbound_application() {
    full_application_name=$1
    description=$2
    ports=$3

    if [[ $(echo "${all_ufw_apps}" | grep "${full_application_name}") == "" ]]; then
        info "UFW: Firewall rule not added for ${full_application_name}, adding now"
        if {
            echo "[${full_application_name}]"
            echo "title=${full_application_name}"
            echo "description=${description}"
            echo "ports=${ports}"
            printf "\n\n"
        } | sudo tee -a "${ufw_pibernetes_config_file}" > /dev/null \
        && sudo ufw app update "${full_application_name}" \
        && sudo ufw allow in "${full_application_name}" > /dev/null; then
            success "UFW: Firewall rule for ${full_application_name} is now added"
        else
            fail "UFW: Failed to add in firewall rule for ${full_application_name}"
        fi
    else
        success "UFW: Firewall rule for ${full_application_name} already exists"
    fi
}

add_ufw_pibernetes_inbound_application "Pibernetes Kubelet API" "Used by Self, Control plane" "10250/tcp"

if echo "y" | sudo ufw enable > /dev/null ; then
    success "UFW: Successfully restarted firewall"
else
    fail "UFW: Failed to restart firewall"
fi
