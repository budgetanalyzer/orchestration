# Plan: Cross-Platform CI Testing

## Goal

Validate that `setup.sh` and related scripts work correctly on Linux, macOS, and Windows using GitHub Actions.

## Background

### What is GitHub Actions?

GitHub's built-in CI/CD system. When you push code, GitHub automatically:
1. Detects workflow files in `.github/workflows/`
2. Spins up VMs for each platform in your matrix
3. Runs your defined steps
4. Reports pass/fail status

### Why cross-platform testing?

- `setup.sh` uses bash, which behaves differently across OSes
- macOS has different default tools (BSD vs GNU)
- Windows requires Git Bash or WSL
- Catch compatibility issues before users hit them

## Implementation

### File to Create

`.github/workflows/test-setup.yml`

### Workflow Configuration

```yaml
name: Test Setup Script

on:
  push:
    branches: [main, setup]
    paths:
      - 'setup.sh'
      - 'scripts/**'
      - 'tests/**'
      - '.github/workflows/test-setup.yml'
  pull_request:
    branches: [main]
  workflow_dispatch:  # Manual trigger button
```

### Matrix Strategy

```yaml
jobs:
  test-setup:
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-14, windows-latest]
```

- **ubuntu-latest**: Linux (free, unlimited minutes for public repos)
- **macos-14**: M1 macOS (free for public repos)
- **windows-latest**: Windows Server with Git Bash (free for public repos)

### Test Steps

#### 1. Syntax Validation (all platforms)

```yaml
- name: Validate script syntax
  run: |
    bash -n setup.sh
    find scripts -name "*.sh" -exec bash -n {} \;
    find tests -name "*.sh" -exec bash -n {} \;
```

Catches syntax errors before runtime.

#### 2. Prerequisite Detection (all platforms)

```yaml
- name: Test prerequisite detection
  run: |
    # setup.sh should fail gracefully when tools are missing
    if ./setup.sh 2>&1; then
      echo "ERROR: Should have failed due to missing prerequisites"
      exit 1
    fi
    echo "✓ Correctly detected missing prerequisites"
```

Validates the script fails gracefully with helpful messages when tools aren't installed.

#### 3. Integration Test Infrastructure (Linux only)

```yaml
- name: Verify test infrastructure
  if: runner.os == 'Linux'
  run: |
    # Check that DinD test files exist
    test -f tests/setup-flow/docker-compose.test.yml
    test -f tests/setup-flow/Dockerfile.test-env
    test -f tests/setup-flow/test-setup-flow.sh
```

The full integration test (Kind cluster, Envoy Gateway, etc.) requires all repos cloned and takes 5-10 minutes. This is better run locally via `./tests/setup-flow/run-test.sh`.

### Summary Job

```yaml
test-summary:
  needs: test-setup
  runs-on: ubuntu-latest
  if: always()
  steps:
    - name: Check results
      run: |
        if [ "${{ needs.test-setup.result }}" == "success" ]; then
          echo "✓ All platforms passed"
        else
          exit 1
        fi
```

## What You'll See in GitHub

### Actions Tab

After pushing, go to your repo's **Actions** tab to see:
- Workflow runs with status (green check / red X)
- Click a run to see each platform's results
- Expand steps to see detailed output

### Pull Request Checks

PRs will show status checks:
```
✓ Test Setup Script (ubuntu-latest)
✓ Test Setup Script (macos-14)
✓ Test Setup Script (windows-latest)
```

Must pass before merging (if you enable branch protection).

## Future Enhancements

1. **Install prerequisites and run further** - Use Homebrew on macOS, Chocolatey on Windows
2. **Test specific functions** - Extract and unit test helper functions
3. **Cross-platform compatibility layer** - Detect OS and use appropriate commands

## Usage

After implementation:

```bash
# Workflow runs automatically on push/PR
# Or trigger manually from GitHub Actions tab

# View results
# Go to: https://github.com/budgetanalyzer/orchestration/actions
```

## Directory Structure After Implementation

```
.github/
└── workflows/
    └── test-setup.yml

tests/
└── setup-flow/           # Existing local DinD tests
    ├── run-test.sh
    ├── test-setup-flow.sh
    └── ...
```
