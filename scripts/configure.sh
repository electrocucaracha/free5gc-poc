#!/bin/bash
# SPDX-license-identifier: Apache-2.0
##############################################################################
# Copyright (c) 2023
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Apache License, Version 2.0
# which accompanies this distribution, and is available at
# http://www.apache.org/licenses/LICENSE-2.0
##############################################################################

set -o pipefail
set -o errexit
set -o nounset
[[ ${DEBUG:-false} != "true" ]] || set -o xtrace

export KIND_CLUSTER_NAME=mgmt
export CLUSTER_TOPOLOGY=true
export KINDNET_VERSION=1.1.0
export MULTUS_CNI_VERSION=3.9.3

# deploy_mgmt_cluster() - Function that deploys a management cluster locally for clusterapi usage
function deploy_mgmt_cluster {
    if ! sudo kind get clusters | grep -q $KIND_CLUSTER_NAME; then
        cat <<EOF | sudo -E kind create cluster --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    image: kindest/node:v1.27.1
    extraMounts:
      - hostPath: /var/run/docker.sock
        containerPath: /var/run/docker.sock
EOF
    fi
    mkdir -p "$HOME/.kube"
    sudo chown -R "$USER" "$HOME/.kube/"
    chmod 600 "$HOME/.kube/config"

    clusterctl init --infrastructure docker
    for namespace in $(kubectl get namespaces -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep cap); do
        for deployment in $(kubectl get deployment --namespace "$namespace" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'); do
            kubectl rollout status "deployment/$deployment" --timeout=5m --namespace "$namespace"
        done
    done
    kubectl apply -f docker-infra.yml
}

# wait_clusters() - Function that waits for cluster readiness
function wait_clusters {
    max_attempts=10

    attempt_counter=0
    while [ "$(kubectl get machines -o jsonpath='{range .items[*]}{.status.phase}{"\n"}{end}' | sort | uniq)" != "Running" ]; do
        if [ ${attempt_counter} -eq ${max_attempts} ]; then
            echo "Max attempts reached waiting for provisioning machines"
            kubectl describe machine
            exit 1
        fi
        attempt_counter=$((attempt_counter + 1))
        sleep $((attempt_counter * 10))
    done
    attempt_counter=0
    until [ "$(kubectl get kubeadmcontrolplane -o jsonpath='{.items[*].status.initialized}')" == "true" ]; do
        if [ ${attempt_counter} -eq ${max_attempts} ]; then
            echo "Max attempts reached waiting for control planes"
            kubectl describe kubeadmcontrolplane
            exit 1
        fi
        attempt_counter=$((attempt_counter + 1))
        sleep $((attempt_counter * 10))
    done
}

# config_context() - Function that reconfigures the kubeconfig file to manage several clusters
function config_context {
    cp ~/.kube/config /tmp/kubeconfig
    clusterctl get kubeconfig regional >/tmp/regional
    cat <<EOT >~/.kube/config
apiVersion: v1
kind: Config
preferences: {}
current-context: kind-$KIND_CLUSTER_NAME

clusters:
$(yq eval -N '.clusters' /tmp/{kubeconfig,regional})

users:
$(yq eval -N '.users' /tmp/{kubeconfig,regional})

contexts:
$(yq eval -N '.contexts' /tmp/{kubeconfig,regional})
EOT
}

# post_clusters_install() - Function that install additional CNI and CSI services
function post_clusters_install {
    for context in $(kubectl config get-contexts --no-headers --output name); do
        if [[ $context != "kind-$KIND_CLUSTER_NAME" ]]; then
            kubectl apply -f "https://raw.githubusercontent.com/aojea/kindnet/v$KINDNET_VERSION/install-kindnet.yaml" --context "$context"
            kubectl apply -f "https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/v$MULTUS_CNI_VERSION/deployments/multus-daemonset-thick-plugin.yml" --context "$context"
            kubectl apply -f local-path-storage.yaml --context "$context"
        fi
    done
}

# connect_clusters() - Function that interconnects regional/edge worker nodes to N6 network
function connect_clusters {
    workers=$(kubectl get nodes -l node-role.kubernetes.io/control-plane!= -o jsonpath='{range .items[*]}"{.metadata.name}",{"\n"}{end}' --context "$1")
    echo "{\"workers\":[${workers::-1}]}" | tee /tmp/vars.json
    sudo clab deploy --topo topo.gotmpl --vars /tmp/vars.json --skip-post-deploy
}

deploy_mgmt_cluster
# Deploy regional/edge cluster
kubectl apply -f regional.yml
wait_clusters
config_context
post_clusters_install

# Wait for node readiness
for context in $(kubectl config get-contexts --no-headers --output name); do
    for node in $(kubectl get node -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' --context "$context"); do
        kubectl wait --for=condition=ready "node/$node" --timeout=3m --context "$context"
    done
done

# Wait for CNI and CSI service readiness
for context in $(kubectl config get-contexts --no-headers --output name); do
    if [[ $context != "kind-$KIND_CLUSTER_NAME" ]]; then
        # Set the default storage class
        kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' --context "$context"
        kubectl rollout status daemonset/kube-multus-ds \
            --namespace kube-system --timeout=3m --context "$context"
        kubectl rollout status deployment/local-path-provisioner \
            --namespace local-path-storage --timeout=3m --context "$context"
    fi
done

# Interconnect worker nodes
# NOTE: Node labels take time to be reflected
for context in $(kubectl config get-contexts --no-headers --output name); do
    if [[ $context != "kind-$KIND_CLUSTER_NAME" ]]; then
        connect_clusters "$context"
    fi
done
