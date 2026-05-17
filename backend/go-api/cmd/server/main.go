package main

import (
	"context"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/rs/zerolog"

	"github.com/onchain-consent/backend/go-api/internal/api"
	"github.com/onchain-consent/backend/go-api/internal/config"
	qdrantclient "github.com/onchain-consent/backend/go-api/internal/qdrant"
	redisclient "github.com/onchain-consent/backend/go-api/internal/redis"
	"github.com/onchain-consent/backend/go-api/internal/worker"
)

func main() {
	logger := zerolog.New(zerolog.ConsoleWriter{Out: os.Stdout, TimeFormat: time.RFC3339}).
		With().
		Timestamp().
		Caller().
		Logger()

	cfg := config.Load()

	logLevel, err := zerolog.ParseLevel(cfg.LogLevel)
	if err != nil {
		logLevel = zerolog.InfoLevel
	}
	zerolog.SetGlobalLevel(logLevel)

	logger.Info().Str("listen_addr", cfg.ListenAddr).Msg("starting consent management API server")

	qdrantClient, err := qdrantclient.NewClient(cfg.Qdrant, &logger)
	if err != nil {
		logger.Warn().Err(err).Msg("Qdrant client initialization failed, continuing without")
		qdrantClient = nil
	}

	redisClient, err := redisclient.NewClient(cfg.Redis, &logger)
	if err != nil {
		logger.Warn().Err(err).Msg("Redis client initialization failed, continuing without")
		redisClient = nil
	}

	handler, err := api.NewHandler(cfg, qdrantClient, redisClient, &logger)
	if err != nil {
		logger.Fatal().Err(err).Msg("failed to create handler")
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	workerPool := worker.NewPool(ctx, cfg.Worker.Count, cfg.Worker.QueueSize, &logger)
	worker.RegisterTaskHandlers(workerPool, cfg, qdrantClient, redisClient)

	if cfg.LogLevel == "debug" {
		gin.SetMode(gin.DebugMode)
	} else {
		gin.SetMode(gin.ReleaseMode)
	}

	r := gin.New()
	r.Use(gin.Recovery())

	api.RegisterRoutes(r, handler, &logger)

	srv := &http.Server{
		Addr:    cfg.ListenAddr,
		Handler: r,
	}

	go func() {
		logger.Info().Str("addr", cfg.ListenAddr).Msg("HTTP server listening")
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Fatal().Err(err).Msg("HTTP server error")
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	logger.Info().Msg("shutting down server...")

	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		logger.Error().Err(err).Msg("HTTP server shutdown error")
	}

	workerPool.Shutdown()

	if qdrantClient != nil {
		qdrantClient.Close()
	}
	if redisClient != nil {
		redisClient.Close()
	}

	logger.Info().Msg("server stopped")
}
