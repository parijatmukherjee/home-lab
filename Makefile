# Home CI/CD Server - Makefile
# Simplified interface for deployment and management

.PHONY: help deploy clean status test validate dry-run backup restore

# Default target
.DEFAULT_GOAL := help

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

# Paths
DEPLOYMENT_DIR := scripts/deployment
REDEPLOY_SCRIPT := $(DEPLOYMENT_DIR)/redeploy.sh
CLEANUP_SCRIPT := $(DEPLOYMENT_DIR)/cleanup.sh

##@ General

help: ## Display this help message
	@echo ""
	@echo "$(BLUE)Home CI/CD Server - Deployment Management$(NC)"
	@echo "$(BLUE)===========================================$(NC)"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make $(GREEN)<target>$(NC)\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  $(GREEN)%-15s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(BLUE)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
	@echo ""

##@ Deployment

deploy: ## Deploy the complete Home CI/CD server
	@echo "$(BLUE)Starting deployment...$(NC)"
	@if [ ! -f "$(REDEPLOY_SCRIPT)" ]; then \
		echo "$(RED)Error: Deployment script not found at $(REDEPLOY_SCRIPT)$(NC)"; \
		exit 1; \
	fi
	@cd $(DEPLOYMENT_DIR) && sudo ./redeploy.sh
	@echo "$(GREEN)Deployment complete!$(NC)"

deploy-test: ## Test deployment in dry-run mode (shows what would be done)
	@echo "$(YELLOW)Running deployment in DRY-RUN mode...$(NC)"
	@echo "$(YELLOW)This will show what would be deployed without making changes$(NC)"
	@cd $(DEPLOYMENT_DIR) && sudo ./redeploy.sh --dry-run || true
	@echo "$(GREEN)Dry-run complete!$(NC)"

##@ Cleanup

clean: ## Remove all deployed components (asks for confirmation)
	@echo "$(YELLOW)Starting cleanup...$(NC)"
	@if [ ! -f "$(CLEANUP_SCRIPT)" ]; then \
		echo "$(RED)Error: Cleanup script not found at $(CLEANUP_SCRIPT)$(NC)"; \
		exit 1; \
	fi
	@cd $(DEPLOYMENT_DIR) && sudo ./cleanup.sh
	@echo "$(GREEN)Cleanup complete!$(NC)"

clean-dry-run: ## Test cleanup without making changes
	@echo "$(YELLOW)Running cleanup in DRY-RUN mode...$(NC)"
	@echo "$(YELLOW)This will show what would be removed without making changes$(NC)"
	@cd $(DEPLOYMENT_DIR) && sudo ./cleanup.sh --dry-run
	@echo "$(GREEN)Dry-run complete!$(NC)"

clean-keep-packages: ## Remove configs/data but keep installed packages
	@echo "$(YELLOW)Cleaning up (keeping packages)...$(NC)"
	@cd $(DEPLOYMENT_DIR) && sudo ./cleanup.sh --keep-packages
	@echo "$(GREEN)Cleanup complete!$(NC)"

##@ Status & Verification

status: ## Show status of all services
	@echo "$(BLUE)Service Status:$(NC)"
	@echo ""
	@echo -n "Jenkins:          "
	@systemctl is-active jenkins 2>/dev/null && echo "$(GREEN)active$(NC)" || echo "$(RED)inactive$(NC)"
	@echo -n "Nginx:            "
	@systemctl is-active nginx 2>/dev/null && echo "$(GREEN)active$(NC)" || echo "$(RED)inactive$(NC)"
	@echo -n "Netdata:          "
	@systemctl is-active netdata 2>/dev/null && echo "$(GREEN)active$(NC)" || echo "$(RED)inactive$(NC)"
	@echo -n "Artifact Upload:  "
	@systemctl is-active artifact-upload 2>/dev/null && echo "$(GREEN)active$(NC)" || echo "$(RED)inactive$(NC)"
	@echo -n "Fail2ban:         "
	@systemctl is-active fail2ban 2>/dev/null && echo "$(GREEN)active$(NC)" || echo "$(RED)inactive$(NC)"
	@echo ""
	@echo "$(BLUE)Endpoints:$(NC)"
	@echo "  • Main Site:      http://core.mohjave.com"
	@echo "  • Jenkins:        http://jenkins.core.mohjave.com"
	@echo "  • Artifacts:      http://artifacts.core.mohjave.com"
	@echo "  • Monitoring:     http://monitoring.core.mohjave.com"
	@echo ""

