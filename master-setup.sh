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

current_ip_address="$(hostname -I | awk '{ print $1 }')"
user="jason"

# Control plane setup
if [[ -f /etc/kubernetes/admin.conf ]]; then
    success "Kubeadm Initialization: Master node control-plane is already initialized"
else
    info "Kubeadm Initialization: Master node control-plane has not been initialized yet, initializing now"
    if sudo kubeadm init --apiserver-advertise-address="${current_ip_address}" ; then
        success "Kubeadm Initialization: Successfully initialized kubernetes control-plane"
    else
        fail "Kubeadm Initialization: Failed to initialize kubernetes control-plane"
    fi
fi

# Admin setup
if [[ -d /home/${user}/.kube ]]; then
    success "Kubeadm Credentials: Administrative credentials are already setup"
else
    info "Kubeadm Credentials: Administrative credentials have not been setup, setting up now"
    if mkdir -p /home/${user}/.kube \
        && sudo cp -i /etc/kubernetes/admin.conf /home/${user}/.kube/config \
        && sudo chown -R "$(sudo -u ${user} id -u)":"$(sudo -u ${user} id -g)" /home/${user}/.kube ; then
        success "Kubeadm Credentials: Successfully setup admin credentials for ${user}"
    else
        fail "Kubeadm Credentials: Failed to setup admin credentials for ${user}"
    fi
fi

# Installs all firewall rules required for the master node
# Values from https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#control-plane-node-s
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

add_ufw_pibernetes_inbound_application "Pibernetes Kubernetes API Server" "Used by All" "6443/tcp"
add_ufw_pibernetes_inbound_application "Pibernetes etcd Server Client API" "Used by kube-apiserver, etcd" "2379:2380/tcp"
add_ufw_pibernetes_inbound_application "Pibernetes Kubernetes Scheduler" "Used by Self" "10251/tcp"
add_ufw_pibernetes_inbound_application "Pibernetes Kubernetes Controller Manager" "Used by Self" "10252/tcp"

if echo "y" | sudo ufw enable > /dev/null ; then
    success "UFW: Successfully restarted firewall"
else
    fail "UFW: Failed to restart firewall"
fi
