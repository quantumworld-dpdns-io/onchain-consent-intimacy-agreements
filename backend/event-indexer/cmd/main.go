package main

import (
	"context"
	"fmt"
	"math/big"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/rs/zerolog"

	"github.com/onchain-consent/backend/event-indexer/internal/config"
	qdrantclient "github.com/onchain-consent/backend/event-indexer/internal/qdrant"
	redisclient "github.com/onchain-consent/backend/event-indexer/internal/redis"
)

type EventType string

const (
	EventConsentRegistered EventType = "ConsentRegistered"
	EventConsentRevoked    EventType = "ConsentRevoked"
	EventConsentExpired    EventType = "ConsentExpired"
)

type ChainListener struct {
	name          string
	rpcURL        string
	contractAddr  common.Address
	client        *ethclient.Client
	logger        zerolog.Logger
	startBlock    uint64
	backfillMode  bool
}

type EventHandler struct {
	cfg     *config.Config
	qdrant  *qdrantclient.Client
	redis   *redisclient.Client
	logger  zerolog.Logger
	mu      sync.Mutex
}

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

	logger.Info().Msg("starting event indexer")

	qdrant, err := qdrantclient.NewClient(cfg.Qdrant, &logger)
	if err != nil {
		logger.Warn().Err(err).Msg("Qdrant client initialization failed, continuing without")
		qdrant = nil
	}

	redis, err := redisclient.NewClient(cfg.Redis, &logger)
	if err != nil {
		logger.Warn().Err(err).Msg("Redis client initialization failed, continuing without")
		redis = nil
	}

	handler := &EventHandler{
		cfg:    cfg,
		qdrant: qdrant,
		redis:  redis,
		logger: logger,
	}

	chains := map[string]struct {
		rpcURL   string
		contract string
	}{
		"sepolia":      {cfg.Chains.SepoliaRPC, cfg.Chains.SepoliaRegistry},
		"bsc-testnet":  {cfg.Chains.BSCTestnetRPC, cfg.Chains.BSCTestnetRegistry},
		"amoy":         {cfg.Chains.AmoyRPC, cfg.Chains.AmoyRegistry},
		"palm-testnet": {cfg.Chains.PalmTestnetRPC, cfg.Chains.PalmTestnetRegistry},
		"base-sepolia": {cfg.Chains.BaseSepoliaRPC, cfg.Chains.BaseSepoliaRegistry},
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	var wg sync.WaitGroup

	for name, chain := range chains {
		if chain.rpcURL == "" || chain.contract == "" {
			logger.Warn().Str("chain", name).Msg("chain not configured, skipping")
			continue
		}

		wg.Add(1)
		go func(name, rpcURL, contractAddr string) {
			defer wg.Done()
			listenChain(ctx, &logger, handler, name, rpcURL, contractAddr, cfg)
		}(name, chain.rpcURL, chain.contract)
	}

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	logger.Info().Msg("shutting down event indexer...")
	cancel()
	wg.Wait()

	if qdrant != nil {
		qdrant.Close()
	}
	if redis != nil {
		redis.Close()
	}

	logger.Info().Msg("event indexer stopped")
}

func listenChain(ctx context.Context, logger *zerolog.Logger, handler *EventHandler, name, rpcURL, contractAddr string, cfg *config.Config) {
	logger.Info().Str("chain", name).Str("rpc", rpcURL).Msg("connecting to chain")

	client, err := ethclient.DialContext(ctx, rpcURL)
	if err != nil {
		logger.Error().Str("chain", name).Err(err).Msg("failed to connect to RPC")
		return
	}
	defer client.Close()

	chainID, err := client.ChainID(ctx)
	if err != nil {
		logger.Error().Str("chain", name).Err(err).Msg("failed to get chain ID")
		return
	}

	contract := common.HexToAddress(contractAddr)

	logger.Info().
		Str("chain", name).
		Uint64("chain_id", chainID.Uint64()).
		Str("contract", contract.Hex()).
		Msg("connected to chain")

	listener := &ChainListener{
		name:         name,
		rpcURL:       rpcURL,
		contractAddr: contract,
		client:       client,
		logger:       logger.With().Str("chain", name).Logger(),
	}

	if cfg.BackfillFromBlock > 0 {
		listener.startBlock = cfg.BackfillFromBlock
		listener.backfillMode = true
		logger.Info().Str("chain", name).Uint64("from_block", cfg.BackfillFromBlock).Msg("backfill mode enabled")
	}

	pollInterval := time.Duration(cfg.PollIntervalSeconds) * time.Second
	if pollInterval == 0 {
		pollInterval = 12 * time.Second
	}

	listener.startEventListener(ctx, handler, pollInterval)
}

