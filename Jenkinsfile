@Library("pso-jenkins-library") _

//////////////////////////////////////////////////////////////////////////////
// Helper functions


class Constants {
    static final String GO_REPO_ROOT = "/go/src/pso.purestorage.com/pure-csi-driver"
    static final String NODE_LABEL_NSTK_LP_DEFAULT = "newstack-launchpad"
    static final String NODE_LABEL_NSTK_LP_FC = "newstack-launchpad-fc"
}

// Select a Repo to add test for
def addTest = selectRepo(Constants.GO_REPO_ROOT, "4.0.9-731f940f")
def addTestWithAllocator = selectRepoWithResource(Constants.GO_REPO_ROOT, "4.0.9-731f940f")

def deleteTestCluster(boolean passed) {
    if (passed || params.DELETE_CLUSTER_ON_ERROR) {
        try {
            sh '${NSM_SRC_DIR}/scripts/cluster/delete-cluster.sh'
        }
        catch (all) {
        // Delete is best effort hence catching all exceptions.
        }
    }
    else {
        echo "Keeping the cluster around for troubleshooting."
    }
}

def archiveTestArtifacts(String name) {
    if (params.UPLOAD_TO_GRAYLOG) {
        sh '${NSM_SRC_DIR}/scripts/logging/upload-jenkins-task-logs.sh'
    }

    artifacts = [
            'bin/',
            'logs/',
            'test-env.sh',
            'cluster-inventory.yaml',
            'kube.conf',
            'plugin-values.yaml',
            'pure.json',
    ]

    sh "mkdir -p ${name}/"
    for (int i = 0; i < artifacts.size(); i++) {
        sh "mv ./${artifacts[i]} ${name}/ || echo unable to copy file, ignoring"
    }
    archiveArtifacts allowEmptyArchive: true, artifacts: "${name}/**/*", defaultExcludes: false, fingerprint: true
}

//////////////////////////////////////////////////////////////////////////////
// Add Build tasks

def buildTasks = [:]

addTest(Constants.NODE_LABEL_NSTK_LP_DEFAULT, buildTasks, "Build", 15) {
    echo "build stage to build an operator image"
    sh "./ci/build_and_push_operator_image.sh"
}



//////////////////////////////////////////////////////////////////////////////
// Add Functional Tests

// Run a stable smoke test on a single node cluster

def osType = "ubuntu-16.04"
def k8sVersion = "1.15"
def backendType = "pure-fa-iscsi"

def functionalTestTasks = [:]

addTestWithAllocator(Constants.NODE_LABEL_NSTK_LP_DEFAULT, functionalTestTasks, "helm install", 30, {
    withEnv(["TEST_CLUSTER_IMAGE=k8s-base-${osType}",
             "TEST_PURE_BACKEND=${backendType}",
             "TEST_CLUSTER_SIZE=1",
             "KUBERNETES_VERSION=${k8sVersion}"]) {
        def passed = false
        try {
            sh './ci/run-functional-tests.sh'
            passed = true
        }
        finally {
            deleteTestCluster(passed)
            archiveTestArtifacts("helm install")
        }
    }
}, {
    withEnv(["TEST_CLUSTER_IMAGE=k8s-base-${osType}",
             "TEST_PURE_BACKEND=${backendType}",
             "TEST_CLUSTER_SIZE=1",
             "KUBERNETES_VERSION=${k8sVersion}"]) {
        sh './ci/provision-cluster.sh'
    }
})


//addTest(Constants.NODE_LABEL_NSTK_LP_DEFAULT, functionalTestTasks, "Vulnerability Tests", 30) {
//    sh "./ci/run-vuln-tests.sh"
//}

//k8sVersion = "1.15"
addTestWithAllocator(Constants.NODE_LABEL_NSTK_LP_DEFAULT, functionalTestTasks, "operator install", 30, {
    withEnv(["TEST_CLUSTER_IMAGE=k8s-base-${osType}",
             "TEST_PURE_BACKEND=${backendType}",
             "TEST_CLUSTER_SIZE=1",
             "KUBERNETES_VERSION=${k8sVersion}"]) {
        def passed = false
        try {
            sh './ci/run-functional-tests.sh'
            passed = true
        }
        finally {
            deleteTestCluster(passed)
            archiveTestArtifacts("operator install")
        }
    }
}, {
    withEnv(["TEST_CLUSTER_IMAGE=k8s-base-${osType}",
             "TEST_PURE_BACKEND=${backendType}",
             "TEST_CLUSTER_SIZE=1",
             "KUBERNETES_VERSION=${k8sVersion}"]) {
        sh './ci/provision-cluster.sh'
    }
})


//////////////////////////////////////////////////////////////////////////////
// Add Compatibility Tests

// Run a full spread of our functional test matrix, stage 2 should weed out
// any obvious issues with the code. This is checking compatibility on a bunch of
// platforms. Its still pretty lightweight testing though (single-pass over functional
// test suite).

