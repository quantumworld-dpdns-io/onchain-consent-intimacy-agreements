package api

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/gin-gonic/gin"

	qdrantclient "github.com/onchain-consent/backend/go-api/internal/qdrant"
)

func (h *Handler) CreateConsent(c *gin.Context) {
	var req CreateConsentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		h.handleError(c, http.StatusBadRequest, "invalid request body", err)
		return
	}

	if len(req.Parties) < 2 {
		h.handleError(c, http.StatusBadRequest, "minimum 2 parties required", fmt.Errorf("got %d parties", len(req.Parties)))
		return
	}
	if len(req.Scopes) < 1 {
		h.handleError(c, http.StatusBadRequest, "minimum 1 scope required", fmt.Errorf("got %d scopes", len(req.Scopes)))
		return
	}
	if req.Duration == 0 {
		h.handleError(c, http.StatusBadRequest, "duration must be greater than 0", fmt.Errorf("duration: %d", req.Duration))
		return
	}
	if err := h.validateChain(req.Chain); err != nil {
		h.handleError(c, http.StatusBadRequest, "invalid chain", err)
		return
	}

	for i, party := range req.Parties {
		if !common.IsHexAddress(party) {
			h.handleError(c, http.StatusBadRequest, fmt.Sprintf("invalid party address at index %d", i), fmt.Errorf("invalid address: %s", party))
			return
		}
	}

	consentID := h.generateConsentID(req.Parties, req.Scopes)

	contractCli, _, err := h.getContractClient(req.Chain)
	if err != nil {
		h.handleError(c, http.StatusInternalServerError, "failed to get contract client", err)
		return
	}

	parties := bytesToAddresses(req.Parties)
	scopeBytes := scopesToBytes32(req.Scopes)
	duration := bigIntPtr(req.Duration)

	_, txHashStr, err := contractCli.RegisterConsent(c.Request.Context(), parties, scopeBytes, duration)
	if err != nil {
		if !strings.Contains(err.Error(), "requires external signing") {
			h.handleError(c, http.StatusInternalServerError, "failed to register consent on chain", err)
			return
		}
	}

	now := uint64(time.Now().Unix())
	validUntil := now + req.Duration

	qdrantDoc := &qdrantclient.ConsentDocument{
		ConsentID:  consentID,
		Parties:    req.Parties,
		Scopes:     req.Scopes,
		ValidFrom:  now,
		ValidUntil: validUntil,
		Revoked:    false,
		Chain:      req.Chain,
		TxHash:     txHashStr,
		CreatedAt:  now,
		Embedding:  h.generateEmbedding(consentID, req.Parties, req.Scopes),
	}

	if err := h.qdrant.IndexConsent(context.Background(), qdrantDoc); err != nil {
		h.logger.Warn().Err(err).Str("consent_id", consentID).Msg("failed to index consent in Qdrant")
	}

	cache := h.createConsentCache(consentID, req.Chain, txHashStr, req.Parties, req.Scopes, now, validUntil, now, false)
	if err := h.redis.CacheConsent(context.Background(), cache, 24*time.Hour); err != nil {
		h.logger.Warn().Err(err).Str("consent_id", consentID).Msg("failed to cache consent in Redis")
	}

	h.logger.Info().
		Str("consent_id", consentID).
		Str("tx_hash", txHashStr).
		Str("chain", req.Chain).
		Int("parties", len(req.Parties)).
		Int("scopes", len(req.Scopes)).
		Msg("consent created")

	c.JSON(http.StatusCreated, CreateConsentResponse{
		ConsentID: consentID,
		Chain:     req.Chain,
		TxHash:    txHashStr,
		Status:    "pending",
	})
}

