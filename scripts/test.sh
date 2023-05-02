#!/bin/bash

set -o pipefail
set -o errexit
set -o nounset
set -o xtrace

function test {
    kubectl version
    workers=$(kubectl get nodes -l node-role.kubernetes.io/control-plane!= -o jsonpath='{range .items[*]}"{.metadata.name}",{"\n"}{end}')
    echo "{\"workers\":[${workers::-1}]}"
}

for version in v1.27.1 v1.26.4; do
    curl -fsSL http://bit.ly/install_pkg | PKG=kubectl PKG_KUBECTL_VERSION="$version" bash
    test
done
