#!/bin/bash
# This script deploys Kubeflow on microk8s as per our tutorial
# Note: after this you still need to configure the public-urls, username and password and namespace (welcome page)

exec 2>&1  # Redirect stderr to stdout

# Setup microk8s
echo "[DEPLOY SCRIPT] Setting up microk8s..."
sudo snap install microk8s --classic --channel=1.24/stable || { echo "Error installing microk8s"; exit 1; }
sudo usermod -a -G microk8s $USER || { echo "Error adding user to microk8s group"; exit 1; }
# Is this chown redundant? Seems like .kube dir doesn't exist after microk8s install
sudo chown -f -R $USER ~/.kube

# Enable addons
echo "[DEPLOY SCRIPT] Enabling addons..."
sg microk8s -c 'microk8s enable dns hostpath-storage ingress metallb:10.64.140.43-10.64.140.49' || { echo "Error enabling addons"; exit 1; }

# Wait for microk8s to be ready and give time for addons
echo "[DEPLOY SCRIPT] Waiting for microk8s to be ready..."
sleep 90
sg microk8s -c 'microk8s status --wait-ready --timeout 150' || { echo "Error checking microk8s status"; exit 1; }

# Install and bootstrap juju
echo "[DEPLOY SCRIPT] Installing and bootstrapping juju..."
sudo snap install juju --classic --channel=2.9/stable || { echo "Error installing juju"; exit 1; }
sg microk8s -c 'juju bootstrap microk8s' || { echo "Error bootstrapping juju"; exit 1; }

# Add model and show status
echo "[DEPLOY SCRIPT] Adding model and checking status..."
sg microk8s -c 'juju add-model kubeflow --config default-series=focal --config automatically-retry-hooks=true' || { echo "Error adding model"; exit 1; }
sg microk8s -c 'juju model-config' || { echo "Error showing model config"; exit 1; }
sg microk8s -c 'juju status' || { echo "Error checking juju status"; exit 1; }

# Increase file system limits
echo "[DEPLOY SCRIPT] Increasing file system limits..."
sudo sysctl fs.inotify.max_user_instances=1280 || { echo "Error increasing fs.inotify.max_user_instances"; exit 1; }
sudo sysctl fs.inotify.max_user_watches=655360 || { echo "Error increasing fs.inotify.max_user_watches"; exit 1; }

# Deploy KF
echo "[DEPLOY SCRIPT] Deploying Kubeflow"
sg microk8s -c 'juju deploy kubeflow --trust --channel=1.7/stable' || { echo "Error deploying Kubeflow"; exit 1; }