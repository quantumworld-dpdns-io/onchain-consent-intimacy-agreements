package api

type CreateConsentRequest struct {
	Parties  []string `json:"parties" binding:"required,min=2"`
	Scopes   []string `json:"scopes" binding:"required,min=1"`
	Duration uint64   `json:"duration" binding:"required"`
	Chain    string   `json:"chain" binding:"required"`
}

type CreateConsentResponse struct {
	ConsentID string `json:"consent_id"`
	Chain     string `json:"chain"`
	TxHash    string `json:"tx_hash"`
	Status    string `json:"status"`
}

type VerifyConsentRequest struct {
	ConsentID string `json:"consent_id" binding:"required"`
	Chain     string `json:"chain" binding:"required"`
	Proof     string `json:"proof,omitempty"`
	ProofType string `json:"proof_type,omitempty"`
}

type VerifyConsentResponse struct {
	Valid      bool   `json:"valid"`
	ExpiresAt  uint64 `json:"expires_at"`
	VerifiedBy string `json:"verified_by"`
}

type RevokeConsentRequest struct {
	ConsentID string `json:"consent_id" binding:"required"`
	Chain     string `json:"chain" binding:"required"`
}

type GenerateProofRequest struct {
	ConsentID string `json:"consent_id" binding:"required"`
	ProofType string `json:"proof_type" binding:"required"`
	Chain     string `json:"chain" binding:"required"`
}

type ConsentResponse struct {
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

type ChainInfo struct {
	Name       string `json:"name"`
	ChainID    uint64 `json:"chain_id"`
	RPCReady   bool   `json:"rpc_ready"`
	LatestBlock uint64 `json:"latest_block"`
	GasPrice   string `json:"gas_price"`
}

type GenerateProofResponse struct {
	Proof        string   `json:"proof"`
	ProofType    string   `json:"proof_type"`
	PublicInputs []string `json:"public_inputs"`
}

type ErrorResponse struct {
	Error   string `json:"error"`
	Code    int    `json:"code"`
	Details string `json:"details,omitempty"`
}

type SearchConsentsResponse struct {
	Results  []ConsentResponse `json:"results"`
	Total    int               `json:"total"`
	Page     int               `json:"page"`
	PageSize int               `json:"page_size"`
}

type GetChainsResponse struct {
	Chains []ChainInfo `json:"chains"`
}
