# Testing Guide - OCM Container

## Overview

This document describes the testing strategy for the ocm-container project, covering unit testing, integration testing, security scanning, and CI/CD validation.

## Unit Testing

### Running Tests

```bash
make test                  # Run all unit tests
make test TESTOPTS="-v"    # Verbose output
make coverage              # Generate coverage report
```

### Test Structure

- **Framework**: Ginkgo v2 + Gomega
- **Location**: `*_test.go` files alongside source code
- **Suites**: `*_suite_test.go` files for package test suites

### Test Coverage Areas

#### 1. OCM Integration (`pkg/ocm/`)

Tests for OCM API authentication and interactions:
- Token validation and refresh
- OAuth authentication flows
- Environment switching (prod, stage, int)
- API client initialization
- Error handling for auth failures

#### 2. Backplane Integration (`pkg/backplane/`)

Tests for OpenShift Backplane cluster access:
- Cluster login workflows
- Session management
- Credential handling
- Backplane API interactions

#### 3. Container Engine (`pkg/engine/`)

Tests for container runtime abstraction:
- Podman/Docker detection
- Container operations (run, stop, remove)
- Image building and tagging
- Volume mounting
- Network configuration

#### 4. Configuration Management (`cmd/`, `pkg/`)

Tests for configuration loading and validation:
- Viper configuration file parsing
- Environment variable precedence
- CLI flag handling
- Feature set mounting logic
- Default value validation

#### 5. Feature Sets (`pkg/featureSet/`)

Tests for modular feature mounting:
- AWS credentials and config mounting
- GCloud SDK integration
- JIRA CLI configuration
- PagerDuty integration
- OpsUtils mounting
- Custom CA bundle handling
- Persistent history preservation
- Personalization (bashrc/dotfiles)

### Test Files to Create/Update

Current test coverage:
- `pkg/ocm/auth_test.go` - OAuth and token handling
- `pkg/engine/engine_test.go` - Container engine operations
- `pkg/ocmcontainer/container_test.go` - Main container logic
- `pkg/featureSet/*_test.go` - Feature set mounting logic

### Test Requirements

- **All tests must pass** before each commit
- Use Ginkgo/Gomega framework (already in place)
- Mock external dependencies (OCM API, container runtime)
- Cover both success and failure paths
- Test edge cases (missing config, invalid credentials, etc.)

### Example Test Structure

```go
var _ = Describe("OCM Authentication", func() {
    Context("when initializing with valid credentials", func() {
        It("should successfully authenticate", func() {
            // Test implementation
            Expect(result).To(Succeed())
        })
    })

    Context("when credentials are invalid", func() {
        It("should return appropriate error", func() {
            // Test implementation
            Expect(err).To(HaveOccurred())
        })
    })
})
```

## Integration Testing

### Container Build Testing

Before running container builds, export GitHub token:

```bash
export GITHUB_TOKEN="$(cat ~/.config/github/token)"
```

Build validation commands:

```bash
make check-image-build     # Full build validation
make build-all             # Build all variants (micro, minimal, full)
make build-micro           # Build micro image only
make build-minimal         # Build minimal image only
make build-full            # Build full image only
```

### Multi-Architecture Testing

Test both amd64 and arm64 builds:

```bash
# Build for specific architecture
make build ARCHITECTURE=amd64
make build ARCHITECTURE=arm64

# Build multi-arch manifest
make push-manifest         # Requires authenticated registry
```

### Functional Testing

After building images, test core functionality:

#### 1. Basic Container Execution

```bash
# Test container starts
./ocm-container --help

# Test version display
./ocm-container --version
```

#### 2. OCM Integration

```bash
# Test OCM login (requires valid token)
ocm-container -- ocm version
ocm-container -- ocm whoami
```

#### 3. Backplane Cluster Login

```bash
# Test cluster login (requires cluster ID)
ocm-container -c <cluster-id>

# Verify OpenShift CLI access
oc whoami
oc get nodes
```

#### 4. Feature Set Mounting

Test each feature independently:

```bash
# AWS credentials
ocm-container --aws-profile <profile>
# Verify: ls ~/.aws/

# GCloud configuration
ocm-container --gcp-credentials <file>
# Verify: gcloud config list

# JIRA CLI
ocm-container --jira-token <token>
# Verify: jira issue list

# PagerDuty
ocm-container --pd-token <token>
# Verify: pd incident list

# OpsUtils
ocm-container --ops-utils
# Verify: ls /root/utils/

# Persistent histories
ocm-container -c <cluster-id> --persist-histories
# Verify: history shows previous cluster session
```

## Security Testing

### Vulnerability Scanning with Clair

#### Quick Scan

```bash
# Ephemeral scan (start Clair, scan all images, stop Clair)
make clair-check
```

#### Manual Workflow

```bash
# Start Clair scanning environment
make clair-start

# Build and scan images
make scan-micro      # Scan micro image
make scan-minimal    # Scan minimal image
make scan-full       # Scan full image
make scan-all        # Scan all variants

# Stop Clair environment
make clair-stop
```

### Scan Result Interpretation

Vulnerabilities are categorized by severity:

- **Critical/High**: Must be addressed immediately
  - Block PR merges until resolved
  - Require base image or dependency updates

- **Medium**: Should be addressed in maintenance cycles
  - Plan remediation in next sprint
  - Document and track

- **Low/Unknown**: Document and monitor
  - Low risk or unconfirmed vulnerabilities
  - Update when new versions available

### Pre-commit Security Checklist