func (h *Handler) GetConsent(c *gin.Context) {
	consentID := c.Param("id")
	if consentID == "" {
		h.handleError(c, http.StatusBadRequest, "consent id is required", fmt.Errorf("missing consent id"))
		return
	}

	chain := c.Query("chain")
	if chain == "" {
		chain = "sepolia"
	}

	if err := h.validateChain(chain); err != nil {
		h.handleError(c, http.StatusBadRequest, "invalid chain", err)
		return
	}

	cached, err := h.redis.GetCachedConsent(c.Request.Context(), chain, consentID)
	if err != nil {
		h.logger.Warn().Err(err).Str("consent_id", consentID).Msg("redis lookup failed")
	}
	if cached != nil {
		c.JSON(http.StatusOK, h.toConsentResponse(cached))
		return
	}

	contractCli, _, err := h.getContractClient(chain)
	if err != nil {
		h.handleError(c, http.StatusInternalServerError, "failed to get contract client", err)
		return
	}

	consentHash := common.HexToHash(consentID)
	consentData, err := contractCli.GetConsent(c.Request.Context(), consentHash)
	if err != nil {
		h.handleError(c, http.StatusInternalServerError, "failed to fetch consent from chain", err)
		return
	}

	if consentData == nil || !consentData.Exists {
		c.JSON(http.StatusNotFound, ErrorResponse{
			Error: "consent not found",
			Code:  http.StatusNotFound,
		})
		return
	}

	parties := addressesToStrings(consentData.Parties)
	scopes := make([]string, len(consentData.Scopes))
	for i, s := range consentData.Scopes {
		scopes[i] = strings.TrimRight(string(s[:]), "\x00")
	}

	response := &ConsentResponse{
		ConsentID:  consentID,
		Parties:    parties,
		Scopes:     scopes,
		ValidFrom:  consentData.ValidFrom.Uint64(),
		ValidUntil: consentData.ValidUntil.Uint64(),
		Revoked:    consentData.Revoked,
		Chain:      chain,
		CreatedAt:  consentData.ValidFrom.Uint64(),
	}

	cacheEntry := h.createConsentCache(
		consentID, chain, "",
		parties, scopes,
		consentData.ValidFrom.Uint64(), consentData.ValidUntil.Uint64(),
		consentData.ValidFrom.Uint64(), consentData.Revoked,
	)
	if err := h.redis.CacheConsent(c.Request.Context(), cacheEntry, 5*time.Minute); err != nil {
		h.logger.Warn().Err(err).Str("consent_id", consentID).Msg("failed to cache consent")
	}

	c.JSON(http.StatusOK, response)
}

func (h *Handler) VerifyConsent(c *gin.Context) {
	consentID := c.Param("id")
	if consentID == "" {
		h.handleError(c, http.StatusBadRequest, "consent id is required", fmt.Errorf("missing consent id"))
		return
	}

	var req VerifyConsentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		h.handleError(c, http.StatusBadRequest, "invalid request body", err)
		return
	}
	req.ConsentID = consentID

	if err := h.validateChain(req.Chain); err != nil {
		h.handleError(c, http.StatusBadRequest, "invalid chain", err)
		return
	}

	if req.Proof != "" {
		valid, err := h.verifyZKProof(req)
		if err != nil {
			h.handleError(c, http.StatusInternalServerError, "failed to verify ZK proof", err)
			return
		}

		contractCli, _, err := h.getContractClient(req.Chain)
		if err != nil {
			h.handleError(c, http.StatusInternalServerError, "failed to get contract client", err)
			return
		}

		consentHash := common.HexToHash(req.ConsentID)
		_, expiresAt, _ := contractCli.VerifyConsentOnChain(c.Request.Context(), consentHash)

		var expiresAtUint uint64
		if expiresAt != nil {
			expiresAtUint = expiresAt.Uint64()
		}

		verifiedBy := "zk-proof"
		if valid {
			verifiedBy = "zk-proof"
		}

		c.JSON(http.StatusOK, VerifyConsentResponse{
			Valid:      valid,
			ExpiresAt:  expiresAtUint,
			VerifiedBy: verifiedBy,
		})
		return
	}

	contractCli, _, err := h.getContractClient(req.Chain)
	if err != nil {
		h.handleError(c, http.StatusInternalServerError, "failed to get contract client", err)
		return
	}

	consentHash := common.HexToHash(req.ConsentID)
	valid, expiresAt, err := contractCli.VerifyConsentOnChain(c.Request.Context(), consentHash)
	if err != nil {
		h.handleError(c, http.StatusInternalServerError, "failed to verify consent on chain", err)
		return
	}

	var expiresAtUint uint64
	if expiresAt != nil {
		expiresAtUint = expiresAt.Uint64()
	}

	if time.Now().Unix() > int64(expiresAtUint) {
		valid = false
	}

	verifiedBy := "on-chain"
	if valid {
		cached, _ := h.redis.GetCachedConsent(c.Request.Context(), req.Chain, req.ConsentID)
		if cached != nil && cached.Revoked {
			valid = false
		}
	}

	c.JSON(http.StatusOK, VerifyConsentResponse{
		Valid:      valid,
		ExpiresAt:  expiresAtUint,
		VerifiedBy: verifiedBy,
	})
}

