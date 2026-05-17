package redis

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
	"github.com/rs/zerolog"

	"github.com/onchain-consent/backend/event-indexer/internal/config"
)

type ConsentCache struct {
	ConsentID  string   `json:"consent_id"`
	Parties    []string `json:"parties"`
	Scopes     []string `json:"scopes"`
	ValidFrom  uint64   `json:"valid_from"`
	ValidUntil uint64   `json:"valid_until"`
	Revoked    bool     `json:"revoked"`
	Chain      string   `json:"chain"`
	TxHash     string   `json:"tx_hash"`
	CreatedAt  uint64   `json:"created_at"`
}

type Client struct {
	rdb    *redis.Client
	config config.RedisConfig
	logger *zerolog.Logger
}

func NewClient(cfg config.RedisConfig, logger *zerolog.Logger) (*Client, error) {
	opts, err := redis.ParseURL(cfg.URL)
	if err != nil {
		return nil, fmt.Errorf("failed to parse Redis URL: %w", err)
	}

	if cfg.Password != "" {
		opts.Password = cfg.Password
	}
	if cfg.DB != 0 {
		opts.DB = cfg.DB
	}

	rdb := redis.NewClient(opts)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := rdb.Ping(ctx).Err(); err != nil {
		return nil, fmt.Errorf("failed to connect to Redis: %w", err)
	}

	return &Client{
		rdb:    rdb,
		config: cfg,
		logger: logger,
	}, nil
}

func (c *Client) Close() error {
	return c.rdb.Close()
}

func (c *Client) CacheConsent(ctx context.Context, consent *ConsentCache, ttl time.Duration) error {
	data, err := json.Marshal(consent)
	if err != nil {
		return fmt.Errorf("failed to marshal consent: %w", err)
	}

	key := fmt.Sprintf("consent:%s:%s", consent.Chain, consent.ConsentID)
	if err := c.rdb.Set(ctx, key, data, ttl).Err(); err != nil {
		return fmt.Errorf("failed to cache consent in Redis: %w", err)
	}

	return nil
}

func (c *Client) InvalidateConsent(ctx context.Context, chain, consentID string) error {
	key := fmt.Sprintf("consent:%s:%s", chain, consentID)
	if err := c.rdb.Del(ctx, key).Err(); err != nil {
		return fmt.Errorf("failed to invalidate consent cache: %w", err)
	}
	return nil
}
