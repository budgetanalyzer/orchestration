#!/usr/bin/env bash
#
# Add GitHub topics to all Budget Analyzer repositories
# Uses GitHub REST API with curl (no gh CLI required)
#
# Prerequisites:
#   export GITHUB_TOKEN="your-personal-access-token"
#   Token needs 'repo' scope
#

set -euo pipefail

ORG="budgetanalyzer"

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "Error: GITHUB_TOKEN environment variable is required"
    echo "Create a token at: https://github.com/settings/tokens"
    echo "Token needs 'repo' scope"
    exit 1
fi

set_topics() {
    local repo="$1"
    shift
    local topics="$*"

    # Convert space-separated topics to JSON array
    local json_topics
    json_topics=$(printf '%s\n' $topics | jq -R . | jq -s '{"names": .}')

    echo "Setting topics for $repo..."

    local response
    response=$(curl -s -w "\n%{http_code}" -X PUT \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/$ORG/$repo/topics" \
        -d "$json_topics")

    local http_code
    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
        echo "  ✓ Success"
    else
        echo "  ✗ Failed (HTTP $http_code)"
        echo "$body" | jq -r '.message // .' 2>/dev/null || echo "$body"
        return 1
    fi
}

echo "Adding topics to Budget Analyzer repositories..."
echo ""

set_topics "orchestration" \
    microservices kubernetes tilt reference-architecture spring-boot oauth2 bff-pattern ai-assisted-development enterprise-security

set_topics "session-gateway" \
    bff spring-cloud-gateway oauth2 redis-session spring-boot

set_topics "token-validation-service" \
    jwt spring-boot oauth2 microservice

set_topics "transaction-service" \
    spring-boot microservice rest-api postgresql

set_topics "currency-service" \
    spring-boot microservice rest-api redis

set_topics "permission-service" \
    spring-boot microservice authorization rbac

set_topics "budget-analyzer-web" \
    react typescript vite casl frontend

set_topics "service-common" \
    spring-boot java shared-library

set_topics "checkstyle-config" \
    checkstyle java code-quality

set_topics "basic-repository-template" \
    template spring-boot

echo ""
echo "Done! Topics added to all repositories."
