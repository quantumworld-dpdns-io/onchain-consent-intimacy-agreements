package config

import (
	"os"
	"strconv"
	"time"
)

type Config struct {
	ListenAddr string
	LogLevel   string
	MCPPort    string

	Chains ChainConfig

	Qdrant   QdrantConfig
	Redis    RedisConfig
	Database DatabaseConfig
	CORS     CORSConfig
	Worker   WorkerConfig

	JWTSecret string
	APIKey    string

	SolanaRPC string

	RustZKURL string
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
	URL               string
	APIKey            string
	CollectionName    string
	VectorSize        int
	ReplicationFactor int
	CloudMode         bool
	ReadTimeout       time.Duration
	WriteTimeout      time.Duration
}

type RedisConfig struct {
	URL      string
	Password string
	DB       int
}

type DatabaseConfig struct {
	URL string
}

type CORSConfig struct {
	AllowOrigins []string
}

type WorkerConfig struct {
	Count     int
	QueueSize int
}

func Load() *Config {
	return &Config{
		ListenAddr: getEnv("LISTEN_ADDR", ":8080"),
		LogLevel:   getEnv("LOG_LEVEL", "info"),
		MCPPort:    getEnv("MCP_PORT", "8081"),
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
		CORS: CORSConfig{
			AllowOrigins: []string{"*"},
		},
		Worker: WorkerConfig{
			Count:     getEnvInt("WORKER_COUNT", 4),
			QueueSize: getEnvInt("WORKER_QUEUE_SIZE", 100),
		},
		JWTSecret: getEnv("JWT_SECRET", "dev-secret-change-in-production"),
		APIKey:    getEnv("API_KEY", "dev-key-change-in-production"),
		SolanaRPC: getEnv("SOLANA_RPC_URL", ""),
		RustZKURL: getEnv("RUST_ZK_URL", "http://localhost:3000"),
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