//def compatibilityMatrix = [
//    "ose": [
//        "versions": ["3.11"],
//        "os": ["rhel-7"],
//	    "spec": ["flex"],
//        "backends": ["pure-fa-iscsi-fb-nfs"],
//        "versionEnvVar": "OPENSHIFT_VERSION",
//        "testScript": "run-openshift-functional-tests.sh",
//        "imagePrefix": "ose-base",
//        "additionalEnv": ["ANSIBLE_PLAYBOOK_VERSION=129-1"]
//    ],
//    "k8s": [
//        "versions": ["1.15", "1.16"],
//        "spec": [ "csi", "flex"],
//        "os": [
//                "ubuntu-16.04",
//                "ubuntu-18.04",
//                "rhel-7"
//        ],
//        "backends": [
//                "pure-fa-iscsi-fb-nfs",
//                "pure-fa-fc-fb-nfs"
//        ],
//        "versionEnvVar": "KUBERNETES_VERSION",
//        "testScript": "run-functional-tests.sh",
//        "imagePrefix": "k8s-base"
//    ]
//]
//
//def compatibilityTestTasks = [:]
//
//for (kv in mapToList(compatibilityMatrix)) {
//    def co = kv[0]
//    def opts = kv[1]
//
//    def scriptToRun = opts["testScript"]
//    def versionEnvVar = opts["versionEnvVar"]
//    def imagePrefix = opts["imagePrefix"]
//
//    for (int idxOS = 0; idxOS < opts["os"].size(); idxOS++) {
//        def os = opts["os"][idxOS]
//        for (int idxBackend = 0; idxBackend < opts["backends"].size(); idxBackend++) {
//            def backend = opts["backends"][idxBackend]
//            for (int idxVersion = 0; idxVersion < opts["versions"].size(); idxVersion++) {
//                for (int idxSpec = 0; idxSpec < opts["spec"].size(); idxSpec++) {
//                    def version = opts["versions"][idxVersion]
//                    def spec = opts["spec"][idxSpec]
//                    def testName = "${co}-${spec}-${version}-${os}-${backend}"
//
//                    def nodeLabel = Constants.NODE_LABEL_NSTK_LP_DEFAULT
//                    if (backend.contains("fa-fc")) {
//                        nodeLabel = Constants.NODE_LABEL_NSTK_LP_FC
//                    }
//
//                    def envVars = ["TEST_CLUSTER_IMAGE=${imagePrefix}-${os}",
//                                 "TEST_PURE_BACKEND=${backend}",
//                                 "TEST_STORAGE_SPEC=${spec}",
//                                 "TEST_CLUSTER_SIZE=3",
//                                 "${versionEnvVar}=${version}"];
//                    
//                    if (opts.containsKey("additionalEnv")) {
//                        envVars.add(opts["additionalEnv"][idxVersion])
//                    }
//
//                    addTestWithAllocator(nodeLabel, compatibilityTestTasks, testName, 240, {
//                        withEnv(envVars) {
//                            def passed = false
//                            try {
//                                sh "./ci/${scriptToRun}"
//                                passed = true
//                            }
//                            finally {
//                                deleteTestCluster(passed)
//                                archiveTestArtifacts(testName)
//                            }
//                        }
//                    }, {
//                        withEnv(envVars) {
//                            sh './ci/provision-cluster.sh'
//                        }
//                    })
//            	}
//            }
//        }
//    }
//}

//////////////////////////////////////////////////////////////////////////////
// Setup some properties/parameters for the build

def parametersToAdd = getParametersForTestStage(buildTasks, "STAGE_0", 'Run Stage 0') +
        getParametersForTestStage(functionalTestTasks, "STAGE_1", "Run Stage 1")
        //getParametersForTestStage(compatibilityTestTasks, "STAGE_3", "Run Stage 3") +
        //booleanParam(defaultValue: true, description: "Delete cluster on error", name: "DELETE_CLUSTER_ON_ERROR") +
        //booleanParam(defaultValue: true, description: "Upload log to graylog", name: "UPLOAD_TO_GRAYLOG") +
        //booleanParam(defaultValue: false, description:"Only re-run unsuccessful steps in the last build", name: "RE_RUN_LAST_FAILED_STEPS_ONLY")


def pipelineProperties = [
        buildDiscarder(logRotator(artifactDaysToKeepStr: '', artifactNumToKeepStr: '', daysToKeepStr: '30', numToKeepStr: '20')),
        overrideIndexTriggers(false),
        parameters(parametersToAdd),
]

addMasterCron(pipelineProperties, '0 13 * * *')
properties(pipelineProperties)

// ------ Only run failed stages if specified -----
if (params.RE_RUN_LAST_FAILED_STEPS_ONLY) {
    def prevFailedSteps = getPreviousFailedSteps()

    // Only run last failed steps
    functionalTestTasks = filterTestsByNames(prevFailedSteps, functionalTestTasks)
    compatibilityTestTasks = filterTestsByNames(prevFailedSteps, compatibilityTestTasks)

    echo "Will re-run ${functionalTestTasks.size()} functionalTestTasks, ${compatibilityTestTasks.size()} compatibilityTestTasks"
}

//////////////////////////////////////////////////////////////////////////////
// Actually run the tasks

// TODO: This is where we can add some logic in for doing sub sets of these tests
// for PR's versus say a timer on a stable branch.

if (params.STAGE_0) {
    stage("Stage 0") {
        parallel buildTasks
    }
}

if (params.STAGE_1) {
    stage("Stage 1") {
        parallel functionalTestTasks
    }
}

//////////////////////////////////////////////////////////////////////////////
// Run compatibility tests, break down to several stages, each runs tests against
// a certain OS (Ubuntu, Red Hat 7 etc)
//if (params.STAGE_3) {
//    for (os in compatibilityMatrix["k8s"]["os"]) {
//
//        def compatibilityTestSuite = filterTestsContainName(os, compatibilityTestTasks)
//
//        stage("Test " + os) {
//            parallel compatibilityTestSuite
//        }
//    }
//}

// Future stages can add >1 iteration, more exotic backend configs, larger clusters, failure testing, etc
