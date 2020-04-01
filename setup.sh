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

# Disables swap file
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

if [[ $(sudo grep "cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory swapaccount=1" /boot/cmdline.txt) == "" ]]; then
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
add_ufw_pibernetes_inbound_application "Pibernetes Network Addon- Flannel" "Networking addon uses Flannel, for simple bare-bones networking" "8472/udp|8285/udp"
add_ufw_pibernetes_inbound_application "Pibernetes Health Metrics- Node Exporter" "Port to enable retrieving the health of nodes" "9100/tcp"

if echo "y" | sudo ufw enable > /dev/null ; then
    success "UFW: Successfully restarted firewall"
else
    fail "UFW: Failed to restart firewall"
fi

# Sets up node exporter on the node to expose metrics for prometheus
metrics_directory="/home/${user}/.pibernetes_metrics"
node_exporter_tarball="${metrics_directory}/node_exporter.tar.gz"
node_exporter_version="0.18.1"

if [[ $(command -v node_exporter) == "" ]]; then
    info "Node Exporter | Download: No node exporter found, getting version: ${node_exporter_version}"
    mkdir -p ${metrics_directory}

    # Downloads node exporter
    if curl --show-error --location https://github.com/prometheus/node_exporter/releases/download/v${node_exporter_version}/node_exporter-${node_exporter_version}.linux-armv7.tar.gz --output "${node_exporter_tarball}" ; then
        success "Node Exporter | Download: Downloaded node exporter"
    else
        fail "Node Exporter | Download: Failed to download node exporter"
    fi

    # Extracts the node exporter
    if sudo tar -xvf "${node_exporter_tarball}" -C /usr/local/bin/ --strip-components=1 ; then
        success "Node Exporter | Extraction: Extracted node exporter"
    else
        fail "Node Exporter | Extraction: Failed to extract node exporter from tarball"
    fi

    if rm -rf ${metrics_directory} ; then
        success "Node Exporter | Download: Cleaned up node exporter download"
    else
        # We don't want to fail if cleanup fails
        warn "Node Exporter | Download: Failed to clean up node exporter download, please remove yourself later: ${metrics_directory}"
    fi
else
    success "Node Exporter | Download: Node exporter already downloaded"
fi

# Makes a node exporter service
node_exporter_service_name="pibernetes-node-exporter"
node_exporter_service_file_name="${node_exporter_service_name}.service"
node_exporter_service_path="/etc/systemd/system/${node_exporter_service_file_name}"
textfile_metrics_directory="/metrics"
if [[ $(systemctl list-unit-files | grep "${node_exporter_service_file_name}") == "" ]]; then
    info "Node Exporter | Service: Could not find the node exporter service, creating now"
    if {
        echo "[Unit]"
        printf "Description=Exports node health metrics for prometheus to pick up\n\n"
        echo "[Service]"
        echo "Type=simple"
        echo "Restart=always"
        echo "RestartSec=1"
        echo "TimeoutStartSec=0"
        printf "ExecStart=/usr/local/bin/node_exporter --collector.textfile.directory %s\n\n" "${textfile_metrics_directory}"
        echo "[Install]"
        echo "WantedBy=multi-user.target"
    } | sudo tee "${node_exporter_service_path}" >/dev/null; then
        success "Node Exporter | Service: Successfully created node exporter service configuration"
    else
        fail "Node Exporter | Service: Failed to create node exporter service configuration"
    fi

    # Reloads the service list
    if sudo systemctl daemon-reload ; then
        success "Node Exporter | Service: Successfully reloaded service definitions"
    else
        fail "Node Exporter | Service: Failed to reload service definitions"
    fi
else
    success "Node Exporter | Service: Already created the node exporter service"
fi

# Makes sure that the node exporter service will restart upon reboot
if [[ $(systemctl list-unit-files --state=enabled | grep "${node_exporter_service_file_name}") == "" ]]; then
    info "Node Exporter | Service: Node exporter service is not set to restart upon reboots, setting up now"
    if sudo systemctl enable "${node_exporter_service_name}"; then
        success "Node Exporter | Service: Node exporter service is now set to self-start on boot"
    else
        fail "Node Exporter | Service: Failed to make the node exporter service self-start on boot"
    fi
else
    success "Node Exporter | Service: Node exporter service is already setup to self-start on boot"
fi

# Makes sure that we're exposing additional textfile-based metrics (E.g. SoC temperature)
sudo mkdir -p "${textfile_metrics_directory}"

