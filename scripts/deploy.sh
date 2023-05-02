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

# _vercmp() - Function that compares two versions
function _vercmp {
    local v1=$1
    local op=$2
    local v2=$3
    local result

    # sort the two numbers with sort's "-V" argument.  Based on if v2
    # swapped places with v1, we can determine ordering.
    result=$(echo -e "$v1\n$v2" | sort -V | head -1)

    case $op in
    "==")
        [ "$v1" = "$v2" ]
        return
        ;;
    ">")
        [ "$v1" != "$v2" ] && [ "$result" = "$v2" ]
        return
        ;;
    "<")
        [ "$v1" != "$v2" ] && [ "$result" = "$v1" ]
        return
        ;;
    ">=")
        [ "$result" = "$v2" ]
        return
        ;;
    "<=")
        [ "$result" = "$v1" ]
        return
        ;;
    *)
        echo "unrecognised op: $op"
        exit 1
        ;;
    esac
}

if _vercmp "$(uname -r | cut -d\. -f1,2)" '>' "5.4"; then
    echo "gtp5g module would not work for kernel versions +5.4"
    exit 1
fi

# TODO: Improve solution
if [ ! -d /opt/gtp5g ]; then
    sudo git clone -b v0.3.1 --depth 1 https://github.com/free5gc/gtp5g.git /opt/gtp5g
    sudo chown -R "$USER:" /opt/gtp5g
fi
if ! lsmod | grep -q gtp5g; then
    pushd /opt/gtp5g >/dev/null
    make
    sudo make install
    popd >/dev/null
fi

kubectl config use-context regional-admin@regional
if ! helm repo list | grep -e towards5gs; then
    helm repo add towards5gs 'https://raw.githubusercontent.com/Orange-OpenSource/towards5gs-helm/main/repo/'
fi
if ! helm ls --namespace free5gc-system | grep -q free5gc; then
    helm upgrade --create-namespace --namespace free5gc-system --wait --install free5gc towards5gs/free5gc
fi
if ! helm ls --namespace ueransim-system | grep -q ueransim; then
    helm upgrade --create-namespace --namespace ueransim-system --wait --install ueransim towards5gs/ueransim
fi
