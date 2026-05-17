package api

import (
	"crypto/ecdsa"
	"fmt"
	"math/big"
	"strings"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/rs/zerolog"

	"github.com/onchain-consent/backend/go-api/internal/config"
	"github.com/onchain-consent/backend/go-api/internal/contracts"
	qdrantclient "github.com/onchain-consent/backend/go-api/internal/qdrant"
	redisclient "github.com/onchain-consent/backend/go-api/internal/redis"
)

type Handler struct {
	cfg        *config.Config
	qdrant     *qdrantclient.Client
	redis      *redisclient.Client
	logger     *zerolog.Logger
	chainMgr   *ChainManager
	privateKey *ecdsa.PrivateKey
}

func NewHandler(cfg *config.Config, qdrant *qdrantclient.Client, redis *redisclient.Client, logger *zerolog.Logger) (*Handler, error) {
	chainMgr := NewChainManager(cfg, logger)

	var privKey *ecdsa.PrivateKey
	if keyHex := cfg.JWTSecret; len(keyHex) >= 64 {
		if key, err := crypto.HexToECDSA(keyHex[:64]); err == nil {
			privKey = key
		}
	}

	return &Handler{
		cfg:        cfg,
		qdrant:     qdrant,
		redis:      redis,
		logger:     logger,
		chainMgr:   chainMgr,
		privateKey: privKey,
	}, nil
}

func (h *Handler) getContractClient(chain string) (*contracts.Client, *ethclient.Client, error) {
	client, err := h.chainMgr.GetClient(chain)
	if err != nil {
		return nil, nil, err
	}

	registryAddr, err := h.chainMgr.GetRegistryAddress(chain)
	if err != nil {
		return nil, nil, err
	}

	contractCli := contracts.NewClient(h.cfg, client, chain, registryAddr, h.logger)
	return contractCli, client, nil
}

func (h *Handler) validateChain(chain string) error {
	if !h.chainMgr.IsChainSupported(chain) {
		return fmt.Errorf("unsupported chain: %s", chain)
	}
	return nil
}

func (h *Handler) generateConsentID(parties []string, scopes []string) string {
	input := strings.Join(parties, ",") + "|" + strings.Join(scopes, ",") + "|" + fmt.Sprintf("%d", time.Now().UnixNano())
	hash := crypto.Keccak256Hash([]byte(input))
	return hash.Hex()
}

func (h *Handler) generateEmbedding(consentID string, parties []string, scopes []string) []float32 {
	embedding := make([]float32, 384)
	input := consentID + strings.Join(parties, " ") + strings.Join(scopes, " ")

	for i := 0; i < 384 && i < len(input); i++ {
		embedding[i] = float32(int(input[i])) / 256.0
	}

	return embedding
}

func (h *Handler) createConsentCache(consentID, chain, txHash string, parties []string, scopes []string, validFrom, validUntil, createdAt uint64, revoked bool) *redisclient.ConsentCache {
	return &redisclient.ConsentCache{
		ConsentID:  consentID,
		Parties:    parties,
		Scopes:     scopes,
		ValidFrom:  validFrom,
		ValidUntil: validUntil,
		Revoked:    revoked,
		Chain:      chain,
		TxHash:     txHash,
		CreatedAt:  createdAt,
	}
}

func (h *Handler) toConsentResponse(cache *redisclient.ConsentCache) *ConsentResponse {
	return &ConsentResponse{
		ConsentID:  cache.ConsentID,
		Parties:    cache.Parties,
		Scopes:     cache.Scopes,
		ValidFrom:  cache.ValidFrom,
		ValidUntil: cache.ValidUntil,
		Revoked:    cache.Revoked,
		Chain:      cache.Chain,
		TxHash:     cache.TxHash,
		CreatedAt:  cache.CreatedAt,
	}
}

func (h *Handler) handleError(c *gin.Context, status int, msg string, err error) {
	h.logger.Error().Err(err).Str("path", c.Request.URL.Path).Msg(msg)
	c.JSON(status, ErrorResponse{
		Error:   msg,
		Code:    status,
		Details: err.Error(),
	})
}

func bytesToAddresses(addrs []string) []common.Address {
	result := make([]common.Address, len(addrs))
	for i, addr := range addrs {
		result[i] = common.HexToAddress(addr)
	}
	return result
}

func addressesToStrings(addrs []common.Address) []string {
	result := make([]string, len(addrs))
	for i, addr := range addrs {
		result[i] = strings.ToLower(addr.Hex())
	}
	return result
}

func scopesToBytes32(scopes []string) [][32]byte {
	result := make([][32]byte, len(scopes))
	for i, scope := range scopes {
		result[i] = contracts.StringToBytes32(scope)
	}
	return result
}

func (h *Handler) CloseChainClients() {
	h.chainMgr.CloseAll()
}

func removeZeroBytes(s string) string {
	return strings.TrimRight(s, "\x00")
}

func bigIntPtr(v uint64) *big.Int {
	return new(big.Int).SetUint64(v)
}