func (l *ChainListener) startEventListener(ctx context.Context, handler *EventHandler, pollInterval time.Duration) {
	query := ethereum.FilterQuery{
		Addresses: []common.Address{l.contractAddr},
		Topics: [][]common.Hash{
			{
				crypto.Keccak256Hash([]byte("ConsentRegistered(bytes32,address[],bytes32[],uint256,uint256)")),
				crypto.Keccak256Hash([]byte("ConsentRevoked(bytes32)")),
			},
		},
	}

	var lastBlock uint64
	if l.startBlock > 0 {
		lastBlock = l.startBlock
	} else {
		block, err := l.client.BlockNumber(ctx)
		if err != nil {
			l.logger.Error().Err(err).Msg("failed to get latest block")
			lastBlock = 0
		} else {
			lastBlock = block
		}
	}

	l.logger.Info().Uint64("start_block", lastBlock).Msg("starting event polling")

	for {
		select {
		case <-ctx.Done():
			l.logger.Info().Msg("event listener stopped")
			return
		case <-time.After(pollInterval):
			latestBlock, err := l.client.BlockNumber(ctx)
			if err != nil {
				l.logger.Error().Err(err).Msg("failed to get latest block number")
				continue
			}

			if latestBlock <= lastBlock {
				continue
			}

			fromBlock := lastBlock + 1
			toBlock := latestBlock

			batchSize := uint64(1000)
			if l.backfillMode {
				batchSize = 5000
			}

			for from := fromBlock; from <= toBlock; from += batchSize {
				to := from + batchSize - 1
				if to > toBlock {
					to = toBlock
				}

				query.FromBlock = big.NewInt(int64(from))
				query.ToBlock = big.NewInt(int64(to))

				logs, err := l.client.FilterLogs(ctx, query)
				if err != nil {
					l.logger.Error().
						Uint64("from", from).
						Uint64("to", to).
						Err(err).
						Msg("failed to filter logs")
					continue
				}

				for _, vLog := range logs {
					handler.processEventLog(ctx, l.name, vLog)
				}

				l.logger.Debug().
					Uint64("from", from).
					Uint64("to", to).
					Int("logs", len(logs)).
					Msg("processed block range")
			}

			lastBlock = toBlock

			if l.backfillMode {
				l.logger.Info().
					Uint64("current_block", lastBlock).
					Uint64("target_block", latestBlock).
					Msg("backfill progress")
			}
		}
	}
}

func (h *EventHandler) processEventLog(ctx context.Context, chain string, vLog types.Log) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if len(vLog.Topics) == 0 {
		return
	}

	eventSig := vLog.Topics[0]

	registeredSig := crypto.Keccak256Hash([]byte("ConsentRegistered(bytes32,address[],bytes32[],uint256,uint256)"))
	revokedSig := crypto.Keccak256Hash([]byte("ConsentRevoked(bytes32)"))

	h.logger.Debug().
		Str("chain", chain).
		Str("tx_hash", vLog.TxHash.Hex()).
		Uint64("block", vLog.BlockNumber).
		Str("event", eventSig.Hex()).
		Msg("processing event log")

	switch {
	case eventSig == registeredSig:
		h.handleConsentRegistered(ctx, chain, vLog)
	case eventSig == revokedSig:
		h.handleConsentRevoked(ctx, chain, vLog)
	default:
		h.logger.Debug().
			Str("chain", chain).
			Str("event_sig", eventSig.Hex()).
			Msg("unknown event signature")
	}
}