func (h *Handler) RevokeConsent(c *gin.Context) {
	consentID := c.Param("id")
	if consentID == "" {
		h.handleError(c, http.StatusBadRequest, "consent id is required", fmt.Errorf("missing consent id"))
		return
	}

	var req RevokeConsentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		h.handleError(c, http.StatusBadRequest, "invalid request body", err)
		return
	}
	req.ConsentID = consentID

	if err := h.validateChain(req.Chain); err != nil {
		h.handleError(c, http.StatusBadRequest, "invalid chain", err)
		return
	}

	contractCli, _, err := h.getContractClient(req.Chain)
	if err != nil {
		h.handleError(c, http.StatusInternalServerError, "failed to get contract client", err)
		return
	}

	consentHash := common.HexToHash(req.ConsentID)
	_, txHashStr, err := contractCli.RevokeConsent(c.Request.Context(), consentHash)
	if err != nil {
		if !strings.Contains(err.Error(), "requires external signing") {
			h.handleError(c, http.StatusInternalServerError, "failed to revoke consent on chain", err)
			return
		}
	}

	if err := h.qdrant.UpdateConsentRevoked(context.Background(), req.ConsentID, true); err != nil {
		h.logger.Warn().Err(err).Str("consent_id", req.ConsentID).Msg("failed to update Qdrant index")
	}

	if err := h.redis.InvalidateConsent(context.Background(), req.Chain, req.ConsentID); err != nil {
		h.logger.Warn().Err(err).Str("consent_id", req.ConsentID).Msg("failed to invalidate cache")
	}

	h.logger.Info().
		Str("consent_id", req.ConsentID).
		Str("tx_hash", txHashStr).
		Str("chain", req.Chain).
		Msg("consent revoked")

	c.JSON(http.StatusOK, gin.H{
		"tx_hash": txHashStr,
		"revoked": true,
	})
}

func (h *Handler) GenerateProof(c *gin.Context) {
	consentID := c.Param("id")
	if consentID == "" {
		h.handleError(c, http.StatusBadRequest, "consent id is required", fmt.Errorf("missing consent id"))
		return
	}

	var req GenerateProofRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		h.handleError(c, http.StatusBadRequest, "invalid request body", err)
		return
	}
	req.ConsentID = consentID

	if err := h.validateChain(req.Chain); err != nil {
		h.handleError(c, http.StatusBadRequest, "invalid chain", err)
		return
	}

	contractCli, _, err := h.getContractClient(req.Chain)
	if err != nil {
		h.handleError(c, http.StatusInternalServerError, "failed to get contract client", err)
		return
	}

	consentHash := common.HexToHash(req.ConsentID)
	consentData, err := contractCli.GetConsent(c.Request.Context(), consentHash)
	if err != nil {
		h.handleError(c, http.StatusInternalServerError, "failed to get consent data", err)
		return
	}

	if consentData == nil || !consentData.Exists {
		c.JSON(http.StatusNotFound, ErrorResponse{
			Error: "consent not found",
			Code:  http.StatusNotFound,
		})
		return
	}

	proofResult, err := h.callZKProofService(req.ConsentID, req.ProofType, req.Chain)
	if err != nil {
		h.handleError(c, http.StatusInternalServerError, "failed to generate proof", err)
		return
	}

	c.JSON(http.StatusOK, GenerateProofResponse{
		Proof:        proofResult.Proof,
		ProofType:    req.ProofType,
		PublicInputs: proofResult.PublicInputs,
	})
}

func (h *Handler) GetPartyConsents(c *gin.Context) {
	addr := c.Param("addr")
	if addr == "" || !common.IsHexAddress(addr) {
		h.handleError(c, http.StatusBadRequest, "valid address is required", fmt.Errorf("invalid address: %s", addr))
		return
	}

	consents, err := h.qdrant.GetConsentsByParty(context.Background(), strings.ToLower(addr))
	if err != nil {
		h.logger.Warn().Err(err).Str("addr", addr).Msg("Qdrant query failed, falling back")
	}

	results := make([]ConsentResponse, 0)
	for _, doc := range consents {
		results = append(results, ConsentResponse{
			ConsentID:  doc.ConsentID,
			Parties:    doc.Parties,
			Scopes:     doc.Scopes,
			ValidFrom:  doc.ValidFrom,
			ValidUntil: doc.ValidUntil,
			Revoked:    doc.Revoked,
			Chain:      doc.Chain,
			TxHash:     doc.TxHash,
			CreatedAt:  doc.CreatedAt,
		})
	}

	if results == nil {
		results = make([]ConsentResponse, 0)
	}

	c.JSON(http.StatusOK, SearchConsentsResponse{
		Results:  results,
		Total:    len(results),
		Page:     1,
		PageSize: len(results),
	})
}

