#!/usr/bin/env bash
set -eou pipefail

# ./run.sh
# ./run.sh --installer=BASH
# ./run.sh --prev-version=0.11.0 --next-version=master

export Red='\033[0;31m'
export Green='\033[0;32m'
export Cyan='\033[0;36m'
export Brown='\033[0;33m'
export NC='\033[0m' # No Color

export KUBEDB_INSTALLER=${KUBEDB_INSTALLER:-HELM}
export KUBEDB_PREVIOUS_VERSION=${KUBEDB_PREVIOUS_VERSION:-0.10.0}
export KUBEDB_NEXT_VERSION=${KUBEDB_NEXT_VERSION:-0.11.0}

# http://redsymbol.net/articles/bash-exit-traps/
function cleanup() {
  exit_status=$?

  if [[ ${exit_status} == 0 ]]; then
    echo -e "${Green}Successful Operator upgrade testing.${NC}"
  else
    echo -e "${Red}Unsuccessful Operator upgrade testing.${NC}"
  fi

  echo -e "${Brown}Cleaning up operator and crds.${NC}"

  helm delete --purge kubedb-operator || true
  helm delete --purge kubedb-catalog || true
  pushd /tmp # to avoid unnecessary backup of crd yamls
  curl -fsSL https://raw.githubusercontent.com/kubedb/cli/${KUBEDB_NEXT_VERSION}/hack/deploy/kubedb.sh | bash -s -- --uninstall --purge || true
  popd
  kubectl delete ns demo || true
}
trap cleanup EXIT

show_help() {
  echo "run.sh - run kubedb upgrade test"
  echo " "
  echo "run.sh [options]"
  echo " "
  echo "options:"
  echo "-h, --help                   show brief help"
  echo "    --installer=HELM         HELM or BASH."
  echo "    --prev-version=0.10.0    kubedb version before upgrade."
  echo "    --next-version=0.11.0    kubedb version after upgrade."
}

while test $# -gt 0; do
  case "$1" in
    -h | --help)
      show_help
      shift
      ;;
    --docker-registry*)
      #      export KUBEDB_DOCKER_REGISTRY=$(echo $1 | sed -e 's/^[^=]*=//g')
      # TODO: support docker-registry
      shift
      ;;
    --installer*)
      export KUBEDB_INSTALLER=$(echo $1 | sed -e 's/^[^=]*=//g')
      shift
      ;;
    --prev-version*)
      export KUBEDB_PREVIOUS_VERSION=$(echo $1 | sed -e 's/^[^=]*=//g')
      shift
      ;;
    --next-version*)
      export KUBEDB_NEXT_VERSION=$(echo $1 | sed -e 's/^[^=]*=//g')
      shift
      ;;
    *)
      show_help
      exit
      ;;
  esac
done

# ----------------------------------[ master ]------------------------------------

master-install() {
  echo -e "${Brown}Installing operator - master${NC}"

  # Clone or update cli repo for helm install
  REPO_ROOT="$GOPATH/src/github.com/kubedb/mongodb"
  CLI_ROOT="$GOPATH/src/github.com/kubedb/cli"
  export KUBEDB_SCRIPT="cat ${CLI_ROOT}/"
  export CLI_BRANCH=${CLI_BRANCH:-master}

  if [[ ! -d ${CLI_ROOT} ]]; then
    echo ">>> Cloning cli repo"
    git clone -b $CLI_BRANCH https://github.com/kubedb/cli.git "${CLI_ROOT}"
  else
    pushd ${CLI_ROOT}
    git fetch --all
    git pull --ff-only origin $CLI_BRANCH #Pull update from remote only if there will be no conflict.
    popd
  fi

  echo ""
  env | sort | grep -e KUBEDB* -e APPSCODE*
  echo ""

  if [[ "${KUBEDB_INSTALLER}" == "BASH" ]]; then
    echo "cat ${CLI_ROOT}/hack/deploy/kubedb.sh | bash"
    pushd ${CLI_ROOT}
    export APPSCODE_ENV=dev
    cat ${CLI_ROOT}/hack/deploy/kubedb.sh | bash
    popd
  elif [[ "$KUBEDB_INSTALLER" == "HELM" ]]; then
    echo "helm install ${CLI_ROOT}/chart/kubedb"
    helm install --name=kubedb-operator ${CLI_ROOT}/chart/kubedb

    TIMER=0
    until kubectl get crd elasticsearchversions.catalog.kubedb.com memcachedversions.catalog.kubedb.com mongodbversions.catalog.kubedb.com mysqlversions.catalog.kubedb.com postgresversions.catalog.kubedb.com redisversions.catalog.kubedb.com || [[ ${TIMER} -eq 60 ]]; do
      sleep 2
      TIMER=$((TIMER + 1))
    done

    helm install --name kubedb-catalog ${CLI_ROOT}/chart/kubedb-catalog
  fi
}