# Enables exporting the raspberry pi's temperature
# via node exporter on a 10-second granularity. See here
# for a breakdown:
#   - Command generation: https://github.com/JasonYao/pibernetes/issues/5#issuecomment-605789525
#   - Putting it together: https://github.com/JasonYao/pibernetes/issues/5#issuecomment-605801222
grep 'thermal_zone0' /etc/crontab > /dev/null || printf '* *'"\t"'* * *'"\t"'root'"\t"'( %s )'"\n"'' 'tr -d '"'\n'"' < /sys/class/thermal/thermal_zone0/temp | xargs -0 printf "3k \%i 1000 /n" | dc | xargs -0 printf "core_temp_celsius \%.3f\n" | sudo tee /metrics/soc_temp.prom.$$ > /dev/null && sudo mv /metrics/soc_temp.prom.$$ /metrics/soc_temp.prom' | sudo tee -a /etc/crontab > /dev/null
grep 'sleep 10' /etc/crontab > /dev/null || printf '* *'"\t"'* * *'"\t"'root'"\t"'( %s )'"\n"'' 'sleep 10 ; tr -d '"'\n'"' < /sys/class/thermal/thermal_zone0/temp | xargs -0 printf "3k \%i 1000 /n" | dc | xargs -0 printf "core_temp_celsius \%.3f\n" | sudo tee /metrics/soc_temp.prom.$$ > /dev/null && sudo mv /metrics/soc_temp.prom.$$ /metrics/soc_temp.prom' | sudo tee -a /etc/crontab > /dev/null
grep 'sleep 20' /etc/crontab > /dev/null || printf '* *'"\t"'* * *'"\t"'root'"\t"'( %s )'"\n"'' 'sleep 20 ; tr -d '"'\n'"' < /sys/class/thermal/thermal_zone0/temp | xargs -0 printf "3k \%i 1000 /n" | dc | xargs -0 printf "core_temp_celsius \%.3f\n" | sudo tee /metrics/soc_temp.prom.$$ > /dev/null && sudo mv /metrics/soc_temp.prom.$$ /metrics/soc_temp.prom' | sudo tee -a /etc/crontab > /dev/null
grep 'sleep 30' /etc/crontab > /dev/null || printf '* *'"\t"'* * *'"\t"'root'"\t"'( %s )'"\n"'' 'sleep 30 ; tr -d '"'\n'"' < /sys/class/thermal/thermal_zone0/temp | xargs -0 printf "3k \%i 1000 /n" | dc | xargs -0 printf "core_temp_celsius \%.3f\n" | sudo tee /metrics/soc_temp.prom.$$ > /dev/null && sudo mv /metrics/soc_temp.prom.$$ /metrics/soc_temp.prom' | sudo tee -a /etc/crontab > /dev/null
grep 'sleep 40' /etc/crontab > /dev/null || printf '* *'"\t"'* * *'"\t"'root'"\t"'( %s )'"\n"'' 'sleep 40 ; tr -d '"'\n'"' < /sys/class/thermal/thermal_zone0/temp | xargs -0 printf "3k \%i 1000 /n" | dc | xargs -0 printf "core_temp_celsius \%.3f\n" | sudo tee /metrics/soc_temp.prom.$$ > /dev/null && sudo mv /metrics/soc_temp.prom.$$ /metrics/soc_temp.prom' | sudo tee -a /etc/crontab > /dev/null
grep 'sleep 50' /etc/crontab > /dev/null || printf '* *'"\t"'* * *'"\t"'root'"\t"'( %s )'"\n"'' 'sleep 50 ; tr -d '"'\n'"' < /sys/class/thermal/thermal_zone0/temp | xargs -0 printf "3k \%i 1000 /n" | dc | xargs -0 printf "core_temp_celsius \%.3f\n" | sudo tee /metrics/soc_temp.prom.$$ > /dev/null && sudo mv /metrics/soc_temp.prom.$$ /metrics/soc_temp.prom' | sudo tee -a /etc/crontab > /dev/null
success "Node Exporter | Additional Metrics: Additional metrics via textfile support is now setup"

# Makes sure that the node exporter is currently running
if [[ $(systemctl | grep pibernetes | grep running) == "" ]]; then
    info "Node Exporter | Service: Node exporter is not currently running, starting now"
    if sudo systemctl start "${node_exporter_service_name}" ; then
        success "Node Exporter | Service: Successfully started node exporter service"
    else
        fail "Node Exporter | Service: Failed to start node exporter service"
    fi
else
    success "Node Exporter | Service: Node exporter service already started"
fi

# Sets up cgroup stats retrieval. For more information, see https://stackoverflow.com/a/46753640
dropin_file="/etc/systemd/system/kubelet.service.d/10-kubeadm.conf"
if [[ $(sudo grep "runtime-cgroups" "${dropin_file}") == "" ]]; then
    info "cgroup stats setup: We haven't set the cgroup stat retrieval yet, setting now"
    if sudo perl -pi -e 's/(Environment="KUBELET_CONFIG_ARGS=--config=\/var\/lib\/kubelet\/config.yaml")/$1\nEnvironment="KUBELET_EXTRA_ARGS=--runtime-cgroups=\/systemd\/system.slice --kubelet-cgroups=\/systemd\/system.slice"/' "${dropin_file}" ; then
        success "cgroup stats setup: Successfully setup cgroup stats access"
        sudo systemctl restart kubelet
        sudo systemctl restart docker
        sudo systemctl daemon-reload
    else
        fail "cgroup stats setup: Failed to setup cgroup stats access"
    fi
else
    success "cgroup stats setup: Already setup cgroup stats retrieval"
fi
