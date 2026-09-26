## Local Setup & Environment Configuration

To run and test the solution locally on your machine, create the necessary secrets and environment configuration before launching the containers:

```bash
# 1. Create secrets directory and write the PostgreSQL password secret
mkdir -p secrets config
echo "BarqLabOnly_7qN2vK8c" > secrets/postgres_password

# 2. Create the application environment file
cat <<EOF> config/app.env
POSTGRES_USER=app_user
POSTGRES_DB=app_db
DATABASE_URL=postgresql://app_user:BarqLabOnly_7qN2vK8c@postgres:5432/app_db
REDIS_URL=redis://redis:6379/0
PUBLIC_PORT=8080
EOF

# 3. Sync environment configuration for Docker Compose context
cp config/app.env .env

# 4. Make all automation scripts executable
chmod +x validate.sh failure_test.sh backup.sh restore.sh

## Build Commands

Build all service container images defined in the Docker Compose configuration:

```bash
# Build container images for all services
docker compose build

# verfication
docker compose images

## Running & Managing Services

Use the following commands to start, inspect, and manage the containerized application stack:

```bash
# 1. Start all services in the background (detached mode)
docker compose up -d

# 2. Verify container status and health checks
docker compose ps

# 3. Stream logs from all services (press Ctrl+C to exit)
docker compose logs -f

# 4. Gracefully stop all running services without removing container state
docker compose stop

# 5. Restart all services
docker compose restart

## Automated Testing & Validation

Execute the automated scripts to verify system operational health and self-healing resilience:

```bash
# 1. Run validation suite (Health checks, HTTP routing, DB & Cache access)
./validate.sh

# 2. Run failure simulation and self-healing recovery test
./failure_test.sh

# 1. Create a logical dump of the PostgreSQL database
./backup.sh

# 2. Restore database state from the latest generated backup file
./restore.sh

# Stop containers and remove associated networks, containers, and named volumes
docker compose down -v

___________________________________________________________________________________

### Question 1: Root Cause & Investigation Journal

* **What failed first?**
  During the initial deployment attempt, the application containers (`app-01` and `app-02`) failed during startup, causing readiness checks on `http://localhost:8080/ready` to return `HTTP 502 Bad Gateway` / `HTTP 500 Internal Server Error`.

* **What proved the cause?**
  Inspecting application container logs via `docker compose logs app-01` revealed explicit connection refusal exceptions:
  `psycopg2.OperationalError: could not connect to server at "postgres", port 5432 failed: Connection refused`.
  Cross-referencing `app.env` against `docker-compose.yml` confirmed credentials and database target port mismatches between the application context and the PostgreSQL service definition.

* **Which failed attempt taught you something?**
  Updating the environment variables in `app.env` and executing a soft container restart (`docker compose restart`) failed to restore the database connection.
  *Lesson Learned:* The official PostgreSQL Docker image executes initialization scripts (`postgres-initdb`) exclusively during the initial creation of the persistent volume (`postgres-data`). Updating runtime environment files does not modify an already-initialized PostgreSQL data directory. Resolving the issue required purging stale volume state with `docker compose down -v` to force a clean database re-initialization with the updated credentials.

### Question 2: Log Analysis & Request Correlation

* **What patterns did the logs reveal?**
  * **Startup Sequence:** NGINX logs initially recorded upstream readiness check retries until backend containers successfully initialized database and cache connections.
  * **Steady-State Load Balancing:** NGINX access logs demonstrated a clean 50/50 round-robin traffic split between `app-01` and `app-02`, verified by the alternating `X-Instance-ID` HTTP header values in client responses.
  * **Fault Tolerance & Failover:** During the execution of `failure_test.sh` (where `app-01` was forcibly stopped), NGINX access logs captured a single upstream error (`connect() failed / Connection refused`) before instantly rerouting 100% of subsequent incoming traffic to the healthy `app-02` container without returning HTTP 5xx errors to the client.

* **How did you avoid double-counting requests?**
  To prevent double-counting HTTP requests caused by internal NGINX upstream retries during backend failure scenarios:
  * Edge client traffic metrics were derived exclusively from the NGINX access logs (`/var/log/nginx/access.log`), which represent the single source of truth for external client requests.
  * Internal request logs generated directly inside individual backend application containers were excluded from aggregate request counts, ensuring that retried requests were not counted multiple times.




### Question 3: Architecture & Traffic Flow

* **How do requests flow?**
  1. **Client Ingress:** Incoming HTTP client requests hit Host Port `8080` (`PUBLIC_PORT`).
  2. **Load Balancing:** NGINX listens on port `8080` on the `frontend` network and proxies traffic using a round-robin algorithm.
  3. **Internal Application Routing:** Requests route over the isolated `backend` Docker network to `app-01:8000` or `app-02:8000`.
  4. **Datastore Persistence & Caching:** Application replicas query PostgreSQL on `postgres:5432` for persistent state and Redis on `redis:6379` for caching within the internal network.

