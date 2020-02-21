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

WORKSPACE=${WORKSPACE:-$(pwd)}

if [[ -f "${WORKSPACE}/test-env.sh" ]]; then
    . ${WORKSPACE}/test-env.sh
fi

if [[ "${TEST_STORAGE_SPEC}" == "csi" ]]; then
    PLUGIN_HELM_CHART_NAME=${PLUGIN_HELM_CHART_NAME:-${WORKSPACE}/pure-csi}
else
    PLUGIN_HELM_CHART_NAME=${PLUGIN_HELM_CHART_NAME:-${WORKSPACE}/pure-k8s-plugin}
fi
PURE_K8S_NAMESPACE=${PURE_K8S_NAMESPACE:-k8s${TEST_ID}}
PURE_K8S_IMG_TAG=${PURE_K8S_IMG_TAG:-purestorage/k8s:latest}

ORCHESTRATOR_NAME=${ORCHESTRATOR_NAME:-k8s}
FLEX_PATH=${FLEX_PATH:-"/usr/libexec/kubernetes/kubelet-plugins/volume/exec/"}

# https://github.com/openshift/openshift-ansible/pull/8964/files flexpath on Atomic is different since 3.10
if [[ "${ORCHESTRATOR_NAME}" == "openshift" && "${OPENSHIFT_ATOMIC}" == "true" ]]; then
    if [[ "${OPENSHIFT_VERSION}" == "3.10" || "${OPENSHIFT_VERSION}" == "3.11" ]]; then
        FLEX_PATH="/etc/origin/kubelet-plugins/volume/exec/"
    fi
fi

TEST_IMAGE_NAME=$(echo "${PURE_K8S_IMG_TAG}" | cut -d ':' -f 1)
TEST_IMAGE_TAG=$(echo "${PURE_K8S_IMG_TAG}" | cut -d ':' -f 2)

PURE_HELM_VALUE_FILE=${PURE_HELM_VALUE_FILE:-${WORKSPACE}/plugin-values.yaml}

DEFAULT_FS_TYPE=${TEST_DEFAULT_FS_TYPE:-"xfs"}
DEFAULT_FS_OPT=${TEST_DEFAULT_FS_OPT:-"-q"}
DEFAULT_MOUNT_OPT=${TEST_DEFALUT_MOUNT_OPT:-""}

PLUGIN_INSTANCE_NAME=pure-plugin
# TODO: Image should be generated from the master helm-repo contents 
PSO_OPERATOR_IMAGE_NAME=${PSO_OPERATOR_IMAGE_NAME:-pso-operator}
PSO_OPERATOR_IMG_TAG=${PSO_OPERATOR_IMG_TAG:-$(${NSM_DEV_TOOLS}/scripts/docker/generate-purestorage-tag-name.sh ${PSO_OPERATOR_IMAGE_NAME} ${WORKSPACE})}
#PSO_OPERATOR_IMG_TAG=pc2-dtr.dev.purestorage.com/purestorage/pso-operator:v0.0.3

source ${NSM_DEV_TOOLS}/scripts/cluster/cluster-utils.sh
if [[ "$1" == "--install" && ${ORCHESTRATOR_NAME} == "openshift" && "${OPENSHIFT_VERSION}" == "3.11" ]]; then

    PARAMS="\nimage:\n  name: ${TEST_IMAGE_NAME}\n  tag: ${TEST_IMAGE_TAG}\n"
    PARAMS+="storageclass:\n  isPureDefault: true\n"
    PARAMS+="namespace:\n  pure: ${PURE_K8S_NAMESPACE}\n"
    PARAMS+="orchestrator:\n  name: ${ORCHESTRATOR_NAME}\n  ${ORCHESTRATOR_NAME}:\n    flexPath: ${FLEX_PATH}\n"
    PARAMS+="flexPath: ${FLEX_PATH}\n"
    PARAMS+="flasharray:\n  defaultFSType: ${DEFAULT_FS_TYPE}\n  defaultFSOpt: ${DEFAULT_FS_OPT}\n  defaultMountOpt: ${DEFAULT_MOUNT_OPT}"
    VALUESFILE=${NSM_DEV_TOOLS}/scripts/k8s/helm/values.yaml

    run_on_cluster_nodes masters "echo -e \"${PARAMS}\" >> ${VALUESFILE}"
    # Though it would be better to install PSO in its own namespace different from the NSM-namespace our tests (esp snapshot exec commands)
    # will fail because they look for the provisioner in the nsm-namespace. So here we are installing PSO Operator in the NSM namespace
    run_on_cluster_nodes masters "${NSM_DEV_TOOLS}/scripts/k8s/helm/operator-install.sh --image=${PSO_OPERATOR_IMG_TAG} --namespace=${PURE_K8S_NAMESPACE} -f ${VALUESFILE}"
elif [ "$1" == "--install" ]; then
    # On Openshift 3.10 and 3.11 add annotation to the pure-flex install namespace so that flex-driver is scheduled on all nodes
    # Otherwise PSO will not work for pods in default namespace
    if [[ "${ORCHESTRATOR_NAME}" == "openshift" ]]; then
            run_on_cluster_nodes masters "oc adm new-project ${PURE_K8S_NAMESPACE} --node-selector=\"\""
    fi

    if [[ ${ORCHESTRATOR_NAME} == "k8s" ]]; then
        # Helm 3 is updated to not create namepsace during install
        kubectl create namespace ${PURE_K8S_NAMESPACE}
    fi

    # install from local not from repo
    helm install ${PLUGIN_INSTANCE_NAME} ${PLUGIN_HELM_CHART_NAME} \
        --namespace=${PURE_K8S_NAMESPACE} \
        -f ${PURE_HELM_VALUE_FILE} \
        --set storageclass.isPureDefault=true \
        --set image.name="${TEST_IMAGE_NAME}" \
        --set image.tag="${TEST_IMAGE_TAG}" \
        --set namespace.pure="${PURE_K8S_NAMESPACE}" \
        --set orchestrator.name="${ORCHESTRATOR_NAME}" \
        --set orchestrator.${ORCHESTRATOR_NAME}.flexPath="${FLEX_PATH}" \
        --set flexPath="${FLEX_PATH}" \
        --set flasharray.defaultFSType="${DEFAULT_FS_TYPE}" \
        --set flasharray.defaultFSOpt="${DEFAULT_FS_OPT}" \
        --set flasharray.defaultMountOpt="${DEFAULT_MOUNT_OPT}" \
        --debug \
        --wait
elif [ "$1" == "--uninstall" ]; then
    if [[ ${ORCHESTRATOR_NAME} == "k8s" || "${OPENSHIFT_VERSION}" != "3.11" ]]; then
        helm uninstall ${PLUGIN_INSTANCE_NAME} --namespace=${PURE_K8S_NAMESPACE}
        kubectl delete namespace ${PURE_K8S_NAMESPACE}
    fi
else
    echo "Unsupported operation"
    exit 1
fi
sleep 5
