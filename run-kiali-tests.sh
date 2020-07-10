#!/bin/bash

while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -dorp|--docker-or-podman)     DORP="$2";                  shift;shift; ;;
    -ir|--irc-room)               IRC_ROOM="$2";              shift;shift; ;;
    -kf|--kiali-fork)             KIALI_FORK="$2";            shift;shift; ;;
    -kb|--kiali-branch)           KIALI_BRANCH="$2";          shift;shift; ;;
    -kof|--kiali-operator-fork)   KIALI_OPERATOR_FORK="$2";   shift;shift; ;;
    -kob|--kiali-operator-branch) KIALI_OPERATOR_BRANCH="$2"; shift;shift; ;;
    *) echo "Unknown argument: [$key]. Aborting."; exit 1 ;;
  esac
done

# abort on any error
set -e

ID="/root/ocp4_setup_ocp4/install_dir"
OC="/root/ocp4_setup_ocp4/oc"
SRC="/tmp/KIALI-GIT"
DORP="${DORP:-podman}"

# if you want to test code from different forks and/or branches, set them here
KIALI_FORK="${KIALI_FORK:-kiali}"
KIALI_BRANCH="${KIALI_BRANCH:-master}"
KIALI_OPERATOR_FORK="${KIALI_OPERATOR_FORK:-kiali}"
KIALI_OPERATOR_BRANCH="${KIALI_OPERATOR_BRANCH:-master}"

# the local github repo where the logs are to be stored
LOGS_SUBDIR="mazz-basement-tests-$(date +'%Y-%m-%d_%H-%M-%S')"
LOGS_LOCAL="/home/jmazzite/source/mazz-basement/${LOGS_SUBDIR}"
LOGS_GITHUB="https://github.com/jmazzitelli/mazz-basement/tree/master/${LOGS_SUBDIR}"
LOGS_LOCAL_RESULTS="${LOGS_LOCAL}/results.log"
LOGS_GITHUB_RESULTS="https://github.com/jmazzitelli/mazz-basement/tree/master/${LOGS_SUBDIR}/results.log"

# the freenode IRC room where notifications are to be sent
IRC_ROOM="${IRC_ROOM:-kiali}"

cat <<EOM
=== CRON JOB SETTINGS ===
DORP=$DORP
KIALI_FORK=$KIALI_FORK
KIALI_BRANCH=$KIALI_BRANCH
KIALI_OPERATOR_FORK=$KIALI_OPERATOR_FORK
KIALI_OPERATOR_BRANCH=$KIALI_OPERATOR_BRANCH
LOGS_SUBDIR=$LOGS_SUBDIR
LOGS_LOCAL=$LOGS_LOCAL
LOGS_GITHUB=$LOGS_GITHUB
LOGS_LOCAL_RESULTS=$LOGS_LOCAL_RESULTS
LOGS_GITHUB_RESULTS=$LOGS_GITHUB_RESULTS
IRC_ROOM=$IRC_ROOM
=== CRON JOB SETTINGS ===
EOM

echo "Cleaning any residual Kiali installs that might be hanging around"

delete_namespace_resources() {
  local selector_expression="$1"
  echo "Removing namespace-scoped resources with selector [${selector_expression}]..."
  for r in $($OC get --ignore-not-found=true all,secrets,sa,configmaps,deployments,roles,rolebindings,ingresses --selector="${selector_expression}" --all-namespaces -o custom-columns=NS:.metadata.namespace,K:.kind,N:.metadata.name --no-headers | sed 's/  */:/g')
  do
    local res_namespace=$(echo $r | cut -d: -f1)
    local res_kind=$(echo $r | cut -d: -f2)
    local res_name=$(echo $r | cut -d: -f3)
    $OC delete --ignore-not-found=true ${res_kind} ${res_name} -n ${res_namespace}
  done
}

delete_cluster_resources() {
  local selector_expression="$1"
  echo "Removing cluster-scoped resources with selector [${selector_expression}]..."
  for r in $($OC get --ignore-not-found=true clusterroles,clusterrolebindings,customresourcedefinitions,oauthclients.oauth.openshift.io,consolelinks.console.openshift.io --selector="${selector_expression}" --all-namespaces -o custom-columns=K:.kind,N:.metadata.name --no-headers | sed 's/  */:/g')
  do
    local res_kind=$(echo $r | cut -d: -f1)
    local res_name=$(echo $r | cut -d: -f2)
    $OC delete --ignore-not-found=true ${res_kind} ${res_name}
  done
}

echo "Remove Kiali CRs..."
for k in $($OC get kiali --ignore-not-found=true --all-namespaces -o custom-columns=NS:.metadata.namespace,N:.metadata.name --no-headers | sed 's/  */:/g')
do
  cr_namespace=$(echo $k | cut -d: -f1)
  cr_name=$(echo $k | cut -d: -f2)
  $OC delete --ignore-not-found=true kiali ${cr_name} -n ${cr_namespace}
done

delete_namespace_resources "app=kiali"
delete_cluster_resources "app=kiali"
delete_namespace_resources "app=kiali-operator"
delete_cluster_resources "app=kiali-operator"

echo "Create a clean github repo location"
rm -rf /tmp/KIALI-GIT
mkdir -p ${SRC}

echo "Make sure everything exists"
test -d $ID || (echo "$ID is missing"; exit 1)
test -x $OC || (echo "$OC is missing"; exit 1)
test -d $SRC || (echo "$SRC is missing"; exit 1)
which $DORP > /dev/null || (echo "$DORP is not in the PATH"; exit 1)

echo "Clone github repos to make sure we have the latest tests and scripts"
cd ${SRC}
git clone --single-branch --branch ${KIALI_BRANCH} git@github.com:${KIALI_FORK}/kiali
git clone --single-branch --branch ${KIALI_OPERATOR_BRANCH} git@github.com:${KIALI_OPERATOR_FORK}/kiali-operator kiali/operator
cd kiali

echo "Log into the cluster"
$OC login -u kubeadmin -p $(cat $ID/auth/kubeadmin-password) https://api.ocp4.local:6443

mkdir -p "${LOGS_LOCAL}"

echo "Running the tests - logs are going here: ${LOGS_LOCAL}"
hack/run-molecule-tests.sh --client-exe "$OC" --color false --test-logs-dir "${LOGS_LOCAL}" > "${LOGS_LOCAL_RESULTS}"

echo "Committing the logs to github: ${LOGS_GITHUB}"
cd ${LOGS_LOCAL}
git add -A
git commit -m "Test results for ${LOGS_SUBDIR}"
git push

# determine what message to send to IRC based on test results
if grep FAILURE "${LOGS_LOCAL_RESULTS}"; then
  irc_msg="a FAILURE occurred in one or more tests"
else
  irc_msg="all tests passed"
fi
irc_msg="mazz basement tests complete [${irc_msg}]: ${LOGS_GITHUB_RESULTS} (test logs directory: ${LOGS_GITHUB})"

echo "Sending IRC notification to room [#${IRC_ROOM}]. msg=${irc_msg}"
(
echo 'NICK mazz-basement'
echo 'USER mazz-basement 8 * : mazz-basement'
sleep 10
echo "JOIN #${IRC_ROOM}"
sleep 5
echo "PRIVMSG #${IRC_ROOM} : ${irc_msg}"
echo QUIT
) | nc irc.freenode.net 6667