master-uninstall() {
  echo -e "${Brown}Uninstalling operator - master${NC}"

  if [[ "${KUBEDB_INSTALLER}" == "BASH" ]]; then
    curl -fsSL https://raw.githubusercontent.com/kubedb/cli/master/hack/deploy/kubedb.sh | bash -s -- --uninstall
  elif [[ "$KUBEDB_INSTALLER" == "HELM" ]]; then
    helm delete kubedb-operator $1
  fi
}

master-upgrade() {
  echo -e "${Brown}Upgrading operator - master${NC}"

  # Clone or update cli repo for helm install
  if [[ "${KUBEDB_INSTALLER}" == "BASH" ]]; then
    ${KUBEDB_PREVIOUS_VERSION}-uninstall
    master-install
  elif [[ "$KUBEDB_INSTALLER" == "HELM" ]]; then
    REPO_ROOT="$GOPATH/src/github.com/kubedb/mongodb"
    CLI_ROOT="$GOPATH/src/github.com/kubedb/cli"
    export KUBEDB_SCRIPT="cat ${CLI_ROOT}/"
    export CLI_BRANCH=${CLI_BRANCH:-master}

    if [[ ! -d ${CLI_ROOT} ]]; then
      echo ">>> Cloning cli repo"
      git clone -b $CLI_BRANCH https://github.com/kubedb/cli.git "${CLI_ROOT}"
    else
      pushd ${CLI_ROOT}
      git fetch --all
      git pull --ff-only origin $CLI_BRANCH #Pull update from remote only if there will be no conflict.
      popd
    fi

    echo ""
    env | sort | grep -e KUBEDB* -e APPSCODE*
    echo ""

    # helm upgrade --install kubedb-operator appscode/kubedb --version 0.12.0
    helm upgrade --install kubedb-operator ${CLI_ROOT}/chart/kubedb

    TIMER=0
    until kubectl get crd elasticsearchversions.catalog.kubedb.com memcachedversions.catalog.kubedb.com mongodbversions.catalog.kubedb.com mysqlversions.catalog.kubedb.com postgresversions.catalog.kubedb.com redisversions.catalog.kubedb.com || [[ ${TIMER} -eq 60 ]]; do
      sleep 2
      TIMER=$((TIMER + 1))
    done

    helm upgrade --install kubedb-catalog ${CLI_ROOT}/chart/kubedb-catalog
  fi
}

# ----------------------------------[ 0.10.0 ]------------------------------------

