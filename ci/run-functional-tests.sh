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

TEST_ID=${TEST_ID:-$(uuidgen | cut -c1-8)}

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
TEST_KUBERNETES_VER=${KUBERNETES_VERSION:-1.15}
TEST_PKG_URL_BASE=${TEST_PKG_URL_BASE:-"ftp://jenkins:jenkins@pc2-ftp.dev.purestorage.com/test"}
TEST_REGEX=${TEST_REGEX:-'.*'}
TEST_OS_AZ=${TEST_OS_AZ:-'newstack'}
TEST_OS_NETWORK=${TEST_OS_NETWORK:-''}
PURE_HELM_VALUE_FILE=${PURE_HELM_VALUE_FILE:-${WORKSPACE}/plugin-values.yaml}
# TODO: Make this point to the script in the operator/helm repo
OPERATOR_SCRIPT=${WORKSPACE}/pure-csi-driver/operator-csi-plugin/install.sh

source ${NSM_DEV_TOOLS}/scripts/cluster/cluster-utils.sh
source ${NSM_DEV_TOOLS}/scripts/bash-utils/trace-utils.sh

mkdir -p ${LOG_BASE_DIR}
mkdir -p ${TEST_TMP_DIR}

# Setup our exit trap function
function get_logs() {
    ${NSM_DEV_TOOLS}/scripts/bash-utils/print-console-label.sh "Trap EXIT: Collecting logs"

    ansible-playbook -i ${CLUSTER_INVENTORY} --private-key=${CLUSTER_KEY} /opt/nsm-dev-tools/scripts/log-collection/run-collect.yaml --extra-vars="PLUGIN_TYPE=kubernetes-${TEST_STORAGE_SPEC} COMBINED_OUTPUT_DIR=${LOG_BASE_DIR}/collected-info" -vv

    run_on_cluster_nodes all "mkdir -p ${TEST_TMP_DIR} && journalctl -b 2>&1 > ${TEST_TMP_DIR}/journal.log"
    copy_from_cluster_nodes all "${TEST_TMP_DIR}/journal.log" "${LOG_BASE_DIR}/"

    run_on_cluster_nodes all "cp -r /etc /tmp/etc && tar -czf /tmp/etc.tar.gz /tmp/etc"
    copy_from_cluster_nodes all /tmp/etc.tar.gz "${LOG_BASE_DIR}/"

    run_on_cluster_nodes all "cp -r /var/log /tmp/var-log && tar -czf /tmp/var-log.tar.gz /tmp/var-log"
    copy_from_cluster_nodes all /tmp/var-log.tar.gz "${LOG_BASE_DIR}/"
    rm -rf ${TEST_TMP_DIR}

    echo "Logs for functional test run can be found at: http://graylog-prod-newstack.dev.purestorage.com:30080/search?q=test_id%${TEST_ID}"
}

function onErr() {
    ${NSM_DEV_TOOLS}/scripts/bash-utils/print-console-label.sh  "TESTS FAILED, EXITING"
    echo "See logs above for error"
}
trap onErr ERR

function final_steps() {
    trace_metrics_for_exit_trap
    generate_trace_report
    get_logs
}
trap final_steps EXIT


# Configure logging for the hosts
echo "Configuring filebeat and starting the logging on all nodes..."
LOG_FIELDS_ENVS="TEST_ID=${TEST_ID}"
LOG_FIELDS_ENVS+=" TEST_PURE_BACKEND=${TEST_PURE_BACKEND}"
LOG_FIELDS_ENVS+=" STAGE_NAME=${STAGE_NAME:-local-test}"
LOG_FIELDS_ENVS+=" BUILD_NUMBER=${BUILD_NUMBER:--1}"
run_on_cluster_nodes all "${LOG_FIELDS_ENVS} ${NSM_DEV_TOOLS}/scripts/logging/start-graylog-filebeat.sh"


# Configure our registry
run_on_cluster_nodes all "${NSM_DEV_TOOLS}/scripts/docker/install-dtr-certificates.sh ${IMAGE_REGISTRY}"
run_on_cluster_nodes all "${NSM_DEV_TOOLS}/scripts/multipath-utils/setup-multipath.sh"


# Convert the inventory to json and deploy kubernetes
${NSM_DEV_TOOLS}/scripts/bash-utils/print-console-label.sh "Deploying Kubernetes"
trace_metrics ${NSM_DEV_TOOLS}/scripts/cluster/ansible_inventory_converter.py -i "${CLUSTER_INVENTORY}" -t pure-k8s-json -o "${TEST_PURE_KUBE_JSON}" -v ${TEST_KUBERNETES_VER}
trace_metrics ${NSM_DEV_TOOLS}/scripts/k8s/install-kube-cluster.sh -f "${TEST_PURE_KUBE_JSON}" -o "${TEST_KUBECONF}"

${NSM_DEV_TOOLS}/scripts/bash-utils/print-console-label.sh "Installing provisioner and flexvolume plugin"

# Setup some environment variables required for helm installation
export KUBECONFIG="${TEST_KUBECONF}"
export HELM_HOME="${WORKSPACE}/.helm"
[ -d ${HELM_HOME} ] && rm -rf ${HELM_HOME}
export ORCHESTRATOR_NAME=k8s

# init helm for the k8s cluster
${NSM_DEV_TOOLS}/scripts/k8s/helm/init-helm.sh

## Deploy the provisioner and flexvol stuff
#${WORKSPACE}/ci/helm-install.sh --install
#
#${NSM_DEV_TOOLS}/scripts/bash-utils/print-console-label.sh "Running functional.test"
#
## Get the functional tests binary
#if [[ ! -f "${WORKSPACE}/bin/functional.test" ]]; then
#    export GOOS=$(go env GOHOSTOS)
#    export GOARCH=$(go env GOHOSTARCH)
#    cd ${WORKSPACE} && make -j2 functional-tests
#fi
#
#for (( c=1; c<=${TEST_ITERATIONS}; c++ ))
#do
#        echo === Running functional test iteration : $c ===
#        trace_metrics ${WORKSPACE}/bin/functional.test -test.v \
#            -kubeconfig "${TEST_KUBECONF}" \
#            -traceEnable \
#            -traceTag "Functional-Test-Round-$c" \
#            -storageType "${TEST_PURE_BACKEND}" \
#            -storageSpec "${TEST_STORAGE_SPEC}" \
#            -kubeVersion "${TEST_KUBERNETES_VER}" \
#            -testify.m "${TEST_REGEX}"
#done
#
#${WORKSPACE}/ci/utils/helm-install.sh --uninstall

echo "Done!"
