package main

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"strconv"
	"time"

	"github.com/redis/go-redis/v9"
)

var (
	ErrSessionNotFound = errors.New("session not found")
	ErrSessionExpired  = errors.New("session expired")
)

// SessionData holds the resolved session fields from Redis.
type SessionData struct {
	UserID      string
	Roles       string
	Permissions string
	ExpiresAt   time.Time
}

// SessionStore wraps a Redis client for session lookups.
type SessionStore struct {
	client    *redis.Client
	keyPrefix string
}

// NewSessionStore creates a Redis-backed session store and verifies connectivity.
func NewSessionStore(cfg Config) (*SessionStore, error) {
	opts := &redis.Options{
		Addr:        cfg.RedisAddr,
		Password:    cfg.RedisPassword,
		PoolSize:    10,
		ReadTimeout: 100 * time.Millisecond,
	}

	if cfg.RedisTLS {
		opts.TLSConfig = &tls.Config{}
	}

	client := redis.NewClient(opts)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := client.Ping(ctx).Err(); err != nil {
		return nil, fmt.Errorf("redis connection failed: %w", err)
	}

	return &SessionStore{
		client:    client,
		keyPrefix: cfg.SessionKeyPrefix,
	}, nil
}

// LookupSession retrieves a session from Redis by ID.
// Returns ErrSessionNotFound if the key doesn't exist,
// ErrSessionExpired if the session has passed its expires_at.
func (s *SessionStore) LookupSession(ctx context.Context, sessionID string) (*SessionData, error) {
	key := s.keyPrefix + sessionID

	result, err := s.client.HGetAll(ctx, key).Result()
	if err != nil {
		return nil, fmt.Errorf("redis error: %w", err)
	}

	if len(result) == 0 {
		return nil, ErrSessionNotFound
	}

	expiresAtUnix, err := strconv.ParseInt(result["expires_at"], 10, 64)
	if err != nil {
		return nil, fmt.Errorf("invalid expires_at: %w", err)
	}

	expiresAt := time.Unix(expiresAtUnix, 0)
	if time.Now().After(expiresAt) {
		return nil, ErrSessionExpired
	}

	return &SessionData{
		UserID:      result["user_id"],
		Roles:       result["roles"],
		Permissions: result["permissions"],
		ExpiresAt:   expiresAt,
	}, nil
}

// Ping checks Redis connectivity for health checks.
func (s *SessionStore) Ping(ctx context.Context) error {
	return s.client.Ping(ctx).Err()
}