check: ## Check if deployment is working correctly
	@echo "$(BLUE)Checking deployment health...$(NC)"
	@echo ""
	@FAILED=0; \
	for dir in /opt/core-setup /srv/data /var/lib/jenkins; do \
		if [ -d "$$dir" ]; then \
			echo "$(GREEN)✓$(NC) $$dir exists"; \
		else \
			echo "$(RED)✗$(NC) $$dir missing"; \
			FAILED=1; \
		fi; \
	done; \
	echo ""; \
	for svc in jenkins nginx netdata artifact-upload fail2ban; do \
		if systemctl is-active --quiet $$svc 2>/dev/null; then \
			echo "$(GREEN)✓$(NC) $$svc is running"; \
		else \
			echo "$(RED)✗$(NC) $$svc is not running"; \
			FAILED=1; \
		fi; \
	done; \
	echo ""; \
	if [ $$FAILED -eq 0 ]; then \
		echo "$(GREEN)All checks passed!$(NC)"; \
	else \
		echo "$(YELLOW)Some checks failed - system may not be fully deployed$(NC)"; \
	fi

logs: ## Show recent deployment logs
	@if [ -d "/opt/core-setup/logs" ]; then \
		echo "$(BLUE)Recent deployment logs:$(NC)"; \
		echo ""; \
		sudo tail -50 /opt/core-setup/logs/deployment-*.log 2>/dev/null || echo "$(YELLOW)No logs found$(NC)"; \
	else \
		echo "$(YELLOW)Deployment logs directory not found - system may not be deployed$(NC)"; \
	fi

##@ Validation

