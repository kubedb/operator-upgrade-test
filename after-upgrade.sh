#!/usr/bin/env bash
set -xeou pipefail

export KUBEDB_PREVIOUS_VERSION=${KUBEDB_PREVIOUS_VERSION:-0.8.0}
export KUBEDB_NEXT_VERSION=${KUBEDB_NEXT_VERSION:-0.9.0}

# =================================================================================
# Upgrade DB versions to latest

if [[ ${KUBEDB_NEXT_VERSION} == "0.9.0" ]]; then

  TIMER=0
  until kubectl patch -n demo pg/hot-postgres -p '{"spec": {"version": "9.6-v1","updateStrategy": { "type": "OnDelete" } } }' --type="merge" || [[ ${TIMER} -eq 60 ]]; do
    sleep 1
    TIMER=$((TIMER + 1))
  done
fi

# =================================================================================
# Check data from all nodes

total=$(kubectl get postgres hot-postgres -n demo -o jsonpath='{.spec.replicas}')

for ((i = ${total} - 1; i >= 0; i--)); do

  # Delete the pod because of onDelete update strategy
  kubectl delete po -n demo hot-postgres-${i}

  kubectl wait pods --for=condition=Ready -n demo hot-postgres-${i} --timeout=120s

  # Check if Database is ready by pgready
  TIMER=0
  until kubectl exec -i -n demo hot-postgres-${i} -- pg_isready -h localhost -U postgres -d postgres || [[ ${TIMER} -eq 60 ]]; do
    sleep 1
    TIMER=$((TIMER + 1))
  done

  kubectl exec -i -n demo hot-postgres-${i} -- psql -h localhost -U postgres <<SQL
    SELECT * FROM company;
SQL

  count=$(
    kubectl exec -i -n demo hot-postgres-${i} -- psql -h localhost -U postgres -qtAX <<SQL
    SELECT count(*) FROM company;
SQL
  )

  if [ $count != "5" ]; then
    echo "For postgres: Row count Got: $count. But Expected: 5"
    exit 1
  fi

  # -----------------------------------------
  # dvd rental data

  count=$(
    kubectl exec -i -n demo hot-postgres-${i} -- psql -h localhost -U postgres -d dvdrental -qtAX <<SQL
    SELECT SUM(seq_tup_read) FROM pg_stat_user_tables;
SQL
  )

  if [ $count != "275537" ]; then
    echo "For postgres: Row count Got: $count. But Expected: 275537"
    exit 1
  fi

done
