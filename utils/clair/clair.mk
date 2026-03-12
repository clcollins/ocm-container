####################
# Vulnerability Scanning with Clair
####################

CLAIR_POD_YAML := utils/clair/clair-scanner.yaml
SCAN_RESULTS_DIR := scan-results

.PHONY: clair-start
clair-start:
	@echo "Starting Clair scanning environment..."
	@sed "s|PWD_PLACEHOLDER|$(CURDIR)|g" $(CLAIR_POD_YAML) | podman play kube -
	@echo "Waiting for Clair to become ready..."
	@TIMEOUT=1200; ELAPSED=0; \
	while [ $$ELAPSED -lt $$TIMEOUT ]; do \
		if [ "$$(podman inspect clair-scanner-clair-service --format '{{.State.Health.Status}}' 2>/dev/null)" = "healthy" ]; then \
			echo "Clair initialization complete! ($${ELAPSED}s)"; \
			break; \
		fi; \
		sleep 10; \
		ELAPSED=$$((ELAPSED + 10)); \
		if [ $$((ELAPSED % 60)) -eq 0 ]; then \
			echo "  Still initializing... ($${ELAPSED}s elapsed)"; \
		fi; \
	done; \
	if [ $$ELAPSED -ge $$TIMEOUT ]; then \
		echo "ERROR: Clair initialization timed out after $${TIMEOUT}s"; \
		echo "Check logs: podman logs clair-scanner-clair-service"; \
		exit 1; \
	fi
	@echo "Clair scanning environment ready at http://localhost:6060"

.PHONY: clair-stop
clair-stop:
	@echo "Stopping Clair scanning environment..."
	@sed "s|PWD_PLACEHOLDER|$(CURDIR)|g" $(CLAIR_POD_YAML) | podman play kube --down -
	@echo "Clair scanning pod removed"

.PHONY: clair-status
clair-status:
	@echo "Pod status:"
	@podman pod ps --filter name=clair-scanner
	@echo ""
	@echo "Container status:"
	@podman ps --filter pod=clair-scanner
	@echo ""
	@echo "Health status:"
	@if [ "$$(podman inspect clair-scanner-clair-service --format '{{.State.Health.Status}}' 2>/dev/null)" = "healthy" ]; then \
		echo "✓ Clair is healthy and ready"; \
	else \
		echo "✗ Clair is not ready"; \
	fi

# Scan using clairctl (https://github.com/quay/clair/tree/main/cmd/clairctl)
# Requires: go install github.com/quay/clair/v4/cmd/clairctl@latest
.PHONY: clair-scan
clair-scan: SCAN_IMAGE ?= $(IMAGE_NAME):latest
clair-scan:
	@echo "Scanning image: $(SCAN_IMAGE)"
	@mkdir -p $(SCAN_RESULTS_DIR)
	@if ! command -v clairctl >/dev/null 2>&1; then \
		echo ""; \
		echo "clairctl is required for vulnerability scanning but is not installed."; \
		echo "Install command: go install github.com/quay/clair/v4/cmd/clairctl@latest"; \
		echo ""; \
		read -p "Install clairctl now? [y/N] " -n 1 -r; \
		echo ""; \
		if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
			echo "Installing clairctl..."; \
			go install github.com/quay/clair/v4/cmd/clairctl@latest; \
			echo "clairctl installed successfully"; \
		else \
			echo "Scan cancelled. Install clairctl manually to proceed."; \
			exit 1; \
		fi; \
	fi
	@echo "Running Clair scan (this may take several minutes)..."
	@echo "Pushing image to registry (localhost:5000)..."
	@podman tag localhost/$(SCAN_IMAGE) localhost:5000/$(SCAN_IMAGE)
	@podman push --tls-verify=false localhost:5000/$(SCAN_IMAGE) >/dev/null
	@echo "Scanning image from registry..."
	@clairctl report --host http://localhost:6060 localhost:5000/$(SCAN_IMAGE) 2>&1 | tee $(SCAN_RESULTS_DIR)/$(shell echo $(SCAN_IMAGE) | tr ':/' '_').txt
	@echo "Cleaning up tagged image..."
	@podman rmi localhost:5000/$(SCAN_IMAGE) >/dev/null 2>&1 || true
	@echo "Scan complete. Results saved to $(SCAN_RESULTS_DIR)/"

.PHONY: scan-micro
scan-micro: clair-validate build-micro-local
	@$(MAKE) clair-scan SCAN_IMAGE=$(IMAGE_NAME)-micro:$(ARCHITECTURE)

.PHONY: scan-minimal
scan-minimal: clair-validate build-minimal-local
	@$(MAKE) clair-scan SCAN_IMAGE=$(IMAGE_NAME)-minimal:$(ARCHITECTURE)

.PHONY: scan-full
scan-full: clair-validate build-full-local
	@$(MAKE) clair-scan SCAN_IMAGE=$(IMAGE_NAME):$(ARCHITECTURE)

.PHONY: scan-all
scan-all: scan-micro scan-minimal scan-full

# Validate environment before scanning
.PHONY: clair-validate
clair-validate:
	@echo "Validating environment for Clair scanning..."
ifdef REGISTRY_AUTH_FILE
	@if [ ! -f "$(REGISTRY_AUTH_FILE)" ]; then \
		echo "ERROR: REGISTRY_AUTH_FILE is set but file does not exist: $(REGISTRY_AUTH_FILE)"; \
		echo "Either:"; \
		echo "  1. Unset REGISTRY_AUTH_FILE: unset REGISTRY_AUTH_FILE"; \
		echo "  2. Create/fix the auth file"; \
		echo "  3. Point to valid file: export REGISTRY_AUTH_FILE=/path/to/valid/file"; \
		exit 1; \
	fi
endif
ifndef GITHUB_TOKEN
	@echo "ERROR: GITHUB_TOKEN is not set"
	@echo "Run: GITHUB_TOKEN=\"\$$(cat ~/.config/github/token)\" make $(MAKECMDGOALS)  # Substitute your token path"
	@exit 1
endif
	@echo "Checking if Clair is running..."
	@if ! podman pod exists clair-scanner 2>/dev/null; then \
		echo "ERROR: Clair pod is not running"; \
		echo "Start Clair: make clair-start"; \
		echo "Or use the all-in-one workflow: make clair-check"; \
		exit 1; \
	fi
	@if [ "$$(podman inspect clair-scanner-clair-service --format '{{.State.Health.Status}}' 2>/dev/null)" != "healthy" ]; then \
		echo "ERROR: Clair is not ready"; \
		echo ""; \
		echo "Clair pod is running but not healthy. This usually means:"; \
		echo "  1. Clair is still initializing (downloading vulnerability databases)"; \
		echo "     Check progress: podman logs -f clair-scanner-clair-service"; \
		echo "  2. Clair failed to start"; \
		echo "     Check errors: podman logs clair-scanner-clair-service | grep -i error"; \
		echo ""; \
		echo "Wait for Clair to finish initializing, then try again."; \
		echo "Initialization typically takes 2-5 minutes on first run."; \
		exit 1; \
	fi
	@echo "✓ Environment validation passed"

# Ephemeral scan: start Clair, scan all images, stop Clair
.PHONY: clair-check
clair-check: clair-validate clair-start
	@echo "Running comprehensive vulnerability scan..."
	@if ! $(MAKE) scan-all; then \
		echo "ERROR: Image scanning failed"; \
		$(MAKE) clair-stop; \
		exit 1; \
	fi
	@$(MAKE) clair-stop
	@echo "Vulnerability scanning complete. Review $(SCAN_RESULTS_DIR)/ for details."

