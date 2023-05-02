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

for cluster in $(sudo kind get clusters); do
    sudo kind delete cluster --name "$cluster"
done
rm -rf ~/.kube/config

for container in $(sudo docker ps --quiet --all); do
    sudo docker kill "$container" >/dev/null || :
    sudo docker rm "$container" >/dev/null || :
done

for vol in $(sudo docker volume list --quiet); do
    sudo docker volume rm "$vol"
done
