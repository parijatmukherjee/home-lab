# Core.Mohjave Constitution

## Core Principles

### I. Transparency & Approval (NON-NEGOTIABLE)
Every operation Claude performs must be transparent and explicitly approved by the human administrator.  
Claude can propose system-level plans or configurations but cannot self-execute without human consent.  
All actions must be logged with timestamps and justifications under `/opt/core-setup/logs/`.

### II. Security & Least Privilege
Claude must follow least-privilege and defense-in-depth principles:  
- Use restricted service accounts.  
- No plaintext secrets or API keys.  
- Enforce SSH key-based access (port 4926).  
- Ensure firewall (UFW) + fail2ban + TLS are always active.  

### III. Reproducibility & Script-First Design
All configurations must be script-driven, idempotent, and reproducible.  
The entire system must be restorable via:
```bash
sudo /opt/core-setup/redeploy.sh
```
Manual changes to the system without script updates are not permitted.

### IV. Observability & Auditability
All system changes, service restarts, and configuration updates must be logged and observable.  
Structured logs must exist for Jenkins, Nginx, SSL, and automation events.  
Any unexpected behavior or security violation must trigger a report to the human administrator.

### V. Extensibility & Modularity
Each DevOps component (CI/CD, Registry, Observability, Security) must be modular.  
Claude can propose or register new modules under `/opt/core-setup/modules.d/` following the naming convention `module-[feature].sh`.

### VI. Testing
Before concluding each phase, the E2E test MUST be run and the E2E test must be green. Otherwise, next phase MUST not be started.
Each of the new feature/bug-fix/update should be shipped with an addition/updation of E2E test. 

---

## Security Requirements

- HTTPS enforced sitewide using Let’s Encrypt or DNS-01 certificates.  
- Firewall (UFW) rules: only allow 4926, 80, 81, 443, 8080.  
- SSH: no root login, no password login.  
- Backups encrypted via Restic or BorgBackup and stored locally + remotely.  
- Regular security scans and OS patch updates must be performed monthly.  
- Anti-bot and rate-limiting protection must be configured in Nginx.  
- CrowdSec or fail2ban must monitor all inbound ports.

---

## Development Workflow

1. **Proposal Stage:** Claude drafts automation scripts or plans.  
2. **Approval Stage:** Human administrator reviews and explicitly approves.  
3. **Execution Stage:** Claude executes with full logs and rollback checkpoints.  
4. **Validation Stage:** Jenkins tests verify successful provisioning.  
5. **Audit Stage:** All actions recorded in `/opt/core-setup/logs/change-history.log`.

**CI/CD Integration Requirements**
- Jenkins must run behind HTTPS on port 8080 proxied via Nginx.  
- Webhooks must connect securely to GitHub/GitLab.  
- Artifact builds (ISO, JAR, NPM, Docker) must be stored in `/srv/data/artifacts/` or Nexus/Harbor.  
- CI jobs must use declarative pipelines with fail-safe rollback on errors.

---

## Governance

- This constitution overrides all local ad-hoc practices.  
- Amendments require written documentation and human approval.  
- Any non-compliant configuration must be reverted.  
- Backward compatibility with existing scripts must be preserved unless explicitly deprecated.  
- Complexity or external dependencies must always be justified.  
- Use `guidance.md` for runtime behavior rules and day-to-day operational updates.

**Version**: 1.0.0 | **Ratified**: 2025-10-23 | **Last Amended**: 2025-10-23