* **Why these ports, networks, and readiness checks?**
  * **Port 8080 Exposure:** Single entry point exposed to the host interface to minimize attack surface.
  * **Strict Network Isolation:** Omitting host port bindings for PostgreSQL (`5432`) and Redis (`6379`) ensures datastores are strictly accessible over the internal Docker network.
  * **Deep Readiness Probes (`/ready`):** Probes verify active database and cache connectivity before returning `HTTP 200 OK`. This prevents NGINX from routing live user traffic to partially degraded or initializing instances.


### Question 4: Operational Resilience & Parameters

* **Why these timeouts, retries, restart settings, and resource limits?**
  * **Bounded Timeouts & Retries (15 retries × 2s sleep interval):** Imposes a strict 30-second execution threshold for health and readiness checks. This prevents automated CI/CD pipelines from hanging indefinitely while giving datastores sufficient time to complete cold-start initialization scripts.
  * **Automated Self-Healing (`restart: "unless-stopped"`):** Ensures that if an application process crashes due to an unhandled exception or transient network glitch, Docker automatically restarts the container without manual operator intervention.
  * **Resource Allocation & Constraints (`cpus` and `memory` limits):** Prevents memory leaks or cpu-intensive routines inside individual application containers from starving the host operating system or triggering the Linux Kernel Out-Of-Memory (OOM) killer on critical infrastructure like PostgreSQL.


### Question 5: CI/CD Pipeline & Validation Limits

* **When should validation fail?**
  Validation scripts (`validate.sh` and `ci.yml` pipeline steps) strictly exit with code `1` (failure) if:
  * Any core endpoint (`/ready` or `/live`) returns a non-200 HTTP status code.
  * Load balancing fails to alternate requests between `app-01` and `app-02` (missing `X-Instance-ID` header alternation).
  * Direct host socket checks detect accessible internal ports for PostgreSQL (`5432`) or Redis (`6379`).
  * Failover simulation returns HTTP 5xx errors to the client during single-node application outage testing.

* **What does green CI prove, or not prove?**
  * **What Green CI Proves:** 
    * Build reproducibility across clean environments.
    * Functional end-to-end connectivity between application, database, and cache layers.
    * Active round-robin load balancing and network isolation compliance.
    * Automated zero-downtime failover handling upon single-instance failure.
  * **What Green CI Does NOT Prove:** 
    * System performance and throughput boundaries under heavy concurrent traffic loads (Stress/Load testing required).
    * Immunity to deep application-level vulnerabilities or zero-day security threats.
    * Multi-node cloud infrastructure resilience beyond a single host machine running Docker Compose.


### Question 6: Single Points of Failure (SPOFs) & Production Plan

* **Which single points of failure remain?**
  * **Single Ingress Load Balancer:** A single NGINX container acts as the sole entry point. A crash or configuration syntax failure on NGINX renders the entire application stack unreachable.
  * **Single Database Instance:** PostgreSQL runs as a single container instance without hot standby replicas or automatic master-slave failover.
  * **Single Cache Instance:** Redis operates as a standalone node without cluster-mode replication.
  * **Single Host Environment:** All containers are bound to a single underlying physical host machine/VM. Physical hardware failure or host kernel panics cause complete system downtime.

* **How would you fix them in production?**
  * **Managed Cloud Load Balancing:** Replace the single NGINX container with an Elastic/Cloud Load Balancer ( AWS ALB / Cloudflare) spanning multiple Availability Zones (AZs) with automated SSL/TLS offloading.
  * **Managed High-Availability Database:** Migrate PostgreSQL to a managed database service (e.g., AWS RDS PostgreSQL Multi-AZ or Amazon Aurora) featuring automated synchronous replication, point-in-time recovery, and instant multi-AZ failover.
  * **Distributed Cache Cluster:** Deploy Redis using a managed cluster service ( AWS ElastiCache for Redis) with multi-AZ replication enabled.
  * **Container Orchestration & Multi-Node Infrastructure:** Migrate workloads from single-node Docker Compose to a cloud-managed Kubernetes cluster ( AWS EKS / GCP GKE) with Auto-Scaling Groups distributed across distinct failure domains.


### Question 7: Continuous Improvement & AI Verification

* **What would you improve?**
  * **Automated Security Scanning:** Integrate vulnerability scanners (e.g., Trivy or Grype) into the GitHub Actions CI/CD pipeline to block builds containing critical CVEs in base images or dependencies.
  * **Observability & Telemetry Stack:** Implement Prometheus metrics endpoints and Grafana dashboards to monitor request throughput, HTTP status distribution, backend latency, and container resource utilization.
  * **TLS Encryption in Transit:** Configure HTTPS termination at the NGINX proxy layer using automated Let's Encrypt certificates or TLS secrets.

* **How did you verify AI-assisted work?**
  * **Manual Code & Logic Audits:** Carefully reviewed all AI-assisted shell scripts (`validate.sh`, `failure_test.sh`, `backup.sh`, `restore.sh`), `docker-compose.yml` configurations, and CI workflow files against official Docker, NGINX, and POSIX documentation.
  * **Empirical Local Execution:** Ran every script in a live Linux terminal environment, explicitly verifying process exit codes (`echo $?`) to ensure strict error handling.
  * **Behavioral & Log Validation:** Cross-referenced expected system behavior against actual container output logs (`docker compose logs`) to confirm true round-robin distribution, clean volume purging, and zero-downtime failover execution.


