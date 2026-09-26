# AI Usage & Verification Log

This document details the limited and specific use of AI tools during the development and documentation of this project.

---

## 1. Tools Used
* **AI Tool:** ChatGPT / Claude / Gemini (LLM Assistants)

---

## 2. Purpose
* **Script Refinement & Optimization:** Assisted in optimizing existing shell automation scripts (`validate.sh`, `failure_test.sh`, `backup.sh`, `restore.sh`) by refining error handling and exit codes.
* **NGINX Configuration Assistance:** Helped craft the specific passive failover and redirection directives (`proxy_next_upstream`, `max_fails`, and `fail_timeout`) inside `nginx.conf`.
* **Documentation Structuring:** Assisted in organizing and formatting technical `.md` documentation files according to assessment rubric guidelines.

---

## 3. Affected Files
* **Configuration Files:** `nginx.conf`
* **Automation Scripts:** `validate.sh`, `failure_test.sh`, `backup.sh`, `restore.sh`
* **Documentation Files:** `README.md`, `troubleshooting.md`, `log_analysis.md`, `decisions.md`, `security_review.md`

---

## 4. Verification Methods
All AI-suggested code snippets and configurations were strictly verified before implementation:
* **Manual Code Review:** Inspected every line of suggested shell logic and NGINX syntax to ensure compliance with POSIX standards and official documentation.
* **Local Testing & Execution:** Ran all modified shell scripts locally in a Linux terminal, explicitly verifying exit codes (`echo $?`) during pass/fail conditions.
* **Failover Validation:** Verified NGINX redirection behavior by manually stopping `app-01` and confirming zero HTTP error responses via live log tailing (`docker compose logs nginx`).
