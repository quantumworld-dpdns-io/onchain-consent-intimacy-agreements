package contracts

import (
	"context"
	"crypto/ecdsa"
	"fmt"
	"math/big"
	"strings"
	"time"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/rs/zerolog"

	"github.com/onchain-consent/backend/go-api/internal/config"
)

const (
	DefaultGasLimit = 300000
	TxTimeout       = 2 * time.Minute
)

type ConsentContract interface {
	RegisterConsent(ctx context.Context, parties []common.Address, scopes [][32]byte, duration *big.Int, privateKey *ecdsa.PrivateKey) (common.Hash, error)
	GetConsent(ctx context.Context, consentID [32]byte) (*ConsentData, error)
	RevokeConsent(ctx context.Context, consentID [32]byte, privateKey *ecdsa.PrivateKey) (common.Hash, error)
	ConsentExists(ctx context.Context, consentID [32]byte) (bool, error)
}

type ConsentData struct {
	Parties    []common.Address
	Scopes     [][32]byte
	ValidFrom  *big.Int
	ValidUntil *big.Int
	Revoked    bool
	Exists     bool
}

type Client struct {
	config  *config.Config
	client  *ethclient.Client
	chain   string
	address common.Address
	logger  *zerolog.Logger
}

func NewClient(cfg *config.Config, client *ethclient.Client, chain string, contractAddr common.Address, logger *zerolog.Logger) *Client {
	return &Client{
		config:  cfg,
		client:  client,
		chain:   chain,
		address: contractAddr,
		logger:  logger,
	}
}

func (c *Client) RegisterConsent(ctx context.Context, parties []common.Address, scopes [][32]byte, duration *big.Int) (common.Hash, string, error) {
	data, err := encodeRegisterConsent(parties, scopes, duration)
	if err != nil {
		return common.Hash{}, "", fmt.Errorf("failed to encode register consent: %w", err)
	}

	gasPrice, err := c.client.SuggestGasPrice(ctx)
	if err != nil {
		return common.Hash{}, "", fmt.Errorf("failed to suggest gas price: %w", err)
	}

	callMsg := ethereum.CallMsg{
		To:       &c.address,
		Data:     data,
		GasPrice: gasPrice,
	}

	gasLimit, err := c.client.EstimateGas(ctx, callMsg)
	if err != nil {
		gasLimit = DefaultGasLimit
	}

	nonce, err := c.client.NonceAt(ctx, common.Address{}, nil)
	if err != nil {
		return common.Hash{}, "", fmt.Errorf("failed to get nonce: %w", err)
	}

	chainID, err := c.client.ChainID(ctx)
	if err != nil {
		return common.Hash{}, "", fmt.Errorf("failed to get chain ID: %w", err)
	}

	tx := types.NewTransaction(nonce, c.address, big.NewInt(0), gasLimit, gasPrice, data)
	signer := types.NewLondonSigner(chainID)

	txHash := signer.Hash(tx)

	c.logger.Info().
		Str("chain", c.chain).
		Str("contract", c.address.Hex()).
		Str("tx_hash", txHash.Hex()).
		Uint64("gas_limit", gasLimit).
		Str("gas_price", gasPrice.String()).
		Int("parties", len(parties)).
		Int("scopes", len(scopes)).
		Msg("consent registration transaction prepared")

	return txHash, txHash.Hex(), fmt.Errorf("transaction requires external signing, hash: %s", txHash.Hex())
}

func (c *Client) GetConsent(ctx context.Context, consentID [32]byte) (*ConsentData, error) {
	data, err := encodeGetConsent(consentID)
	if err != nil {
		return nil, fmt.Errorf("failed to encode get consent: %w", err)
	}

	callMsg := ethereum.CallMsg{
		To:   &c.address,
		Data: data,
	}

	result, err := c.client.CallContract(ctx, callMsg, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to call contract: %w", err)
	}

	return decodeConsentData(result)
}

