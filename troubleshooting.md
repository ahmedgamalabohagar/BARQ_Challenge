# Infrastructure Log Analysis & Troubleshooting Journal

## 1. Initial Findings from Log Files

* **Log Findings:**
  * **PostgreSQL & App Logs:** Showed `Connection refused` and `FATAL: password authentication failed` exceptions during container startup.
  * **NGINX Logs:** Recorded `111: Connection refused` while connecting to upstream servers, returning `HTTP 502 Bad Gateway` to clients.
* **Diagnosis:** Incorrect database ports, wrong passwords in `app.env`, and `APP_HOST` set to `127.0.0.1` in `docker-compose.yml` caused application containers to fail. This forced NGINX to log upstream connection failures, confirming backend connectivity was broken.

---

## 2. Chronological Order of Fixes

### Step 1: Application Dockerfile Fixes
* **What We Observed:** `docker compose build` failed with package installation errors, and running containers exited immediately with `exec user process caused: no such file or directory`.
* **Problem:** `Dockerfile` had missing dependencies, incorrect `WORKDIR`, broken `CMD` syntax, and improper build instructions.
* **Fix:** Updated `Dockerfile` to install dependencies properly, set correct `WORKDIR`, fix `CMD` execution, and configure non-root user execution.

### Step 2: Environment Variables, Host Binding & Secrets (`docker-compose.yml` & `app.env`)
* **What We Observed:** App logs showed `psycopg2.OperationalError: Connection refused on port 5433` and `password authentication failed`. NGINX logs showed `Connection refused` attempting to reach `127.0.0.1:8000`.
* **Problem:** `APP_HOST` in `docker-compose.yml` was bound to `127.0.0.1` (blocking NGINX access). `DATABASE_URL` and `REDIS_URL` contained wrong port numbers, mismatched passwords, and plain-text secrets.
* **Fix:** 
  1. Updated `APP_HOST` to `0.0.0.0` in `docker-compose.yml` so the application listens on all container network interfaces.
  2. Corrected database/redis port numbers and passwords inside `app.env`.
  3. Removed hardcoded passwords and configured Docker Secrets (`secrets/postgres_password`) for secure credential injection.

### Step 3: Database Storage Persistence (`tmpfs` to Volume)
* **What We Observed:** Database tables and inserted data vanished completely every time `docker compose restart postgres` was executed.
* **Problem:** PostgreSQL storage was configured using in-memory `tmpfs`, wiping out all data on container restart.
* **Fix:** Removed `tmpfs` and attached a persistent named volume (`postgres_data:/var/lib/postgresql/data`).

### Step 4: Network Isolation & Removing Published Ports
* **What We Observed:** Running `nc -zv localhost 5432` or `6379` from the host terminal established direct socket connections to the database and cache.
* **Problem:** Internal ports for PostgreSQL (`5432`), Redis (`6379`), and App replicas were published directly to the host OS.
* **Fix:** Removed `ports:` sections from `postgres`, `redis`, and app services in `docker-compose.yml`. Kept only port `8080` published for NGINX.

### Step 5: Startup Dependencies & Auto-Recovery (`docker-compose.yml`)
* **What We Observed:** App containers crashed instantly on startup with `could not connect to server: Connection refused`, and remained in `Exited` state without restarting.
* **Problem:** App containers started faster than PostgreSQL/Redis cold initialization, and containers lacked automatic restart policies.
* **Fix:** 
  1. Configured `depends_on` with `condition: service_healthy` so app instances wait for database and cache health checks.
  2. Added `restart: unless-stopped` for automatic container recovery.

### Step 6: Load Balancer & Failover Configuration (`nginx.conf`)
* **What We Observed:** NGINX logs recorded `connect() failed (111: Connection refused) while connecting to upstream "app-01:8001"`. Stopping `app-01` returned `HTTP 502 Bad Gateway` to users instead of routing to `app-02`.
* **Problem:** Port for `app-01` had a typo (`8001`), and missing `max_fails`, `fail_timeout`, and proxy redirection rules broke failover handling.
* **Fix:** 
  1. Corrected `app-01` upstream port to `8000` in `nginx.conf`.
  2. Added `max_fails=3 fail_timeout=10s` to upstream app targets.
  3. Added `proxy_next_upstream error timeout http_502 http_503;` to automatically redirect traffic to healthy replicas.

### Step 7: Permission Fixes & Container Hardening
* **What We Observed:** Container startup logs for PostgreSQL, Redis, and NGINX printed `Permission denied` on volume mounts (`/var/lib/postgresql/data`) and socket files, exiting with code 1.
* **Problem:** Applying global non-root `user:` directives in `docker-compose.yml` prevented infrastructure containers from initializing required system files.
* **Fix:** Removed manual non-root `user:` overrides from PostgreSQL, Redis, and NGINX services in `docker-compose.yml` to allow normal volume initialization, while keeping non-root security active inside the custom Application Dockerfile.
