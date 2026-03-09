package main

import "os"

// Config holds all ext-authz service configuration, loaded from environment variables.
type Config struct {
	RedisAddr         string
	RedisPassword     string
	RedisTLS          bool
	GRPCPort          string
	HealthPort        string
	SessionKeyPrefix  string
	SessionCookieName string
	EnforceMode       bool
	LogLevel          string
	LogFormat         string
}

func LoadConfig() Config {
	return Config{
		RedisAddr:         envOrDefault("REDIS_ADDR", "redis.infrastructure:6379"),
		RedisPassword:     envOrDefault("REDIS_PASSWORD", ""),
		RedisTLS:          envOrDefault("REDIS_TLS", "false") == "true",
		GRPCPort:          envOrDefault("GRPC_PORT", "9001"),
		HealthPort:        envOrDefault("HEALTH_PORT", "8090"),
		SessionKeyPrefix:  envOrDefault("SESSION_KEY_PREFIX", "extauthz:session:"),
		SessionCookieName: envOrDefault("SESSION_COOKIE_NAME", "SESSION"),
		EnforceMode:       envOrDefault("ENFORCE_MODE", "false") == "true",
		LogLevel:          envOrDefault("LOG_LEVEL", "info"),
		LogFormat:         envOrDefault("LOG_FORMAT", "json"),
	}
}

func envOrDefault(key, defaultVal string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return defaultVal
}
