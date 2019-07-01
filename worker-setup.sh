#!/usr/bin/env bash

set -e # Fails immediately if a line fails

##
# Setup script for only worker nodes in a raspberry
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

# Port 30,000 is already in use, so we reset the node port range available
kubernetes_available_node_port_range="30001:32767"

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

add_ufw_pibernetes_inbound_application "Pibernetes Kubernetes NodePort Services" "Used by All, for exposing services externally from the cluster" "${kubernetes_available_node_port_range}/tcp"

if echo "y" | sudo ufw enable > /dev/null ; then
    success "UFW: Successfully restarted firewall"
else
    fail "UFW: Failed to restart firewall"
fi