func (h *EventHandler) handleConsentRegistered(ctx context.Context, chain string, vLog types.Log) {
	if len(vLog.Data) < 128 {
		h.logger.Warn().
			Str("chain", chain).
			Str("tx_hash", vLog.TxHash.Hex()).
			Int("data_len", len(vLog.Data)).
			Msg("invalid ConsentRegistered event data")
		return
	}

	consentID := common.BytesToHash(vLog.Data[0:32])

	var parties []common.Address
	partyOffset := new(big.Int).SetBytes(vLog.Data[32:64]).Uint64()
	if int(partyOffset+32) <= len(vLog.Data) {
		partyCount := new(big.Int).SetBytes(vLog.Data[partyOffset : partyOffset+32]).Uint64()
		for i := uint64(0); i < partyCount; i++ {
			start := partyOffset + 32 + i*32
			if int(start+32) <= len(vLog.Data) {
				parties = append(parties, common.BytesToAddress(vLog.Data[start+12:start+32]))
			}
		}
	}

	var scopes []string
	scopeOffset := new(big.Int).SetBytes(vLog.Data[64:96]).Uint64()
	if int(scopeOffset+32) <= len(vLog.Data) {
		scopeCount := new(big.Int).SetBytes(vLog.Data[scopeOffset : scopeOffset+32]).Uint64()
		for i := uint64(0); i < scopeCount; i++ {
			start := scopeOffset + 32 + i*32
			if int(start+32) <= len(vLog.Data) {
				var b [32]byte
				copy(b[:], vLog.Data[start:start+32])
				scopes = append(scopes, strings.TrimRight(string(b[:]), "\x00"))
			}
		}
	}

	validFrom := new(big.Int).SetBytes(vLog.Data[96:128]).Uint64()
	var validUntil uint64
	if len(vLog.Data) >= 160 {
		validUntil = new(big.Int).SetBytes(vLog.Data[128:160]).Uint64()
	}

	h.logger.Info().
		Str("chain", chain).
		Str("consent_id", consentID.Hex()).
		Str("tx_hash", vLog.TxHash.Hex()).
		Uint64("block", vLog.BlockNumber).
		Int("parties", len(parties)).
		Int("scopes", len(scopes)).
		Msg("ConsentRegistered event processed")

	partyStrs := make([]string, len(parties))
	for i, p := range parties {
		partyStrs[i] = strings.ToLower(p.Hex())
	}

	if h.redis != nil {
		cacheData := &redisclient.ConsentCache{
			ConsentID:  consentID.Hex(),
			Parties:    partyStrs,
			Scopes:     scopes,
			ValidFrom:  validFrom,
			ValidUntil: validUntil,
			Revoked:    false,
			Chain:      chain,
			TxHash:     vLog.TxHash.Hex(),
			CreatedAt:  validFrom,
		}

		if err := h.redis.CacheConsent(ctx, cacheData, 24*time.Hour); err != nil {
			h.logger.Warn().Err(err).Str("consent_id", consentID.Hex()).Msg("failed to cache consent event")
		}
	}
}

func (h *EventHandler) handleConsentRevoked(ctx context.Context, chain string, vLog types.Log) {
	if len(vLog.Data) < 32 {
		h.logger.Warn().
			Str("chain", chain).
			Str("tx_hash", vLog.TxHash.Hex()).
			Msg("invalid ConsentRevoked event data")
		return
	}

	consentID := common.BytesToHash(vLog.Data[0:32])

	h.logger.Info().
		Str("chain", chain).
		Str("consent_id", consentID.Hex()).
		Str("tx_hash", vLog.TxHash.Hex()).
		Uint64("block", vLog.BlockNumber).
		Msg("ConsentRevoked event processed")

	if h.qdrant != nil {
		if err := h.qdrant.UpdateConsentRevoked(ctx, consentID.Hex(), true); err != nil {
			h.logger.Warn().Err(err).Str("consent_id", consentID.Hex()).Msg("failed to update Qdrant index on revoke")
		}
	}

	if h.redis != nil {
		if err := h.redis.InvalidateConsent(ctx, chain, consentID.Hex()); err != nil {
			h.logger.Warn().Err(err).Str("consent_id", consentID.Hex()).Msg("failed to invalidate cache on revoke")
		}
	}
}
