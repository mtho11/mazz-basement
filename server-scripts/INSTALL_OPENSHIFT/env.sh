#!/bin/bash

MASTERS="3"
WORKERS="0"
OPENSHIFT_VERSION="4.4.8"

SCRIPT_DIR="${HOME}/source/ocp4_setup_upi_kvm"
SCRIPT_EXE="${SCRIPT_DIR}/ocp4_setup_upi_kvm.sh"

INSTALL_CMD="${SCRIPT_EXE} -m ${MASTERS} -w ${WORKERS} -O ${OPENSHIFT_VERSION}"