validate: ## Validate deployment scripts syntax
	@echo "$(BLUE)Validating deployment scripts...$(NC)"
	@echo ""
	@FAILED=0; \
	for script in $(DEPLOYMENT_DIR)/*.sh $(DEPLOYMENT_DIR)/lib/*.sh $(DEPLOYMENT_DIR)/modules.d/*.sh; do \
		if [ -f "$$script" ]; then \
			echo -n "Checking $$(basename $$script)... "; \
			if bash -n "$$script" 2>/dev/null; then \
				echo "$(GREEN)OK$(NC)"; \
			else \
				echo "$(RED)FAILED$(NC)"; \
				FAILED=1; \
			fi; \
		fi; \
	done; \
	echo ""; \
	if [ $$FAILED -eq 0 ]; then \
		echo "$(GREEN)All scripts are valid!$(NC)"; \
	else \
		echo "$(RED)Some scripts have syntax errors$(NC)"; \
		exit 1; \
	fi

shellcheck: ## Run shellcheck on all scripts (requires shellcheck installed)
	@echo "$(BLUE)Running shellcheck...$(NC)"
	@echo ""
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		echo "$(YELLOW)shellcheck not installed. Install with: sudo apt install shellcheck$(NC)"; \
		exit 1; \
	fi
	@FAILED=0; \
	for script in $(DEPLOYMENT_DIR)/*.sh $(DEPLOYMENT_DIR)/lib/*.sh $(DEPLOYMENT_DIR)/modules.d/*.sh; do \
		if [ -f "$$script" ]; then \
			echo "Checking $$(basename $$script)..."; \
			shellcheck "$$script" || FAILED=1; \
		fi; \
	done; \
	echo ""; \
	if [ $$FAILED -eq 0 ]; then \
		echo "$(GREEN)All scripts passed shellcheck!$(NC)"; \
	else \
		echo "$(YELLOW)Some scripts have shellcheck warnings$(NC)"; \
	fi

##@ Service Management

start: ## Start all services
	@echo "$(BLUE)Starting services...$(NC)"
	@sudo systemctl start jenkins nginx netdata artifact-upload fail2ban 2>/dev/null || true
	@echo "$(GREEN)Services started!$(NC)"
	@make status

stop: ## Stop all services
	@echo "$(BLUE)Stopping services...$(NC)"
	@sudo systemctl stop jenkins nginx netdata artifact-upload fail2ban 2>/dev/null || true
	@echo "$(GREEN)Services stopped!$(NC)"
	@make status

restart: ## Restart all services
	@echo "$(BLUE)Restarting services...$(NC)"
	@sudo systemctl restart jenkins nginx netdata artifact-upload fail2ban 2>/dev/null || true
	@echo "$(GREEN)Services restarted!$(NC)"
	@make status

##@ Quick Actions

redeploy: clean deploy ## Clean and redeploy everything from scratch

quick-deploy: ## Deploy without prompts (use with caution!)
	@echo "$(YELLOW)Quick deployment starting...$(NC)"
	@cd $(DEPLOYMENT_DIR) && sudo ./redeploy.sh --auto-approve 2>/dev/null || sudo ./redeploy.sh
	@echo "$(GREEN)Quick deployment complete!$(NC)"

##@ Information

info: ## Show deployment information
	@echo ""
	@echo "$(BLUE)Home CI/CD Server Deployment$(NC)"
	@echo "$(BLUE)=============================$(NC)"
	@echo ""
	@echo "$(GREEN)Server:$(NC)        core.mohjave.com"
	@echo "$(GREEN)Location:$(NC)      $(DEPLOYMENT_DIR)"
	@echo ""
	@echo "$(BLUE)Services:$(NC)"
	@echo "  • Jenkins CI/CD"
	@echo "  • Nginx Reverse Proxy"
	@echo "  • Netdata Monitoring"
	@echo "  • Artifact Storage"
	@echo "  • Fail2ban Security"
	@echo ""
	@echo "$(BLUE)Ports:$(NC)"
	@echo "  • 80    - HTTP"
	@echo "  • 443   - HTTPS"
	@echo "  • 4926  - SSH"
	@echo "  • 8080  - Jenkins"
	@echo "  • 81    - Nginx Admin"
	@echo ""
	@echo "$(BLUE)Quick Start:$(NC)"
	@echo "  make deploy      - Deploy everything"
	@echo "  make status      - Check service status"
	@echo "  make clean       - Remove everything"
	@echo "  make help        - Show all commands"
	@echo ""

version: ## Show script versions
	@echo "$(BLUE)Script Versions:$(NC)"
	@echo ""
	@grep "^# Version:" $(DEPLOYMENT_DIR)/*.sh 2>/dev/null || echo "No version information found"
	@echo ""
	@echo "Last modified:"
	@ls -lt $(DEPLOYMENT_DIR)/*.sh | head -3 | awk '{print "  " $$9 " - " $$6 " " $$7 " " $$8}'

##@ Testing

test: ## Run E2E tests in Docker
	@echo "$(BLUE)Running End-to-End tests...$(NC)"
	@if ! command -v docker >/dev/null 2>&1; then \
		echo "$(RED)Error: Docker is required for E2E tests$(NC)"; \
		echo "Please install Docker: https://docs.docker.com/get-docker/"; \
		exit 1; \
	fi
	@if ! docker ps >/dev/null 2>&1; then \
		echo "$(YELLOW)Docker requires sudo, running with sudo...$(NC)"; \
		cd tests/e2e && sudo ./run-e2e-tests.sh; \
	else \
		cd tests/e2e && ./run-e2e-tests.sh; \
	fi
	@echo "$(GREEN)E2E tests complete!$(NC)"

test-keep: ## Run E2E tests and keep Docker image
	@echo "$(BLUE)Running E2E tests (keeping image)...$(NC)"
	@if ! docker ps >/dev/null 2>&1; then \
		echo "$(YELLOW)Docker requires sudo, running with sudo...$(NC)"; \
		cd tests/e2e && sudo ./run-e2e-tests.sh --keep-image; \
	else \
		cd tests/e2e && ./run-e2e-tests.sh --keep-image; \
	fi
	@echo "$(GREEN)E2E tests complete!$(NC)"

test-logs: ## Show latest E2E test logs
	@if [ -d "tests/e2e/logs" ]; then \
		LATEST_LOG=$$(ls -t tests/e2e/logs/*.log 2>/dev/null | head -1); \
		if [ -n "$$LATEST_LOG" ]; then \
			echo "$(BLUE)Latest test log: $$LATEST_LOG$(NC)"; \
			echo ""; \
			tail -100 "$$LATEST_LOG"; \
		else \
			echo "$(YELLOW)No test logs found$(NC)"; \
		fi \
	else \
		echo "$(YELLOW)No test logs directory found$(NC)"; \
	fi

test-clean: ## Clean up E2E test logs and artifacts
	@echo "$(BLUE)Cleaning E2E test artifacts...$(NC)"
	@rm -rf tests/e2e/logs/*
	@docker rmi home-lab-e2e:latest 2>/dev/null || true
	@echo "$(GREEN)Test artifacts cleaned!$(NC)"

##@ Development

test-modules: ## Test individual modules (interactive)
	@echo "$(BLUE)Available modules:$(NC)"
	@ls -1 $(DEPLOYMENT_DIR)/modules.d/*.sh | sed 's/.*module-/  • /' | sed 's/.sh//'
	@echo ""
	@echo "Run individual module:"
	@echo "  cd $(DEPLOYMENT_DIR) && sudo ./modules.d/module-<name>.sh"

list-files: ## List all deployment files
	@echo "$(BLUE)Deployment Files:$(NC)"
	@echo ""
	@tree $(DEPLOYMENT_DIR) 2>/dev/null || find $(DEPLOYMENT_DIR) -type f -o -type d | sort

backup-config: ## Backup current configuration
	@echo "$(BLUE)Creating configuration backup...$(NC)"
	@BACKUP_DIR="/tmp/home-lab-config-backup-$$(date +%Y%m%d-%H%M%S)"; \
	mkdir -p "$$BACKUP_DIR"; \
	if [ -d "/opt/core-setup" ]; then \
		sudo cp -r /opt/core-setup "$$BACKUP_DIR/"; \
		echo "$(GREEN)Backup created at: $$BACKUP_DIR$(NC)"; \
	else \
		echo "$(YELLOW)No deployment found to backup$(NC)"; \
	fi

##@ Troubleshooting

debug: ## Enable debug mode for next deployment
	@echo "$(YELLOW)Debug mode enabled$(NC)"
	@echo "export DEBUG=1" > $(DEPLOYMENT_DIR)/.debug
	@echo "Run 'make deploy' to deploy with debug output"
	@echo "Run 'make debug-off' to disable debug mode"

debug-off: ## Disable debug mode
	@rm -f $(DEPLOYMENT_DIR)/.debug
	@echo "$(GREEN)Debug mode disabled$(NC)"

fix-permissions: ## Fix script permissions
	@echo "$(BLUE)Fixing script permissions...$(NC)"
	@find $(DEPLOYMENT_DIR) -type f -name "*.sh" -exec chmod +x {} \;
	@echo "$(GREEN)Permissions fixed!$(NC)"

clean-logs: ## Clean old log files
	@echo "$(BLUE)Cleaning old logs...$(NC)"
	@sudo rm -f /tmp/*-deploy*.log 2>/dev/null || true
	@echo "$(GREEN)Logs cleaned!$(NC)"
