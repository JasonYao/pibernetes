# Help

## Getting Version Numbers
- [Kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)
  - `kubeadm version`
- Kernal version
  - `uname -a`
- Kubernetes node versions
  - `kubectl get nodes`

## General Debugging Commands
- Seeing the status of kubernetes on a host
  - `systemctl status kubelet`
- Restarting the kubernetes service on a host
  - `sudo systemctl restart kubelet`
- Seeing the logs of kubernetes on a host
  - `sudo journalctl -u kubelet`

## Config Locations
- Baseline config: `/lib/systemd/system/kubelet.service`
- Drop-in config (probably the one you're trying to edit): `/etc/systemd/system/kubelet.service.d/10-kubeadm.conf`

## Upgrading Kubernetes Cluster
- [Upgrade the admin tool](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/) and have it do the legwork

## Networking Errors/Flannel Pods Crashing
### Situation
- Network issues are occurring

### Diagnosis
- `sudo journalctl -u kubelet` on a given host

### Remedy
- If you see `Error registering network: failed to configure interface flannel.1: failed to ensure address of interface flannel.1: link has incompatible addresses. Remove additional addresses and try again`, then do the following:
  - [on master node] `kubectl --namespace kube-system get pods -o wide`
  - Identify the `flannel` pod running on that node
  - [on bad node] SSH into bad node and run `sudo ip link delete flannel.1`
  - [on master node] `kubectl --namespace kube-system delete pod <flannel pod running on that node>`
- This can occur when manually deleting the flannel pods. See [here](https://github.com/coreos/flannel/issues/1060#issue-377079629) for more info