func (c *Client) RevokeConsent(ctx context.Context, consentID [32]byte) (common.Hash, string, error) {
	data, err := encodeRevokeConsent(consentID)
	if err != nil {
		return common.Hash{}, "", fmt.Errorf("failed to encode revoke consent: %w", err)
	}

	gasPrice, err := c.client.SuggestGasPrice(ctx)
	if err != nil {
		return common.Hash{}, "", fmt.Errorf("failed to suggest gas price: %w", err)
	}

	callMsg := ethereum.CallMsg{
		To:       &c.address,
		Data:     data,
		GasPrice: gasPrice,
	}

	gasLimit, err := c.client.EstimateGas(ctx, callMsg)
	if err != nil {
		gasLimit = DefaultGasLimit
	}

	nonce, err := c.client.NonceAt(ctx, common.Address{}, nil)
	if err != nil {
		return common.Hash{}, "", fmt.Errorf("failed to get nonce: %w", err)
	}

	chainID, err := c.client.ChainID(ctx)
	if err != nil {
		return common.Hash{}, "", fmt.Errorf("failed to get chain ID: %w", err)
	}

	tx := types.NewTransaction(nonce, c.address, big.NewInt(0), gasLimit, gasPrice, data)
	signer := types.NewLondonSigner(chainID)
	txHash := signer.Hash(tx)

	c.logger.Info().
		Str("chain", c.chain).
		Str("consent_id", fmt.Sprintf("%x", consentID)).
		Str("tx_hash", txHash.Hex()).
		Msg("consent revocation transaction prepared")

	return txHash, txHash.Hex(), fmt.Errorf("transaction requires external signing, hash: %s", txHash.Hex())
}

func (c *Client) ConsentExists(ctx context.Context, consentID [32]byte) (bool, error) {
	data, err := encodeConsentExists(consentID)
	if err != nil {
		return false, fmt.Errorf("failed to encode consent exists: %w", err)
	}

	callMsg := ethereum.CallMsg{
		To:   &c.address,
		Data: data,
	}

	result, err := c.client.CallContract(ctx, callMsg, nil)
	if err != nil {
		return false, fmt.Errorf("failed to call contract: %w", err)
	}

	return decodeBool(result)
}

func (c *Client) VerifyConsentOnChain(ctx context.Context, consentID [32]byte) (bool, *big.Int, error) {
	data, err := encodeVerifyConsent(consentID)
	if err != nil {
		return false, nil, fmt.Errorf("failed to encode verify consent: %w", err)
	}

	callMsg := ethereum.CallMsg{
		To:   &c.address,
		Data: data,
	}

	result, err := c.client.CallContract(ctx, callMsg, nil)
	if err != nil {
		return false, nil, fmt.Errorf("failed to call contract: %w", err)
	}

	return decodeVerificationResult(result)
}

func encodeRegisterConsent(parties []common.Address, scopes [][32]byte, duration *big.Int) ([]byte, error) {
	partiesLen := len(parties)
	scopesLen := len(scopes)

	data := make([]byte, 0, 4+32+32+32+partiesLen*32+scopesLen*32+32)

	sig := crypto.Keccak256([]byte("registerConsent(address[],bytes32[],uint256)"))[:4]
	data = append(data, sig...)

	dynOffset := uint64(32 + 32 + 32)
	offset := uint64(len(data))

	partiesOffset := make([]byte, 32)
	big.NewInt(int64(dynOffset)).FillBytes(partiesOffset)
	data = append(data, partiesOffset...)

	scopesDynamicOffset := dynOffset + 32 + uint64(partiesLen*32) + 32
	scopesOffset := make([]byte, 32)
	big.NewInt(int64(scopesDynamicOffset)).FillBytes(scopesOffset)
	data = append(data, scopesOffset...)

	durationBytes := make([]byte, 32)
	duration.FillBytes(durationBytes)
	data = append(data, durationBytes...)

	partiesLenBytes := make([]byte, 32)
	big.NewInt(int64(partiesLen)).FillBytes(partiesLenBytes)
	data = append(data, partiesLenBytes...)
	for _, p := range parties {
		addrBytes := make([]byte, 32)
		copy(addrBytes[12:], p.Bytes())
		data = append(data, addrBytes...)
	}

	scopesLenBytes := make([]byte, 32)
	big.NewInt(int64(scopesLen)).FillBytes(scopesLenBytes)
	data = append(data, scopesLenBytes...)
	for _, s := range scopes {
		data = append(data, s[:]...)
	}

	return data, nil
}

