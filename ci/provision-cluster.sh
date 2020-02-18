#!/usr/bin/env bash

# Copyright 2017, Pure Storage Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -xe

SCRIPT_DIR=$(dirname $0)
WORKSPACE=${WORKSPACE:-$(pwd)}


if [[ ! -f "${WORKSPACE}/test-env.sh" ]]; then
    ${WORKSPACE}/ci/setup-test-env.sh
fi
. ${WORKSPACE}/test-env.sh

# Start by setting up some env variables used by scripts we call
export CLUSTER_INVENTORY=${CLUSTER_INVENTORY:-$(pwd)/cluster-inventory.yaml}
export CLUSTER_KEY=${CLUSTER_KEY:-${HOME}/.ssh/jenkins_key}
export VERBOSE=true
export PURE_K8S_NAMESPACE=${PURE_K8S_NAMESPACE:-k8s${TEST_ID}}

# Now some local ones for parameters
LOG_BASE_DIR=${WORKSPACE}/logs
TEST_CLUSTER_IMAGE=${TEST_CLUSTER_IMAGE:-"k8s-base-ubuntu-16.04"}
TEST_CLUSTER_SIZE=${TEST_CLUSTER_SIZE:-1}
# options for STORAGE_SPEC are flex/csi
export TEST_STORAGE_SPEC=${TEST_STORAGE_SPEC:-csi}
TEST_ITERATIONS=${TEST_ITERATIONS:-1}
TEST_KUBECONF=${TEST_KUBECONF:-${WORKSPACE}/kube.conf}
TEST_PURE_KUBE_JSON=${TEST_PURE_KUBE_JSON:-${WORKSPACE}/pure-kube.json}
TEST_TMP_DIR=/tmp/${TEST_ID}
TEST_KUBERNETES_VER=${KUBERNETES_VERSION:-1.13}
TEST_PKG_URL_BASE=${TEST_PKG_URL_BASE:-"ftp://jenkins:jenkins@pc2-ftp.dev.purestorage.com/test"}
TEST_REGEX=${TEST_REGEX:-'.*'}
TEST_OS_AZ=${TEST_OS_AZ:-'newstack'}
TEST_OS_NETWORK=${TEST_OS_NETWORK:-''}
PURE_HELM_VALUE_FILE=${PURE_HELM_VALUE_FILE:-${WORKSPACE}/plugin-values.yaml}
# TODO: Make this point to the script in the operator/helm repo
OPERATOR_SCRIPT=${WORKSPACE}/operator-csi-plugin/install.sh

source ${NSM_DEV_TOOLS}/scripts/cluster/cluster-utils.sh

mkdir -p ${LOG_BASE_DIR}
mkdir -p ${TEST_TMP_DIR}

${NSM_DEV_TOOLS}/scripts/bash-utils/print-console-label.sh "Provisioning Cluster Nodes"

SUCCESSFULLY_PROVISIONED=false

while [[ ${SUCCESSFULLY_PROVISIONED} != true ]]
do
    if ${NSM_DEV_TOOLS}/scripts/cluster/create-cluster-hosts.sh --helm-values-file=${PURE_HELM_VALUE_FILE} --cluster-name=${TEST_CLUSTER_NAME} --cluster-size=${TEST_CLUSTER_SIZE} --cluster-base-image-tag=${TEST_CLUSTER_IMAGE} --cluster-az=${TEST_OS_AZ} --cluster-networks=${TEST_OS_NETWORK} --operator-install-script=${OPERATOR_SCRIPT}
    then
        SUCCESSFULLY_PROVISIONED=true
    else
        echo "Node provisioning failed, cleaning up hosts to try again"
        # clean up hosts
        ${NSM_DEV_TOOLS}/scripts/cluster/delete-cluster.sh
    fi
done


