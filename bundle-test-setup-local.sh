#!/bin/bash
# This script helps run the bundle-tests locally
# It runs from the source root directory of a cloned bundle-kubeflow repo
# Note: after this you still need to configure the public-urls, username and password and namespace (welcome page)

exec 2>&1  # Redirect stderr to stdout

# Install tools
echo "[DEPLOY SCRIPT] Installing tools..."
sudo apt-get update -yqq
sudo apt-get install -yqq python3-pip
sudo --preserve-env=http_proxy,https_proxy,no_proxy pip3 install tox
sudo snap install charmcraft --classic
sudo snap install firefox

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

# Set up environment for gecko driver
echo "[DEPLOY SCRIPT] Setting up environment for gecko driver..."
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
echo "$(id -u)"
loginctl enable-linger $USER
sudo apt-get install dbus-user-session -yqq
systemctl --user start dbus.service

# Bundle Test Requirements
echo "[DEPLOY SCRIPT] Installing requirements for the bundle tests..."
pip install lightkube
pip install pytest
pip install pytest-operator
pip install 'kfp<2.0.0'
pip install 'juju<3.0.0'
pip install 'selenium>=4.8.3'
pip install 'webdriver_manager>=3.8.5'

# Deploy KF
echo "[DEPLOY SCRIPT] Deploying Kubeflow"
sg microk8s -c 'juju deploy kubeflow --trust --channel=1.7/stable' || { echo "Error deploying Kubeflow"; exit 1; }