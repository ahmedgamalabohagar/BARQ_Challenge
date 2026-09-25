#! /usr/bin/env bash

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
target_app='app-01'
total_requests=20
failed=0

cleanup() {
    echo "[INFO]: cleanup: ensuring ${target_app} is running ..."
    docker compose start "${target_app}" > /dev/null 2>&1 || true
}
trap cleanup EXIT

log_pass() { echo "[PASS]: $1" ; }
log_fail() { echo "[FAIL]: $1" ; failed=1 ;}
log_info() { echo "[INFO]: $1" ; }

echo "=========================================="
echo "     STARTING FAILURE AND RECOVERY TEST"
echo "=========================================="

# check system readiness
log_info "1. check system work before FAILURE test..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/ready" || true)
if [ "$HTTP_CODE" -eq 200 ]; then
    log_pass "system status is http 200 ok "
else
    log_fail "check failed with http ${HTTP_CODE} "
    exit 1
fi

# stop one instance
log_info "stopping (${target_app})"
docker compose stop "${target_app}" >/dev/null 


#measure traffic and error after one instance down
log_info "sending $total_requests requests while $target_app is down..."
success_count=0
error_count=0

for ((i=1 ; i<=$total_requests ; i++));do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/ready" || true)
    if [ "${HTTP_CODE}" -eq 200 ]; then
        success_count=$((success_count + 1))
    else
        error_count=$((error_count + 1))
    fi
    sleep 0.2
done

echo "_________________________________________"
echo "total requests      : $total_requests"
echo "successful requests : $success_count"
echo "faild requests      : $error_count"
echo "_________________________________________"

#restore the stopped instance
log_info "restoring instance : $target_app"
docker compose start $target_app >/dev/null

#verify recovery and traffic serving by recoverd instance
log_info "Verifying that $target_app recover and recieve requests"
recoverd=false
max_retries=15

for ((i=1 ; i<=max_retries ; i++)); do
    instance_id=$(curl -s -i "${BASE_URL}/ready" | grep -i "x-instance-id:" | tr -d "\r" |awk '{print $2}' || true)
    if [ "$instance_id" = "$target_app" ]; then
        recoverd=true
        break
    fi
    sleep 1
done

if [ "$recoverd" = true ]; then
    log_pass "$target_app successfully recoverd and serving trafic "
else
    log_fail "$target_app failed to serving trafic after restart "
fi


echo "===================================================="
if [ "$failed" -eq 0 ]; then
    log_pass "failure and recovery test passed successfully :)"
    exit 0
else
    log_fail "failure and recovery test fail :("
    exit 1
fi