```bash
# 1. Build all images
export GITHUB_TOKEN="$(cat ~/.config/github/token)"
make build-all

# 2. Run vulnerability scan
make clair-check

# 3. Review critical/high vulnerabilities
grep -i "critical\|high" scan-results/*.txt

# 4. Address vulnerabilities if found
# 5. Re-scan to verify fixes
make clair-check
```

## Binary Testing

### Local Build

```bash
# Build Go binary for current platform
make build-binary

# Verify binary works
./build/ocm-container --version
./build/ocm-container --help
```

### Cross-Platform Testing

```bash
# Build snapshot for all platforms
make build-snapshot

# GoReleaser builds:
# - Linux amd64
# - Linux arm64
# - Darwin amd64 (macOS Intel)
# - Darwin arm64 (macOS Apple Silicon)
```

### Binary Functionality Testing

```bash
# Test configuration initialization
./build/ocm-container configure init

# Verify config file created
cat ~/.config/ocm-container/ocm-container.yaml

# Test container execution
./build/ocm-container -- ocm version
```

## CI/CD Testing

### Pre-PR Validation

Run all checks before creating pull request:

```bash
make pr-check              # Run PR validation checks
make lint                  # Static analysis with golangci-lint
make fmt                   # Format check with gofmt
make test                  # Unit tests
make build-binary          # Binary build
```

### CI Pipeline Validation

The project uses Tekton CI/CD pipeline (`.tekton/` directory):

- **Pull Request Check** (`.ci/pull-request-check.sh`)
  - Linting validation
  - Unit test execution
  - Binary build verification
  - Container image build

- **Container Build** (Tekton tasks)
  - Multi-stage Containerfile build
  - Multi-architecture manifest creation
  - Clair vulnerability scanning
  - Image signing with Sigstore

### Manual Tekton Testing

To test pipeline locally (requires Tekton CLI):

```bash
# Validate Tekton resources
tkn task validate -f .tekton/tasks/

# Dry-run pipeline
tkn pipeline start ocm-container-build --dry-run
```

## Test Maintenance

### Adding New Tests

When adding new functionality:

1. **Create test file**: `<package>/<feature>_test.go`
2. **Use Ginkgo structure**: Describe/Context/It blocks
3. **Use Gomega matchers**: Expect, Eventually, Consistently
4. **Mock dependencies**: Use interfaces for external dependencies
5. **Test success and failure**: Cover both paths
6. **Test edge cases**: nil values, empty strings, invalid input

### Test Dependencies

The project uses:
- `github.com/onsi/ginkgo/v2` - BDD testing framework
- `github.com/onsi/gomega` - Matcher/assertion library
- `github.com/spf13/afero` - Filesystem mocking
- `github.com/golang/mock` - Mock generation

### Updating Test Coverage

```bash
# Generate coverage report
make coverage

# View coverage by package
go tool cover -func=coverage.out

# Generate HTML coverage report
go tool cover -html=coverage.out -o coverage.html
```

## Troubleshooting

### Common Test Issues

#### 1. GITHUB_TOKEN not set

**Problem**: Container builds fail with authentication errors

**Solution**: Export GitHub token before building
```bash
export GITHUB_TOKEN="$(cat ~/.config/github/token)"
```

#### 2. Clair timeout errors

**Problem**: Clair scans timeout or hang

**Solution**: Increase Clair initialization time
```bash
# Edit utils/clair/clair-pod.sh
# Increase sleep duration from 60 to 120 seconds
```

#### 3. Test flakiness

**Problem**: Tests pass/fail intermittently

**Solution**: Use `Eventually()` for async operations
```go
Eventually(func() bool {
    return condition
}, "5s", "100ms").Should(BeTrue())
```

#### 4. Container build failures

**Problem**: Image builds fail with base image errors

**Solution**: Verify base image availability
```bash
podman pull registry.access.redhat.com/ubi10/ubi:latest
```

#### 5. Go module issues

**Problem**: Dependency resolution errors

**Solution**: Clean and rebuild modules
```bash
go clean -modcache
go mod tidy
make build-binary
```

## Performance Testing

### Build Time Benchmarks

Expected build times on modern hardware:

- **Micro image**: ~5 minutes
- **Minimal image**: ~8 minutes
- **Full image**: ~15 minutes

Factors affecting build time:
- Network bandwidth (package downloads)
- CPU cores (parallel compilation)
- Docker layer cache (cached builds faster)

### Resource Requirements

Minimum system requirements:

- **RAM**: 4GB minimum, 8GB recommended
- **Disk**: 20GB free space for multi-arch builds
- **Network**: Stable connection for dependency downloads
- **CPU**: 4+ cores recommended for parallel builds

## Continuous Improvement

### Test Coverage Goals

- **Target**: 80% code coverage across all packages
- **Critical paths**: 100% coverage (auth, container engine)
- **New features**: Must include unit tests before merge
- **Bug fixes**: Must include regression tests

### Test Quality Metrics

- **Reliability**: Tests pass consistently (no flakiness)
- **Speed**: Unit tests complete in < 30 seconds
- **Maintainability**: Tests are easy to understand and update
- **Independence**: Tests don't depend on external services

## References

- [Ginkgo Documentation](https://onsi.github.io/ginkgo/)
- [Gomega Matchers](https://onsi.github.io/gomega/)
- [Vulnerability Scanning Guide](docs/vulnerability-scanning.md)
- [Tekton Documentation](https://tekton.dev/docs/)
- [GoReleaser Documentation](https://goreleaser.com/)