0.10.0-install() {
  echo -e "${Brown}Installing operator - 0.10.0${NC}"

  if [[ "${KUBEDB_INSTALLER}" == "BASH" ]]; then
    curl -fsSL https://raw.githubusercontent.com/kubedb/cli/0.10.0/hack/deploy/kubedb.sh | bash
  elif [[ "$KUBEDB_INSTALLER" == "HELM" ]]; then
    helm repo add appscode https://charts.appscode.com/stable/
    helm repo update
    helm install appscode/kubedb --name kubedb-operator --version 0.10.0 \
      --namespace kube-system

    TIMER=0
    until kubectl get crd elasticsearchversions.catalog.kubedb.com memcachedversions.catalog.kubedb.com mongodbversions.catalog.kubedb.com mysqlversions.catalog.kubedb.com postgresversions.catalog.kubedb.com redisversions.catalog.kubedb.com || [[ ${TIMER} -eq 60 ]]; do
      sleep 2
      TIMER=$((TIMER + 1))
    done

    helm install appscode/kubedb-catalog --name kubedb-catalog --version 0.10.0 \
      --namespace kube-system
  fi
}

0.10.0-uninstall() {
  echo -e "${Brown}Uninstalling operator - 0.10.0${NC}"
  if [[ "${KUBEDB_INSTALLER}" == "BASH" ]]; then
    curl -fsSL https://raw.githubusercontent.com/kubedb/cli/0.10.0/hack/deploy/kubedb.sh | bash -s -- --uninstall
  elif [[ "$KUBEDB_INSTALLER" == "HELM" ]]; then
    helm delete kubedb-operator $1
  fi
}

0.10.0-upgrade() {
  echo -e "${Brown}Upgrading operator - 0.10.0${NC}"
  if [[ "${KUBEDB_INSTALLER}" == "BASH" ]]; then
    ${KUBEDB_PREVIOUS_VERSION}-uninstall
    0.10.0-install
  elif [[ "$KUBEDB_INSTALLER" == "HELM" ]]; then
    # helm upgrade --install kubedb-operator appscode/kubedb --version 0.10.0
    helm upgrade kubedb-operator appscode/kubedb --version 0.10.0
  fi
}

# ----------------------------------[ 0.11.0 ]------------------------------------

0.11.0-install() {
  echo -e "${Brown}Installing operator - 0.11.0${NC}"

  if [[ "${KUBEDB_INSTALLER}" == "BASH" ]]; then
    curl -fsSL https://raw.githubusercontent.com/kubedb/cli/0.11.0/hack/deploy/kubedb.sh | bash
  elif [[ "$KUBEDB_INSTALLER" == "HELM" ]]; then
    helm repo add appscode https://charts.appscode.com/stable/
    helm repo update
    helm install appscode/kubedb --name kubedb-operator --version 0.11.0 \
      --namespace kube-system

    TIMER=0
    until kubectl get crd elasticsearchversions.catalog.kubedb.com memcachedversions.catalog.kubedb.com mongodbversions.catalog.kubedb.com mysqlversions.catalog.kubedb.com postgresversions.catalog.kubedb.com redisversions.catalog.kubedb.com || [[ ${TIMER} -eq 60 ]]; do
      sleep 2
      TIMER=$((TIMER + 1))
    done

    helm install appscode/kubedb-catalog --name kubedb-catalog --version 0.11.0 \
      --namespace kube-system
  fi
}

0.11.0-uninstall() {
  echo -e "${Brown}Uninstalling operator - 0.11.0${NC}"

  if [[ "${KUBEDB_INSTALLER}" == "BASH" ]]; then
    curl -fsSL https://raw.githubusercontent.com/kubedb/cli/0.11.0/hack/deploy/kubedb.sh | bash -s -- --uninstall
  elif [[ "$KUBEDB_INSTALLER" == "HELM" ]]; then
    helm delete kubedb-operator $1
  fi
}

