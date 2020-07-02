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
IRC_ROOM=$IRC_ROOM
=== CRON JOB SETTINGS ===
EOM

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
hack/run-molecule-tests.sh --client-exe "$OC" --color false --test-logs-dir "${LOGS_LOCAL}" > "${LOGS_LOCAL}/results.log"

echo "Committing the logs to github: ${LOGS_GITHUB}"
cd ${LOGS_LOCAL}
git add -A
git commit -m "Test results for ${LOGS_SUBDIR}"
git push

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
