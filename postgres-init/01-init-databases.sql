-- Create separate databases for each microservice
-- This script runs automatically when the PostgreSQL container is first initialized

-- Database for budget analyzer (transactions, categories, budgets, etc.)
CREATE DATABASE budget_analyzer;
GRANT ALL PRIVILEGES ON DATABASE budget_analyzer TO budget_analyzer;

-- Database for currency service (exchange rates, currency data)
CREATE DATABASE currency;
GRANT ALL PRIVILEGES ON DATABASE currency TO budget_analyzer;

-- Database for permission service (RBAC, roles, delegations)
CREATE DATABASE permission;
GRANT ALL PRIVILEGES ON DATABASE permission TO budget_analyzer;

-- You can add more databases here as you add more microservices
-- Example:
-- CREATE DATABASE authentication;
-- GRANT ALL PRIVILEGES ON DATABASE authentication TO budget_analyzer;
