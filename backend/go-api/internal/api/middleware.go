package api

import (
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/rs/zerolog"

	"github.com/onchain-consent/backend/go-api/internal/config"
)

type RateLimiter struct {
	mu       sync.Mutex
	buckets  map[string]*TokenBucket
	rate     int
	burst    int
}

type TokenBucket struct {
	tokens    float64
	lastCheck time.Time
	capacity  float64
	rate      float64
}

func NewRateLimiter(rate, burst int) *RateLimiter {
	return &RateLimiter{
		buckets: make(map[string]*TokenBucket),
		rate:    rate,
		burst:   burst,
	}
}

func (rl *RateLimiter) Allow(key string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	bucket, exists := rl.buckets[key]
	if !exists {
		bucket = &TokenBucket{
			tokens:   float64(rl.burst),
			capacity: float64(rl.burst),
			rate:     float64(rl.rate),
		}
		rl.buckets[key] = bucket
	}

	now := time.Now()
	elapsed := now.Sub(bucket.lastCheck).Seconds()
	bucket.tokens += elapsed * bucket.rate
	if bucket.tokens > bucket.capacity {
		bucket.tokens = bucket.capacity
	}
	bucket.lastCheck = now

	if bucket.tokens >= 1 {
		bucket.tokens--
		return true
	}

	return false
}

func AuthMiddleware(cfg *config.Config, logger *zerolog.Logger) gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, ErrorResponse{
				Error: "missing authorization header",
				Code:  http.StatusUnauthorized,
			})
			return
		}

		if strings.HasPrefix(authHeader, "Bearer ") {
			tokenStr := strings.TrimPrefix(authHeader, "Bearer ")

			if tokenStr == cfg.APIKey {
				c.Set("auth_type", "api_key")
				c.Set("api_key", tokenStr)
				c.Next()
				return
			}

			token, err := jwt.Parse(tokenStr, func(token *jwt.Token) (interface{}, error) {
				if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
					return nil, jwt.ErrSignatureInvalid
				}
				return []byte(cfg.JWTSecret), nil
			})

			if err != nil || !token.Valid {
				logger.Warn().Err(err).Str("path", c.Request.URL.Path).Msg("invalid JWT token")
				c.AbortWithStatusJSON(http.StatusUnauthorized, ErrorResponse{
					Error: "invalid or expired token",
					Code:  http.StatusUnauthorized,
				})
				return
			}

			claims, ok := token.Claims.(jwt.MapClaims)
			if ok {
				c.Set("auth_type", "jwt")
				c.Set("sub", claims["sub"])
				c.Set("roles", claims["roles"])
			}

			c.Next()
			return
		}

		if authHeader == cfg.APIKey {
			c.Set("auth_type", "api_key")
			c.Next()
			return
		}

		c.AbortWithStatusJSON(http.StatusUnauthorized, ErrorResponse{
			Error: "invalid authorization",
			Code:  http.StatusUnauthorized,
		})
	}
}

func RateLimitMiddleware(rl *RateLimiter) gin.HandlerFunc {
	return func(c *gin.Context) {
		key := c.ClientIP()

		if !rl.Allow(key) {
			c.AbortWithStatusJSON(http.StatusTooManyRequests, ErrorResponse{
				Error: "rate limit exceeded",
				Code:  http.StatusTooManyRequests,
			})
			return
		}

		c.Next()
	}
}

func ChainMiddleware() gin.HandlerFunc {
	supportedChains := map[string]bool{
		"sepolia":      true,
		"bsc-testnet":  true,
		"amoy":         true,
		"palm-testnet": true,
		"base-sepolia": true,
	}

	return func(c *gin.Context) {
		chain := c.Param("chain")
		if chain != "" {
			if !supportedChains[chain] {
				c.AbortWithStatusJSON(http.StatusBadRequest, ErrorResponse{
					Error:   "unsupported chain",
					Code:    http.StatusBadRequest,
					Details: "supported chains: sepolia, bsc-testnet, amoy, palm-testnet, base-sepolia",
				})
				return
			}
			c.Set("chain", chain)
		}

		c.Next()
	}
}

func CORSMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, DELETE, PATCH")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}

		c.Next()
	}
}

func RequestLogger(logger *zerolog.Logger) gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.Request.URL.Path
		raw := c.Request.URL.RawQuery

		c.Next()

		latency := time.Since(start)
		status := c.Writer.Status()
		method := c.Request.Method

		if raw != "" {
			path = path + "?" + raw
		}

		event := logger.Info()
		if status >= 400 {
			event = logger.Warn()
		}
		if status >= 500 {
			event = logger.Error()
		}

		event.
			Str("method", method).
			Str("path", path).
			Int("status", status).
			Dur("latency", latency).
			Int("size", c.Writer.Size()).
			Msg("request completed")
	}
}
