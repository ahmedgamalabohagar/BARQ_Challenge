#! /usr/bin/env bash

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
max_retries=15
sleep_interval=2
failed=0

log_pass() { echo "[PASS]: $1" ;}
log_fail() { echo "[FAIL]: $1" ; failed=1; }
log_info() { echo "[INFO]: $1" ;}

echo "===================================================="
echo "                 starting system validation         "
echo "===================================================="
#wait for api readiness
log_info "1. check API readness at ${BASE_URL}/ready ....."
ready=false
ready_file=$(mktemp)

for (( i=1 ; i<=max_retries ; i++ )); do
    HTTP_CODE=$(curl -s -o "$ready_file" -w "%{http_code}" "${BASE_URL}/ready" || true)
    if [ "${HTTP_CODE} -eq 200" ]; then
        ready=true
        break
    fi 
    echo "attempt $i/$max_retries: service not ready (HTTP $HTTP_CODE). retring in $sleep_interval... "
    sleep $sleep_interval
done

if [ "$ready" = true ]; then
    log_pass "endpoint /ready is up "
else
    log_fail "endpoint /ready is faild within $((max_retries * sleep_interval)) seconds."
fi

#check (postgres,redis)
if [ -s "$ready_file" ]; then
    if grep -q '"postgres":"ready"' "$ready_file"; then
        log_pass "dependancy check: postgress is ready"
    else
        log_fail "dependancy check: postgress is not ready"
    fi

    if grep -q '"redis":"ready"' "$ready_file"; then
        log_pass "dependancy check: redis is ready"
    else
        log_fail "dependancy check: redis is not ready"
    fi
fi
rm -f "$ready_file"

#check backend instance
log_info "verifying (app-01,app-02)"
found_app1=false
found_app2=false

for i in {1..10}; do
    instance_id=$(curl -s -i  "${BASE_URL}/ready" | grep -i "x-instance-id:" | tr -d '\r' | awk '{print $2}' || true )
    if [ "$instance_id" = "app-01" ]; then
        found_app1=true
    elif [ "$instance_id" = "app-02" ]; then
        found_app2=true
    fi
done

if [ "$found_app1" = true ] && [ "$found_app2" = true ]; then
    log_pass  "both (app-01 and app-02) working successfully "
else
    log_fail  "load balancing failure ( app-01 reached: ${found_app1} , app-02 reached: ${found_app2})"
fi

#check network isolation
log_info "verify network isolation on port (5432 , 6379)..."
if (echo > /dev/tcp/127.0.0.1/5432) 2> /dev/null; then
    log_fail "port 5432 is exposed on Host "
else 
    log_pass "port 5432 is isolated on Host "
fi 

if (echo > /dev/tcp/127.0.0.1/6379) 2> /dev/null; then
    log_fail "port 6379 is exposed on Host "
else 
    log_pass "port 6379 is isolated on Host "
fi 

echo "================================================="
#exit code
if [ "$failed" -eq 0 ]; then
    log_pass "all validation checks passed successfullt :) "
    exit 0
else
    log_fail "validation faild ,checks logs :( "
    exit 1
fi



