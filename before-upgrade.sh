#!/usr/bin/env bash
set -xeou pipefail

kubectl create ns demo || true

#TIMER=0
#until kubectl create -f https://raw.githubusercontent.com/kubedb/cli/0.8.0/docs/examples/postgres/clustering/hot-postgres.yaml || [[ ${TIMER} -eq 60 ]]; do
#  sleep 1
#  timer+=1
#done

TIMER=0
until kubectl get pods -n demo hot-postgres-0 hot-postgres-1 hot-postgres-2 || [[ ${TIMER} -eq 60 ]]; do
  sleep 1
  timer+=1
done


kubectl wait pods --for=condition=Ready -n demo hot-postgres-0 hot-postgres-1 hot-postgres-2 --timeout=120s

# =================================================================================
# Insert manual data inside primary node of hot-postgres

kubectl exec -i -n demo "$(kubectl get pod -n demo -l "kubedb.com/role=primary" -l "kubedb.com/name=hot-postgres" -o jsonpath='{.items[0].metadata.name}')" -- psql -h localhost -U postgres -d postgres -c '\d'

kubectl exec -i -n demo "$(kubectl get pod -n demo -l "kubedb.com/role=primary" -l "kubedb.com/name=hot-postgres" -o jsonpath='{.items[0].metadata.name}')" -- psql -h localhost -U postgres -t <<SQL
    DROP TABLE IF EXISTS COMPANY;
    CREATE TABLE COMPANY
    (
      ID        INT PRIMARY KEY NOT NULL,
      NAME      TEXT            NOT NULL,
      AGE       INT             NOT NULL,
      ADDRESS   CHAR(50),
      SALARY    REAL,
      JOIN_DATE DATE
    );
SQL

kubectl exec -i -n demo "$(kubectl get pod -n demo -l 'kubedb.com/role=primary' -l 'kubedb.com/name=hot-postgres' -o jsonpath='{.items[0].metadata.name}')" -- psql -h localhost -U postgres -qtAX <<SQL
    INSERT INTO COMPANY (ID, NAME, AGE, ADDRESS, SALARY, JOIN_DATE)
    VALUES (1, 'Paul', 32, 'California', 20000.00, '2001-07-13'),
           (2, 'Allen', 25, 'Texas', 20000.00, '2007-12-13'),
           (3, 'Teddy', 23, 'Norway', 20000.00, '2007-12-13'),
           (4, 'Mark', 25, 'Rich-Mond ', 65000.00, '2007-12-13'),
           (5, 'David', 27, 'Texas', 85000.00, '2007-12-13');
SQL

kubectl exec -i -n demo "$(kubectl get pod -n demo -l "kubedb.com/role=primary" -l "kubedb.com/name=hot-postgres" -o jsonpath='{.items[0].metadata.name}')" -- psql -h localhost -U postgres <<SQL
    SELECT * FROM company;
SQL

count=$(
  kubectl exec -i -n demo "$(kubectl get pod -n demo -l "kubedb.com/role=primary" -l "kubedb.com/name=hot-postgres" -o jsonpath='{.items[0].metadata.name}')" -- psql -h localhost -U postgres -qtAX <<SQL
    SELECT count(*) FROM company;
SQL
)

if [ $count != "5" ]; then
  echo "For postgres: Row count Got: $count. But Expected: 5"
  exit 1
fi

# ------------------------------------------------------
# Sample database. ref: http://www.postgresqltutorial.com/postgresql-sample-database/

z

PGPASSWORD=$(kubectl get secrets -n demo hot-postgres-auth -o jsonpath='{.data.\POSTGRES_PASSWORD}' | base64 -d)

kubectl run -it -n demo --rm --restart=Never postgres-cli --image=postgres:alpine --env="PGPASSWORD=$PGPASSWORD" --command -- bash -c \
  "wget http://www.postgresqltutorial.com/wp-content/uploads/2017/10/dvdrental.zip;
  unzip dvdrental.zip;
  pg_restore --clean --create -h hot-postgres.demo -U postgres -d dvdrental dvdrental.tar;
  psql -h hot-postgres.demo -U postgres -d dvdrental -c '\dt';
  "

# =================================================================================
# Check data from all nodes

total=$(kubectl get postgres hot-postgres -n demo -o jsonpath='{.spec.replicas}')

for ((i = 0; i < $total; i++)); do

  kubectl exec -i -n demo "$(kubectl get pod -n demo -l "kubedb.com/role=primary" -l "kubedb.com/name=hot-postgres" -o jsonpath='{.items[0].metadata.name}')" -- psql -h localhost -U postgres <<SQL
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
    SELECT count(*) FROM payment;
SQL
  )

  if [ $count != "14596" ]; then
    echo "For postgres: Row count Got: $count. But Expected: 5"
    exit 1
  fi

done