func encodeGetConsent(consentID [32]byte) ([]byte, error) {
	sig := crypto.Keccak256([]byte("getConsent(bytes32)"))[:4]
	data := make([]byte, 0, 4+32)
	data = append(data, sig...)
	data = append(data, consentID[:]...)
	return data, nil
}

func encodeRevokeConsent(consentID [32]byte) ([]byte, error) {
	sig := crypto.Keccak256([]byte("revokeConsent(bytes32)"))[:4]
	data := make([]byte, 0, 4+32)
	data = append(data, sig...)
	data = append(data, consentID[:]...)
	return data, nil
}

func encodeConsentExists(consentID [32]byte) ([]byte, error) {
	sig := crypto.Keccak256([]byte("consentExists(bytes32)"))[:4]
	data := make([]byte, 0, 4+32)
	data = append(data, sig...)
	data = append(data, consentID[:]...)
	return data, nil
}

func encodeVerifyConsent(consentID [32]byte) ([]byte, error) {
	sig := crypto.Keccak256([]byte("verifyConsent(bytes32)"))[:4]
	data := make([]byte, 0, 4+32)
	data = append(data, sig...)
	data = append(data, consentID[:]...)
	return data, nil
}

func decodeConsentData(data []byte) (*ConsentData, error) {
	if len(data) < 96 {
		return &ConsentData{Exists: false}, nil
	}

	result := &ConsentData{Exists: true}

	partiesOffset := new(big.Int).SetBytes(data[0:32]).Uint64()
	scopesOffset := new(big.Int).SetBytes(data[32:64]).Uint64()

	result.ValidFrom = new(big.Int).SetBytes(data[64:96])
	if len(data) >= 128 {
		result.ValidUntil = new(big.Int).SetBytes(data[96:128])
	}
	if len(data) >= 160 {
		result.Revoked = data[128] != 0
	}

	partiesData := data[partiesOffset:]
	if len(partiesData) >= 32 {
		partiesLen := new(big.Int).SetBytes(partiesData[0:32]).Uint64()
		result.Parties = make([]common.Address, partiesLen)
		for i := uint64(0); i < partiesLen; i++ {
			start := 32 + i*32
			if int(start+32) <= len(partiesData) {
				result.Parties[i] = common.BytesToAddress(partiesData[start+12 : start+32])
			}
		}
	}

	scopesData := data[scopesOffset:]
	if len(scopesData) >= 32 {
		scopesLen := new(big.Int).SetBytes(scopesData[0:32]).Uint64()
		result.Scopes = make([][32]byte, scopesLen)
		for i := uint64(0); i < scopesLen; i++ {
			start := 32 + i*32
			if int(start+32) <= len(scopesData) {
				copy(result.Scopes[i][:], scopesData[start:start+32])
			}
		}
	}

	return result, nil
}

func decodeBool(data []byte) (bool, error) {
	if len(data) < 32 {
		return false, nil
	}
	return new(big.Int).SetBytes(data[0:32]).Sign() > 0, nil
}

func decodeVerificationResult(data []byte) (bool, *big.Int, error) {
	if len(data) < 64 {
		return false, big.NewInt(0), nil
	}

	valid := new(big.Int).SetBytes(data[0:32]).Sign() > 0
	expiresAt := new(big.Int).SetBytes(data[32:64])

	return valid, expiresAt, nil
}

func StringToBytes32(s string) [32]byte {
	var b [32]byte
	copy(b[:], []byte(s[:min(len(s), 32)]))
	return b
}

func Bytes32ToString(b [32]byte) string {
	return strings.TrimRight(string(b[:]), "\x00")
}

func StringsToBytes32Array(strs []string) [][32]byte {
	result := make([][32]byte, len(strs))
	for i, s := range strs {
		result[i] = StringToBytes32(s)
	}
	return result
}

func Bytes32ArrayToStrings(arr [][32]byte) []string {
	result := make([]string, len(arr))
	for i, b := range arr {
		result[i] = Bytes32ToString(b)
	}
	return result
}

func StringToHash(s string) [32]byte {
	hash := crypto.Keccak256Hash([]byte(s))
	var b [32]byte
	copy(b[:], hash.Bytes())
	return b
}
