package api

import (
	"context"
	"fmt"
	"math/big"
	"strings"
	"sync"
	"time"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/rs/zerolog"

	"github.com/onchain-consent/backend/go-api/internal/config"
)

type ChainID uint64

const (
	ChainSepolia     ChainID = 11155111
	ChainBSCTestnet  ChainID = 97
	ChainAmoy        ChainID = 80002
	ChainPalmTestnet ChainID = 11297108099
	ChainBaseSepolia ChainID = 84532
)

var chainNames = map[ChainID]string{
	ChainSepolia:     "sepolia",
	ChainBSCTestnet:  "bsc-testnet",
	ChainAmoy:        "amoy",
	ChainPalmTestnet: "palm-testnet",
	ChainBaseSepolia: "base-sepolia",
}

type ChainManager struct {
	mu       sync.RWMutex
	clients  map[string]*ethclient.Client
	config   *config.Config
	logger   *zerolog.Logger
}

func NewChainManager(cfg *config.Config, logger *zerolog.Logger) *ChainManager {
	return &ChainManager{
		clients: make(map[string]*ethclient.Client),
		config:  cfg,
		logger:  logger,
	}
}

func (m *ChainManager) GetClient(chain string) (*ethclient.Client, error) {
	m.mu.RLock()
	client, ok := m.clients[chain]
	m.mu.RUnlock()

	if ok {
		return client, nil
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	if client, ok = m.clients[chain]; ok {
		return client, nil
	}

	rpcURL, err := m.getRPCURL(chain)
	if err != nil {
		return nil, err
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	client, err = ethclient.DialContext(ctx, rpcURL)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to %s RPC: %w", chain, err)
	}

	m.clients[chain] = client
	m.logger.Info().Str("chain", chain).Str("rpc", rpcURL).Msg("connected to chain")
	return client, nil
}

func (m *ChainManager) getRPCURL(chain string) (string, error) {
	switch strings.ToLower(chain) {
	case "sepolia":
		return m.config.Chains.SepoliaRPC, nil
	case "bsc-testnet", "bsc_testnet", "bsc":
		return m.config.Chains.BSCTestnetRPC, nil
	case "amoy":
		return m.config.Chains.AmoyRPC, nil
	case "palm-testnet", "palm_testnet", "palm":
		return m.config.Chains.PalmTestnetRPC, nil
	case "base-sepolia", "base_sepolia", "base":
		return m.config.Chains.BaseSepoliaRPC, nil
	default:
		return "", fmt.Errorf("unsupported chain: %s", chain)
	}
}

func (m *ChainManager) GetRegistryAddress(chain string) (common.Address, error) {
	var addr string
	switch strings.ToLower(chain) {
	case "sepolia":
		addr = m.config.Chains.SepoliaRegistry
	case "bsc-testnet", "bsc_testnet", "bsc":
		addr = m.config.Chains.BSCTestnetRegistry
	case "amoy":
		addr = m.config.Chains.AmoyRegistry
	case "palm-testnet", "palm_testnet", "palm":
		addr = m.config.Chains.PalmTestnetRegistry
	case "base-sepolia", "base_sepolia", "base":
		addr = m.config.Chains.BaseSepoliaRegistry
	default:
		return common.Address{}, fmt.Errorf("unsupported chain: %s", chain)
	}

	if addr == "" {
		return common.Address{}, fmt.Errorf("registry address not configured for chain: %s", chain)
	}

	return common.HexToAddress(addr), nil
}

func (m *ChainManager) GetChainID(chain string) (ChainID, error) {
	switch strings.ToLower(chain) {
	case "sepolia":
		return ChainSepolia, nil
	case "bsc-testnet", "bsc_testnet", "bsc":
		return ChainBSCTestnet, nil
	case "amoy":
		return ChainAmoy, nil
	case "palm-testnet", "palm_testnet", "palm":
		return ChainPalmTestnet, nil
	case "base-sepolia", "base_sepolia", "base":
		return ChainBaseSepolia, nil
	default:
		return 0, fmt.Errorf("unsupported chain: %s", chain)
	}
}

func (m *ChainManager) GetChainName(chainID ChainID) string {
	return chainNames[chainID]
}

func (m *ChainManager) IsChainSupported(chain string) bool {
	_, err := m.getRPCURL(chain)
	return err == nil
}

func (m *ChainManager) SubmitTransaction(ctx context.Context, chain string, to common.Address, data []byte, gasLimit uint64) (common.Hash, error) {
	client, err := m.GetClient(chain)
	if err != nil {
		return common.Hash{}, err
	}

	chainID, err := client.ChainID(ctx)
	if err != nil {
		return common.Hash{}, fmt.Errorf("failed to get chain ID: %w", err)
	}

	gasPrice, err := client.SuggestGasPrice(ctx)
	if err != nil {
		return common.Hash{}, fmt.Errorf("failed to suggest gas price: %w", err)
	}

	msg := ethereum.CallMsg{
		To:    &to,
		Data:  data,
		Gas:   gasLimit,
		GasPrice: gasPrice,
	}

	gasLimit, err = client.EstimateGas(ctx, msg)
	if err != nil {
		return common.Hash{}, fmt.Errorf("failed to estimate gas: %w", err)
	}

	gasFeeCap := new(big.Int).Mul(gasPrice, big.NewInt(2))
	gasTipCap := gasPrice

	tx := types.NewTx(&types.DynamicFeeTx{
		ChainID:   chainID,
		Nonce:     0,
		GasFeeCap: gasFeeCap,
		GasTipCap: gasTipCap,
		Gas:       gasLimit,
		To:        &to,
		Data:      data,
	})

	m.logger.Info().
		Str("chain", chain).
		Str("to", to.Hex()).
		Uint64("gas_limit", gasLimit).
		Str("gas_price", gasPrice.String()).
		Msg("transaction created, requires signing")

	return tx.Hash(), fmt.Errorf("transaction requires external signing - tx hash: %s", tx.Hash().Hex())
}

func (m *ChainManager) WaitForReceipt(ctx context.Context, client *ethclient.Client, txHash common.Hash, timeout time.Duration) (*types.Receipt, error) {
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	for {
		receipt, err := client.TransactionReceipt(ctx, txHash)
		if err != nil {
			if err == ethereum.NotFound {
				select {
				case <-ctx.Done():
					return nil, fmt.Errorf("timeout waiting for transaction receipt: %s", txHash.Hex())
				case <-time.After(500 * time.Millisecond):
					continue
				}
			}
			return nil, fmt.Errorf("failed to get transaction receipt: %w", err)
		}
		return receipt, nil
	}
}

func (m *ChainManager) GetChainStatus(ctx context.Context, chain string) (*ChainInfo, error) {
	client, err := m.GetClient(chain)
	if err != nil {
		return &ChainInfo{
			Name:     chain,
			RPCReady: false,
		}, nil
	}

	chainID, err := client.ChainID(ctx)
	if err != nil {
		return &ChainInfo{
			Name:     chain,
			RPCReady: false,
		}, nil
	}

	block, err := client.BlockNumber(ctx)
	if err != nil {
		return &ChainInfo{
			Name:     chain,
			RPCReady: false,
		}, nil
	}

	gasPrice, err := client.SuggestGasPrice(ctx)
	if err != nil {
		gasPrice = big.NewInt(0)
	}

	return &ChainInfo{
		Name:        chain,
		ChainID:     chainID.Uint64(),
		RPCReady:    true,
		LatestBlock: block,
		GasPrice:    gasPrice.String(),
	}, nil
}

func (m *ChainManager) CloseAll() {
	m.mu.Lock()
	defer m.mu.Unlock()

	for chain, client := range m.clients {
		client.Close()
		delete(m.clients, chain)
	}
}
