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

# Set some default values if they were not specified
IMAGE_REGISTRY=${IMAGE_REGISTRY:-pc2-dtr.dev.purestorage.com}
TEST_USER=${TEST_USER:-jenkins}
TEST_PASS=${TEST_PASS:-jenkins-pass}
TEST_ORG=${TEST_ORG:-purestorage}
IMAGE_REPO=${IMAGE_REPO:-purestorage}
TEST_IMAGE_NAME=${TEST_IMAGE_NAME:-k8s}
TEST_ID=${TEST_ID:-k8s-${HOST_USER}-$(uuidgen | tr -d - | cut -c1-5 | tr -d '\n')}
PURE_HELM_VALUE_FILE=${WORKSPACE}/plugin-values.yaml
TEST_PURE_BACKEND=${TEST_PURE_BACKEND:-"pure-fa-iscsi"}
NSM_DEV_TOOLS=${NSM_DEV_TOOLS:-/opt/nsm-dev-tools/}
TEST_CLUSTER_NAME=${TEST_CLUSTER_NAME:-${TEST_ID}}
TEST_CSI_SANITY_VERSION=${TEST_CSI_SANITY_VERSION:-"v1.1.0"}
# K8S namespace cannot have hyphen at this time so removing it
PURE_K8S_NAMESPACE=${PURE_K8S_NAMESPACE:-$(echo ${TEST_ID} | sed 's/-//g')}

export OS_CLOUD=${OS_CLOUD:-c14}

TEST_PURE_CONF_DIR=${NSM_DEV_TOOLS}/secrets/test-envs/${OS_CLOUD}
cp -f ${TEST_PURE_CONF_DIR}/${TEST_PURE_BACKEND}-values.yaml ${PURE_HELM_VALUE_FILE}

# Stash away a copy of our test environment vars, makes it easy to reproduce runs
# and is super helpful for scripts further down the chain to use them.
cat <<EOF > ${WORKSPACE}/test-env.sh
export IMAGE_REGISTRY=${IMAGE_REGISTRY}
export TEST_USER=${TEST_USER}
export TEST_PASS=${TEST_PASS}
export TEST_ORG=${TEST_ORG}
export IMAGE_REPO=${IMAGE_REPO}
export TEST_IMAGE_NAME=${TEST_IMAGE_NAME}
export TEST_ID=${TEST_ID}
export PURE_HELM_VALUE_FILE=${PURE_HELM_VALUE_FILE}
export TEST_PURE_BACKEND=${TEST_PURE_BACKEND}
export NSM_DEV_TOOLS=${NSM_DEV_TOOLS}
export TEST_CLUSTER_NAME=${TEST_CLUSTER_NAME}
export PURE_K8S_NAMESPACE=${PURE_K8S_NAMESPACE}
export TEST_CSI_SANITY_VERSION=${TEST_CSI_SANITY_VERSION}
EOF

# Setup OpenStack credentials and access info when they are in the environment
for OS_OPT in $(env | grep "OS_"); do
    echo "export ${OS_OPT}" >> ${WORKSPACE}/test-env.sh
done

sudo docker login -u ${TEST_USER} -p ${TEST_PASS} ${IMAGE_REGISTRY}
