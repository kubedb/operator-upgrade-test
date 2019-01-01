#!/usr/bin/env bash
set -eou pipefail

set -x

export KUBEDB_INSTALLER=${KUBEDB_INSTALLER:-HELM}
export KUBEDB_PREVIOUS_VERSION=${KUBEDB_PREVIOUS_VERSION:-0.8.0}
export KUBEDB_NEXT_VERSION=${KUBEDB_NEXT_VERSION:-0.9.0}

0.8.0-install() {
  if [[ "${KUBEDB_INSTALLER}" == "BASH" ]]; then
    curl -fsSL https://raw.githubusercontent.com/kubedb/cli/0.8.0/hack/deploy/kubedb.sh | bash
  elif [[ "$KUBEDB_INSTALLER" == "HELM" ]]; then
    # ref: https://github.com/kubedb/project/issues/262
    mkdir -p /tmp/kubedb || true
    pushd /tmp/kubedb
    if [[ ! -d /tmp/kubedb/cli ]]; then
      git clone https://github.com/kubedb/cli.git || true
    fi

    cd cli
    git checkout 987837d26c0b92705a8bdafde89206e4448c710b
    helm install ./chart/kubedb --name kubedb-operator --namespace=kube-system \
      --set apiserver.ca="$(onessl get kube-ca)" \
      --set apiserver.enableValidatingWebhook=true \
      --set apiserver.enableMutatingWebhook=true

    kubectl wait deploy --for condition=available kubedb-operator -n kube-system --timeout=120s

    popd
  fi
}

0.8.0-uninstall() {
  if [[ "${KUBEDB_INSTALLER}" == "BASH" ]]; then
    curl -fsSL https://raw.githubusercontent.com/kubedb/cli/0.8.0/hack/deploy/kubedb.sh | bash -s -- --uninstall $1
  elif [[ "$KUBEDB_INSTALLER" == "HELM" ]]; then
    helm delete kubedb-operator $1
  fi
}

0.8.0-upgrade() {
  if [[ "${KUBEDB_INSTALLER}" == "BASH" ]]; then
    ${KUBEDB_PREVIOUS_VERSION}-uninstall
    0.8.0-install
  elif [[ "$KUBEDB_INSTALLER" == "HELM" ]]; then
    helm upgrade --install kubedb-operator appscode/kubedb --version 0.8.0
  fi
}

0.9.0-install() {
  if [[ "${KUBEDB_INSTALLER}" == "BASH" ]]; then
    curl -fsSL https://raw.githubusercontent.com/kubedb/cli/0.9.0/hack/deploy/kubedb.sh | bash
  elif [[ "$KUBEDB_INSTALLER" == "HELM" ]]; then
    helm repo add appscode https://charts.appscode.com/stable/
    helm repo update
    helm install appscode/kubedb --name kubedb-operator --version 0.9.0 \
      --namespace kube-system

    TIMER=0
    until kubectl get crd elasticsearchversions.catalog.kubedb.com memcachedversions.catalog.kubedb.com mongodbversions.catalog.kubedb.com mysqlversions.catalog.kubedb.com postgresversions.catalog.kubedb.com redisversions.catalog.kubedb.com || [[ ${TIMER} -eq 60 ]]; do
      sleep 1
      timer+=1
    done

    helm install appscode/kubedb-catalog --name kubedb-catalog --version 0.9.0 \
      --namespace kube-system
  fi
}

0.9.0-uninstall() {
  if [[ "${KUBEDB_INSTALLER}" == "BASH" ]]; then
    curl -fsSL https://raw.githubusercontent.com/kubedb/cli/0.9.0/hack/deploy/kubedb.sh | bash -s -- --uninstall $1
  elif [[ "$KUBEDB_INSTALLER" == "HELM" ]]; then
    helm delete kubedb-operator $1
  fi
}

0.9.0-upgrade() {
  if [[ "${KUBEDB_INSTALLER}" == "BASH" ]]; then
    ${KUBEDB_PREVIOUS_VERSION}-uninstall
    0.8.0-install
  elif [[ "$KUBEDB_INSTALLER" == "HELM" ]]; then
    helm upgrade --install kubedb-operator appscode/kubedb --version 0.9.0

    TIMER=0
    until kubectl get crd elasticsearchversions.catalog.kubedb.com memcachedversions.catalog.kubedb.com mongodbversions.catalog.kubedb.com mysqlversions.catalog.kubedb.com postgresversions.catalog.kubedb.com redisversions.catalog.kubedb.com || [[ ${TIMER} -eq 60 ]]; do
      sleep 1
      timer+=1
    done

    helm upgrade --install kubedb-catalog appscode/kubedb-catalog --version 0.9.0 --namespace kube-system

  fi
}

${KUBEDB_PREVIOUS_VERSION}-install

./before-upgrade.sh

# ${KUBEDB_NEXT_VERSION}-upgrade
