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

# Build and push the docker image to the repository
docker build -t ${IMG_TAG} ${IMG_DIR}
docker push ${IMG_TAG}

# Cleanup leftovers on our node, but don't fail the script if we cant remove them
sudo docker rmi ${IMG_TAG} || echo "WARNING: Failed to remove docker image!"
