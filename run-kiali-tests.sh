#!/bin/bash

# abort on any error
set -e

ID="/root/ocp4_setup_ocp4/install_dir"
OC="/root/ocp4_setup_ocp4/oc"
SRC="/tmp/KIALI-GIT"
DORP="podman"

# If you want to test code from different forks and/or branches, set them here
KIALI_FORK="kiali"
KIALI_BRANCH="master"
KIALI_OPERATOR_FORK="kiali"
KIALI_OPERATOR_BRANCH="master"

echo "Create a clean github repo location"
rm -rf /tmp/KIALI-GIT
mkdir -p $SRC

echo "Make sure everything exists"
test -d $ID || (echo "$ID is missing"; exit 1)
test -x $OC || (echo "$OC is missing"; exit 1)
test -d $SRC || (echo "$SRC is missing"; exit 1)
which $DORP > /dev/null || (echo "$DORP is not in the PATH"; exit 1)

echo "Clone github repos to make sure we have the latest tests and scripts"
cd $SRC
git clone --single-branch --branch ${KIALI_BRANCH} git@github.com:${KIALI_FORK}/kiali
git clone --single-branch --branch ${KIALI_OPERATOR_BRANCH} git@github.com:${KIALI_OPERATOR_FORK}/kiali-operator kiali/operator
cd kiali

echo "Log into the cluster"
$OC login -u kubeadmin -p $(cat $ID/auth/kubeadmin-password) https://api.ocp4.local:6443

LOGS_SUBDIR="mazz-basement-tests-$(date +'%Y-%m-%d_%H-%M-%S')"
LOGS_LOCAL="/home/jmazzite/source/mazz-basement/${LOGS_SUBDIR}"
LOGS_GITHUB="https://github.com/jmazzitelli/mazz-basement/tree/master/${LOGS_SUBDIR}"
mkdir -p "${LOGS_LOCAL}"

echo "Running the tests - logs are going here: ${LOGS_LOCAL}"
hack/run-molecule-tests.sh --client-exe "$OC" --color false --test-logs-dir "${LOGS_LOCAL}" > "${LOGS_LOCAL}/results.log"

echo "Committing the logs to github: ${LOGS_GITHUB}"
cd ${LOGS_LOCAL}
git add -A
git commit -m "Test results for ${LOGS_SUBDIR}"
git push

IRC_ROOM="kiali"
echo "Sending IRC notification: #${IRC_ROOM}"
(
echo 'NICK mazz-basement'
echo 'USER mazz-basement 8 * : mazz-basement'
sleep 10
echo "JOIN #${IRC_ROOM}"
sleep 5
echo "PRIVMSG #${IRC_ROOM} : mazz basement tests complete: ${LOGS_GITHUB}"
echo QUIT
) | nc irc.freenode.net 6667
