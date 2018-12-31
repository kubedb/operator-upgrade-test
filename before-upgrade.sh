#!/usr/bin/env bash

kubectl create ns demo || true
kubectl create -f https://raw.githubusercontent.com/kubedb/cli/0.8.0/docs/examples/postgres/clustering/hot-postgres.yaml

kubectl wait pods --for=condition=Ready -n demo hot-postgres-0 hot-postgres-1 hot-postgres-2

kubectl exec -it -n demo "$(kubectl get pod -n demo -l "kubedb.com/role=primary" -l "kubedb.com/name=hot-postgres" -o jsonpath='{.items[0].metadata.name}')" -- bash -c \
 " psql -h localhost -U postgres; \l; \d; \q;"

