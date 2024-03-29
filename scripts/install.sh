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
if [[ ${DEBUG:-false} == "true" ]]; then
    set -o xtrace
    export PKG_DEBUG=true
fi

export CLUSTER_API_VERSION=1.5.2

# Install dependencies
# NOTE: Shorten link -> https://github.com/electrocucaracha/pkg-mgr_scripts
curl -fsSL http://bit.ly/install_pkg | PKG_COMMANDS_LIST="docker,kubectl,kind,yq,helm,make,gcc" PKG="cni-plugins" bash

if ! command -v clab >/dev/null; then
    curl -fsSL https://get.containerlab.dev | bash
    clab completion bash | sudo tee /etc/bash_completion.d/clab >/dev/null
fi

if ! command -v clusterctl >/dev/null; then
    curl -s "https://i.jpillora.com/kubernetes-sigs/cluster-api@v$CLUSTER_API_VERSION!?as=clusterctl" | bash
    clusterctl completion bash | sudo tee /etc/bash_completion.d/clusterctl >/dev/null
fi
