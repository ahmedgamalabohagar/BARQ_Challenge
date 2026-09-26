# Architectural Decisions & Trade-Offs

This document outlines the core technical decisions, underlying assumptions, evaluated alternatives, and trade-offs made during the infrastructure implementation.

---

## Decision 1: NGINX Reverse Proxy for Round-Robin Load Balancing

* **Decision:** Used NGINX as an edge reverse proxy to distribute incoming client traffic across dual application replicas (`app-01` and `app-02`) using a round-robin algorithm with passive health checks (`max_fails=3 fail_timeout=10s`).
* **Assumptions:** Application replicas are stateless and can process requests interchangeably without session affinity dependencies.
* **Alternatives Considered:** 
  * *Single Application Instance:* Lower operational complexity, but lacks fault tolerance and zero-downtime capabilities.
  * *Traefik / HAProxy:* Advanced dynamic routing, but adds unnecessary complexity for a multi-container Docker Compose stack.
* **Trade-offs & Limitations:** NGINX acts as a Single Point of Failure (SPOF) on single-host deployments. Upstream retries (`proxy_next_upstream`) add minor latency overhead during failover events.

---

## Decision 2: Dual Network Segmentation (`frontend` vs. `backend`)

* **Decision:** Isolated containers into two distinct Docker bridge networks: `frontend` (NGINX and App replicas) and `backend` (App replicas, PostgreSQL, and Redis).
* **Assumptions:** External clients should only access the system via HTTP on Port `8080`. Datastores must never be directly exposed to the host interface.
* **Alternatives Considered:** 
  * *Single Flat Network:* Simpler configuration, but exposes database container sockets to all containers on the bridge.
  * *Publishing Host Ports (`5432`/`6379`):* Allows direct host debugging, but severely compromises network security boundaries.
* **Trade-offs & Limitations:** Database management and debugging require executing CLI commands inside containers (`docker exec`) or using ephemeral debug containers rather than host-level GUI tools.

---

## Decision 3: Managed Named Volumes for Persistent Datastores

* **Decision:** Replaced `tmpfs` with a dedicated Docker named volume (`postgres_data`) for PostgreSQL persistence.
* **Assumptions:** Application data must persist across container restarts, recreates, and host reboots.
* **Alternatives Considered:** 
  * *`tmpfs` (In-Memory Storage):* High I/O performance, but causes total data loss on container termination.
  * *Host Bind Mounts (`./data:/var/lib/postgresql/data`):* Direct host file visibility, but introduces cross-platform file permission issues (UID/GID mismatches) between Host OS and Linux containers.
* **Trade-offs & Limitations:** Named volumes are managed internally by the Docker Engine, making raw database file inspection slightly less accessible on the host filesystem without root privileges.

---

## Decision 4: Docker File-Based Secrets for Credential Injection

* **Decision:** Injected sensitive database credentials using Docker Secrets (`secrets/postgres_password`) and environment variable mapping instead of plaintext values in compose files.
* **Assumptions:** Passwords must not be hardcoded in version-controlled configuration files (`docker-compose.yml` or git repo).
* **Alternatives Considered:** 
  * *Plaintext Environment Variables in `app.env`:* Easy to configure, but exposes secrets via `docker inspect` and process environment listings.
  * *External Vault (e.g., HashiCorp Vault):* Enterprise-grade security, but creates heavy infrastructure overhead for local/CI container environments.
* **Trade-offs & Limitations:** Docker Compose file-backed secrets are mounted as plain files inside containers, which works well locally but requires integration with cloud KMS/Vault solutions in enterprise production environments.

---

## Decision 5: Deep Readiness Probes (`/ready`) Over Simple Process Checks

* **Decision:** Configured Docker health checks and application probes to validate active connections to PostgreSQL and Redis before marking instances as `healthy`.
* **Assumptions:** A running application process is useless if it cannot query its persistent datastores or cache layers.
* **Alternatives Considered:** 
  * *Basic TCP/Port Probes:* Checks if the web port is open, but fails to detect backend dependency crashes.
  * *Static `/health` Endpoint:* Returns `HTTP 200 OK` regardless of datastore connectivity state.
* **Trade-offs & Limitations:** Deep probes introduce minor execution overhead and additional queries to PostgreSQL/Redis at regular check intervals (`interval: 5s`).
