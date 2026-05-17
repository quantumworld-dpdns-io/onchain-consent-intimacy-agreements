package config

import (
	"os"
	"strconv"
	"time"
)

type Config struct {
	LogLevel          string
	PollIntervalSeconds int
	BackfillFromBlock uint64
	Chains            ChainConfig
	Qdrant            QdrantConfig
	Redis             RedisConfig
}

type ChainConfig struct {
	SepoliaRPC          string
	BSCTestnetRPC       string
	AmoyRPC             string
	PalmTestnetRPC      string
	BaseSepoliaRPC      string
	SepoliaRegistry     string
	BSCTestnetRegistry  string
	AmoyRegistry        string
	PalmTestnetRegistry string
	BaseSepoliaRegistry string
}

type QdrantConfig struct {
	URL            string
	APIKey         string
	CollectionName string
	VectorSize     int
	CloudMode      bool
	ReadTimeout    time.Duration
	WriteTimeout   time.Duration
}

type RedisConfig struct {
	URL      string
	Password string
	DB       int
}

func Load() *Config {
	return &Config{
		LogLevel:            getEnv("LOG_LEVEL", "info"),
		PollIntervalSeconds: getEnvInt("POLL_INTERVAL_SECONDS", 12),
		BackfillFromBlock:   uint64(getEnvInt("BACKFILL_FROM_BLOCK", 0)),
		Chains: ChainConfig{
			SepoliaRPC:          getEnv("SEPOLIA_RPC_URL", ""),
			BSCTestnetRPC:       getEnv("BSC_TESTNET_RPC_URL", ""),
			AmoyRPC:             getEnv("AMOY_RPC_URL", ""),
			PalmTestnetRPC:      getEnv("PALM_TESTNET_RPC_URL", ""),
			BaseSepoliaRPC:      getEnv("BASE_SEPOLIA_RPC_URL", ""),
			SepoliaRegistry:     getEnv("SEPOLIA_REGISTRY", ""),
			BSCTestnetRegistry:  getEnv("BSC_TESTNET_REGISTRY", ""),
			AmoyRegistry:        getEnv("AMOY_REGISTRY", ""),
			PalmTestnetRegistry: getEnv("PALM_TESTNET_REGISTRY", ""),
			BaseSepoliaRegistry: getEnv("BASE_SEPOLIA_REGISTRY", ""),
		},
		Qdrant: QdrantConfig{
			URL:            getEnv("QDRANT_URL", "http://localhost:6333"),
			APIKey:         getEnv("QDRANT_API_KEY", ""),
			CollectionName: getEnv("QDRANT_COLLECTION", "consent_agreements"),
			VectorSize:     getEnvInt("QDRANT_VECTOR_SIZE", 384),
			CloudMode:      getEnv("QDRANT_MODE", "self-hosted") == "cloud",
			ReadTimeout:    30 * time.Second,
			WriteTimeout:   30 * time.Second,
		},
		Redis: RedisConfig{
			URL:      getEnv("REDIS_URL", "redis://localhost:6379"),
			Password: getEnv("REDIS_PASSWORD", ""),
			DB:       getEnvInt("REDIS_DB", 0),
		},
	}
}

func getEnv(key, defaultVal string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return defaultVal
}

func getEnvInt(key string, defaultVal int) int {
	if v := os.Getenv(key); v != "" {
		if i, err := strconv.Atoi(v); err == nil {
			return i
		}
	}
	return defaultVal
}
