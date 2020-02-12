#!/usr/bin/env bash

set -xe

WORKSPACE=${WORKSPACE:-$(pwd)}

if [[ ! -f "${WORKSPACE}/test-env.sh" ]]; then
    ${WORKSPACE}/ci/setup-test-env.sh
fi
. ${WORKSPACE}/test-env.sh

IMG_NAME="pure-csi-driver"
IMG_TAG=$(${NSM_DEV_TOOLS}/scripts/docker/generate-purestorage-tag-name.sh ${IMG_NAME} ${WORKSPACE})

IMG_DIR=${WORKSPACE}/operator-csi-plugin
HELM_DIR=${IMG_DIR}/..
mkdir -p ${IMG_DIR}/helm-charts
cp -r ${HELM_DIR}/pure-csi ${IMG_DIR}/helm-charts

docker build -t ${IMG_TAG} ${IMG_DIR}
docker push ${IMG_TAG}