0.11.0-upgrade() {
  echo -e "${Brown}Upgrading operator - 0.11.0${NC}"

  if [[ "${KUBEDB_INSTALLER}" == "BASH" ]]; then
    ${KUBEDB_PREVIOUS_VERSION}-uninstall
    0.11.0-install
  elif [[ "$KUBEDB_INSTALLER" == "HELM" ]]; then
    # helm upgrade --install kubedb-operator appscode/kubedb --version 0.11.0
    helm upgrade kubedb-operator appscode/kubedb --version 0.11.0

    TIMER=0
    until kubectl get crd elasticsearchversions.catalog.kubedb.com memcachedversions.catalog.kubedb.com mongodbversions.catalog.kubedb.com mysqlversions.catalog.kubedb.com postgresversions.catalog.kubedb.com redisversions.catalog.kubedb.com || [[ ${TIMER} -eq 60 ]]; do
      sleep 2
      TIMER=$((TIMER + 1))
    done

    helm upgrade --install kubedb-catalog appscode/kubedb-catalog --version 0.11.0 --namespace kube-system

  fi
}

# ----------------------------------[ 0.12.0 ]------------------------------------

0.12.0-install() {
  echo -e "${Brown}Installing operator - 0.12.0${NC}"

  if [[ "${KUBEDB_INSTALLER}" == "BASH" ]]; then
    curl -fsSL https://raw.githubusercontent.com/kubedb/cli/0.12.0/hack/deploy/kubedb.sh | bash
  elif [[ "$KUBEDB_INSTALLER" == "HELM" ]]; then
    helm repo add appscode https://charts.appscode.com/stable/
    helm repo update
    helm install appscode/kubedb --name kubedb-operator --version 0.12.0 \
      --namespace kube-system

    TIMER=0
    until kubectl get crd elasticsearchversions.catalog.kubedb.com memcachedversions.catalog.kubedb.com mongodbversions.catalog.kubedb.com mysqlversions.catalog.kubedb.com postgresversions.catalog.kubedb.com redisversions.catalog.kubedb.com || [[ ${TIMER} -eq 60 ]]; do
      sleep 2
      TIMER=$((TIMER + 1))
    done

    helm install appscode/kubedb-catalog --name kubedb-catalog --version 0.12.0 \
      --namespace kube-system
  fi
}

0.12.0-uninstall() {
  echo -e "${Brown}Uninstalling operator - 0.12.0${NC}"

  if [[ "${KUBEDB_INSTALLER}" == "BASH" ]]; then
    curl -fsSL https://raw.githubusercontent.com/kubedb/cli/0.12.0/hack/deploy/kubedb.sh | bash -s -- --uninstall
  elif [[ "$KUBEDB_INSTALLER" == "HELM" ]]; then
    helm delete kubedb-operator $1
  fi
}

0.12.0-upgrade() {
  echo -e "${Brown}Upgrading operator - 0.12.0${NC}"
  if [[ "${KUBEDB_INSTALLER}" == "BASH" ]]; then
    ${KUBEDB_PREVIOUS_VERSION}-uninstall
    0.12.0-install
  elif [[ "$KUBEDB_INSTALLER" == "HELM" ]]; then
    # helm upgrade --install kubedb-operator appscode/kubedb --version 0.12.0
    helm upgrade kubedb-operator appscode/kubedb --version 0.12.0

    TIMER=0
    until kubectl get crd elasticsearchversions.catalog.kubedb.com memcachedversions.catalog.kubedb.com mongodbversions.catalog.kubedb.com mysqlversions.catalog.kubedb.com postgresversions.catalog.kubedb.com redisversions.catalog.kubedb.com || [[ ${TIMER} -eq 60 ]]; do
      sleep 2
      TIMER=$((TIMER + 1))
    done

    helm upgrade --install kubedb-catalog appscode/kubedb-catalog --version 0.12.0 --namespace kube-system

  fi
}

echo -e "${Cyan}Installing Previous version operator: ${KUBEDB_PREVIOUS_VERSION}${NC}"

${KUBEDB_PREVIOUS_VERSION}-install

./before-upgrade.sh

echo -e "${Cyan}Upgrading to Next version operator: ${KUBEDB_NEXT_VERSION}${NC}"

${KUBEDB_NEXT_VERSION}-upgrade

./after-upgrade.sh
