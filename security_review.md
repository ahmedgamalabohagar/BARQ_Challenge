# Security Review & Risk Assessment

This document highlights 8 concrete security risks identified within the current infrastructure architecture and details the actionable improvements required to mitigate them.

---

## 1. Lack of TLS/HTTPS Encryption in Transit
* **Risk:** All incoming client traffic to Host Port `8080` and internal container traffic operates over unencrypted HTTP. Intercepted network packets can expose sensitive request data, cookies, and tokens in plain text.
* **Improvement:** Configure TLS termination at the NGINX layer using automated Let's Encrypt certificates (via Certbot) or custom SSL/TLS certificates. Enforce HTTP-to-HTTPS redirection and HTTP Strict Transport Security (HSTS) headers.

---

## 2. Plaintext Secrets Stored on Local Disk
* **Risk:** Docker secrets (`secrets/postgres_password`) are stored as unencrypted plain text files on the host filesystem, exposing credentials to any process or user with host read permissions.
* **Improvement:** Integrate a dedicated secret management tool (e.g., HashiCorp Vault, AWS Secrets Manager, or Kubernetes Secrets) to dynamically inject encrypted credentials into runtime container memory at startup.

---

## 3. Absence of Rate Limiting on Ingress Layer (DDoS / Brute Force Risk)
* **Risk:** NGINX currently forwards all incoming HTTP requests without rate enforcement, making the application vulnerable to Denial of Service (DoS) attacks and brute-force traffic floods.
* **Improvement:** Implement `limit_req_zone` and `limit_conn_zone` directives inside `nginx.conf` to cap requests per second per IP address and limit concurrent connections.

---

## 4. Root Privileges in Infrastructure Container Runtimes
* **Risk:** Infrastructure containers (PostgreSQL, Redis, NGINX) rely on default entrypoints that run primary processes with elevated privileges, increasing the risk of host compromise in the event of a container breakout.
* **Improvement:** Custom-build infrastructure images with explicit non-root service accounts (`USER 10001`), configure explicit file ownership (`chown`) on mounted volumes, and execute container runtimes under unprivileged security contexts.

---

## 5. Lack of Automated Container Image Vulnerability Scanning
* **Risk:** Base container images and OS packages could contain unpatched CVEs (Common Vulnerabilities and Exposures) that go undetected during deployment.
* **Improvement:** Embed static container security scanners (e.g., Trivy, Grype, or Docker Scout) directly into the GitHub Actions CI pipeline to automatically fail builds containing `CRITICAL` or `HIGH` vulnerabilities.

---

## 6. Writable Root Filesystem inside Running Containers
* **Risk:** A compromised container process can modify system binaries, drop malicious scripts, or install unverified packages directly into the running container filesystem.
* **Improvement:** Enforce a read-only root filesystem (`read_only: true` in `docker-compose.yml`) for application containers, restricting file writes exclusively to temporary in-memory mounts (`tmpfs` for `/tmp`) and dedicated persistent volumes.

---

## 7. Excess Linux Kernel Capabilities Allowed
* **Risk:** Containers retain default Linux kernel capabilities (e.g., `CAP_NET_RAW`, `CAP_SYS_ADMIN`), providing an expanded attack surface for privilege escalation exploits.
* **Improvement:** Explicitly drop all default kernel capabilities (`cap_drop: [ALL]`) in `docker-compose.yml` and add back only minimal required permissions (e.g., `cap_add: [NET_BIND_SERVICE]`).

---

## 8. Information Disclosure via Error Stack Traces and Server Headers
* **Risk:** Default error pages and HTTP response headers expose exact NGINX, Python, and OS version numbers to clients, aiding attackers in targeted footprinting.
* **Improvement:** Disable version headers by adding `server_tokens off;` in `nginx.conf`, and implement generic application error handlers that conceal internal stack traces from client responses.