func (h *Handler) SearchConsents(c *gin.Context) {
	query := c.Query("q")
	chain := c.Query("chain")
	party := c.Query("party")
	scope := c.Query("scope")
	pageStr := c.Query("page")
	limitStr := c.Query("limit")

	page := 1
	limit := 20

	if p, err := strconv.Atoi(pageStr); err == nil && p > 0 {
		page = p
	}
	if l, err := strconv.Atoi(limitStr); err == nil && l > 0 && l <= 100 {
		limit = l
	}

	searchParams := &qdrantclient.SearchParams{
		Query:  query,
		Chain:  chain,
		Party:  party,
		Scope:  scope,
		Limit:  limit,
		Offset: (page - 1) * limit,
	}

	results, err := h.qdrant.Search(context.Background(), searchParams)
	if err != nil {
		h.logger.Error().Err(err).Msg("Qdrant search failed")
		c.JSON(http.StatusOK, SearchConsentsResponse{
			Results:  make([]ConsentResponse, 0),
			Total:    0,
			Page:     page,
			PageSize: limit,
		})
		return
	}

	consentResponses := make([]ConsentResponse, 0, len(results))
	for _, doc := range results {
		consentResponses = append(consentResponses, ConsentResponse{
			ConsentID:  doc.ConsentID,
			Parties:    doc.Parties,
			Scopes:     doc.Scopes,
			ValidFrom:  doc.ValidFrom,
			ValidUntil: doc.ValidUntil,
			Revoked:    doc.Revoked,
			Chain:      doc.Chain,
			TxHash:     doc.TxHash,
			CreatedAt:  doc.CreatedAt,
		})
	}

	c.JSON(http.StatusOK, SearchConsentsResponse{
		Results:  consentResponses,
		Total:    len(consentResponses),
		Page:     page,
		PageSize: limit,
	})
}

func (h *Handler) GetChains(c *gin.Context) {
	chainNames := []string{"sepolia", "bsc-testnet", "amoy", "palm-testnet", "base-sepolia"}
	chains := make([]ChainInfo, 0, len(chainNames))

	for _, name := range chainNames {
		status, err := h.chainMgr.GetChainStatus(c.Request.Context(), name)
		if err != nil {
			chains = append(chains, ChainInfo{
				Name:     name,
				RPCReady: false,
			})
			continue
		}
		chains = append(chains, *status)
	}

	c.JSON(http.StatusOK, GetChainsResponse{Chains: chains})
}

func (h *Handler) GetChainStatus(c *gin.Context) {
	chain := c.Param("chain")
	if chain == "" {
		h.handleError(c, http.StatusBadRequest, "chain parameter is required", fmt.Errorf("missing chain"))
		return
	}

	if err := h.validateChain(chain); err != nil {
		h.handleError(c, http.StatusBadRequest, "unsupported chain", err)
		return
	}

	status, err := h.chainMgr.GetChainStatus(c.Request.Context(), chain)
	if err != nil {
		h.handleError(c, http.StatusInternalServerError, "failed to get chain status", err)
		return
	}

	c.JSON(http.StatusOK, status)
}

type ZKProofResult struct {
	Proof        string   `json:"proof"`
	ProofType    string   `json:"proof_type"`
	PublicInputs []string `json:"public_inputs"`
}

func (h *Handler) callZKProofService(consentID, proofType, chain string) (*ZKProofResult, error) {
	payload := map[string]string{
		"consent_id": consentID,
		"proof_type": proofType,
		"chain":      chain,
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal proof request: %w", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, "POST", h.cfg.RustZKURL+"/api/v1/prove", bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("failed to create proof request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to call ZK proof service: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read proof response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("ZK proof service returned status %d: %s", resp.StatusCode, string(respBody))
	}

	var result ZKProofResult
	if err := json.Unmarshal(respBody, &result); err != nil {
		return nil, fmt.Errorf("failed to parse proof response: %w", err)
	}

	return &result, nil
}

func (h *Handler) verifyZKProof(req VerifyConsentRequest) (bool, error) {
	payload := map[string]string{
		"consent_id": req.ConsentID,
		"proof":      req.Proof,
		"proof_type": req.ProofType,
		"chain":      req.Chain,
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return false, fmt.Errorf("failed to marshal verify request: %w", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	httpReq, err := http.NewRequestWithContext(ctx, "POST", h.cfg.RustZKURL+"/api/v1/verify", bytes.NewReader(body))
	if err != nil {
		return false, fmt.Errorf("failed to create verify request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(httpReq)
	if err != nil {
		return false, fmt.Errorf("failed to call ZK verify service: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return false, fmt.Errorf("failed to read verify response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return false, fmt.Errorf("ZK verify service returned status %d: %s", resp.StatusCode, string(respBody))
	}

	var result struct {
		Valid bool `json:"valid"`
	}
	if err := json.Unmarshal(respBody, &result); err != nil {
		return false, fmt.Errorf("failed to parse verify response: %w", err)
	}

	return result.Valid, nil
}

