#!/usr/bin/env bash
set -euo pipefail

dnf install -y tar gzip unzip jq git

curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/awscliv2.zip /tmp/aws

curl -fsSL -o /usr/local/bin/kubectl https://dl.k8s.io/release/v1.33.4/bin/linux/amd64/kubectl
chmod 0755 /usr/local/bin/kubectl

curl -fsSL -o /tmp/helm.tgz https://get.helm.sh/helm-v3.17.1-linux-amd64.tar.gz
tar -xzf /tmp/helm.tgz -C /tmp
cp /tmp/linux-amd64/helm /usr/local/bin/helm
chmod 0755 /usr/local/bin/helm
rm -rf /tmp/helm.tgz /tmp/linux-amd64

command -v jq
command -v aws
command -v kubectl
command -v helm
