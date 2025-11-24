# CI/CD Workflows

This document describes the GitHub Actions CI/CD setup for Budget Analyzer services.

## Overview

All backend services use GitHub Actions for continuous integration. Each service has its own workflow that:

- Builds on every push to `main` and pull requests
- Runs all tests (unit, integration)
- Enforces code quality (Spotless formatting, Checkstyle)
- Uploads test results and build artifacts

## Services with CI

| Service | Status Badge |
|---------|-------------|
| service-common | [![Build](https://github.com/budgetanalyzer/service-common/actions/workflows/build.yml/badge.svg)](https://github.com/budgetanalyzer/service-common/actions/workflows/build.yml) |
| token-validation-service | [![Build](https://github.com/budgetanalyzer/token-validation-service/actions/workflows/build.yml/badge.svg)](https://github.com/budgetanalyzer/token-validation-service/actions/workflows/build.yml) |
| session-gateway | [![Build](https://github.com/budgetanalyzer/session-gateway/actions/workflows/build.yml/badge.svg)](https://github.com/budgetanalyzer/session-gateway/actions/workflows/build.yml) |
| transaction-service | [![Build](https://github.com/budgetanalyzer/transaction-service/actions/workflows/build.yml/badge.svg)](https://github.com/budgetanalyzer/transaction-service/actions/workflows/build.yml) |
| currency-service | [![Build](https://github.com/budgetanalyzer/currency-service/actions/workflows/build.yml/badge.svg)](https://github.com/budgetanalyzer/currency-service/actions/workflows/build.yml) |
| permission-service | [![Build](https://github.com/budgetanalyzer/permission-service/actions/workflows/build.yml/badge.svg)](https://github.com/budgetanalyzer/permission-service/actions/workflows/build.yml) |

## Workflow Details

### Triggers

All workflows trigger on:

- **Push to main**: Runs CI on every merge/commit
- **Pull requests**: Validates changes before merge
- **Manual dispatch**: Allows manual triggering via GitHub UI

### Build Steps

1. **Checkout**: Clone the repository
2. **Setup JDK 24**: Install Temurin JDK 24
3. **Setup Gradle**: Configure Gradle with caching
4. **Build service-common**: Clone and build the shared library (for services that depend on it)
5. **Build with Gradle**: Run `./gradlew build` which includes:
   - Compile Java source
   - Run Spotless formatting check
   - Run Checkstyle validation
   - Execute all tests
   - Package JAR
6. **Upload artifacts**: Save test results and JARs

### Code Quality

The build enforces code quality via:

- **Spotless**: Google Java Format (1.32.0)
- **Checkstyle**: Style rules from [checkstyle-config](https://github.com/budgetanalyzer/checkstyle-config)

### Dependencies

Backend services depend on `service-common`. Each workflow clones and builds service-common to Maven Local before building the service itself.

## Running Locally

To run the same checks locally:

```bash
# Full build with all checks
./gradlew build

# Just run tests
./gradlew test

# Check formatting (without fixing)
./gradlew spotlessCheck

# Fix formatting automatically
./gradlew spotlessApply

# Run checkstyle
./gradlew checkstyleMain checkstyleTest
```

## Future Enhancements

### Release Automation

Planned improvements include:

- **Semantic versioning** with [release-please](https://github.com/googleapis/release-please)
- **Automated changelog** generation from conventional commits
- **Docker image publishing** to GitHub Container Registry on release

### GitHub Packages

To improve build times and dependency management:

- Publish service-common to GitHub Packages
- Remove git clone step from service workflows
- Version service-common properly for releases

## Troubleshooting

### Build Failures

1. **Spotless check failed**: Run `./gradlew spotlessApply` locally to fix formatting
2. **Checkstyle violations**: Fix style issues reported in the build log
3. **Test failures**: Check test output in the uploaded artifacts
4. **service-common build failed**: Ensure service-common has no breaking changes

### Viewing Results

- Go to the repository's **Actions** tab
- Click on the failed workflow run
- Download the `test-results` artifact for detailed JUnit reports
