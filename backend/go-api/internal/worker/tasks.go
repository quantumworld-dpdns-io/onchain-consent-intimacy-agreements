package worker

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"

	"github.com/onchain-consent/backend/go-api/internal/config"
	qdrantclient "github.com/onchain-consent/backend/go-api/internal/qdrant"
	redisclient "github.com/onchain-consent/backend/go-api/internal/redis"
)

type ProofGenData struct {
	ConsentID string `json:"consent_id"`
	ProofType string `json:"proof_type"`
	Chain     string `json:"chain"`
}

type QdrantIndexData struct {
	ConsentID  string    `json:"consent_id"`
	Parties    []string  `json:"parties"`
	Scopes     []string  `json:"scopes"`
	ValidFrom  uint64    `json:"valid_from"`
	ValidUntil uint64    `json:"valid_until"`
	Revoked    bool      `json:"revoked"`
	Chain      string    `json:"chain"`
	TxHash     string    `json:"tx_hash"`
	CreatedAt  uint64    `json:"created_at"`
	Embedding  []float32 `json:"embedding"`
}

type NotificationData struct {
	Type      string `json:"type"`
	ConsentID string `json:"consent_id"`
	Party     string `json:"party"`
	Message   string `json:"message"`
}

type EventIndexData struct {
	EventType string `json:"event_type"`
	Chain     string `json:"chain"`
	BlockNum  uint64 `json:"block_number"`
	TxHash    string `json:"tx_hash"`
	Data      string `json:"data"`
}

func RegisterTaskHandlers(pool *Pool, cfg *config.Config, qdrant *qdrantclient.Client, rclient *redisclient.Client) {
	pool.RegisterHandler(TaskProofGeneration, func(ctx context.Context, task *Task) error {
		data, ok := task.Data.(*ProofGenData)
		if !ok {
			return fmt.Errorf("invalid task data type for proof generation")
		}
		return handleProofGeneration(ctx, data, cfg)
	})

	pool.RegisterHandler(TaskQdrantIndexing, func(ctx context.Context, task *Task) error {
		data, ok := task.Data.(*QdrantIndexData)
		if !ok {
			return fmt.Errorf("invalid task data type for Qdrant indexing")
		}
		return handleQdrantIndexing(ctx, data, qdrant)
	})

	pool.RegisterHandler(TaskNotificationDispatch, func(ctx context.Context, task *Task) error {
		data, ok := task.Data.(*NotificationData)
		if !ok {
			return fmt.Errorf("invalid task data type for notification dispatch")
		}
		return handleNotificationDispatch(ctx, data)
	})

	pool.RegisterHandler(TaskEventIndexing, func(ctx context.Context, task *Task) error {
		data, ok := task.Data.(*EventIndexData)
		if !ok {
			return fmt.Errorf("invalid task data type for event indexing")
		}
		return handleEventIndexing(ctx, data, qdrant, rclient)
	})
}

func handleProofGeneration(ctx context.Context, data *ProofGenData, cfg *config.Config) error {
	payload := map[string]string{
		"consent_id": data.ConsentID,
		"proof_type": data.ProofType,
		"chain":      data.Chain,
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("failed to marshal proof request: %w", err)
	}

	_ = body
	_ = cfg

	return nil
}

func handleQdrantIndexing(ctx context.Context, data *QdrantIndexData, qdrant *qdrantclient.Client) error {
	doc := &qdrantclient.ConsentDocument{
		ConsentID:  data.ConsentID,
		Parties:    data.Parties,
		Scopes:     data.Scopes,
		ValidFrom:  data.ValidFrom,
		ValidUntil: data.ValidUntil,
		Revoked:    data.Revoked,
		Chain:      data.Chain,
		TxHash:     data.TxHash,
		CreatedAt:  data.CreatedAt,
	}

	if len(data.Embedding) > 0 {
		doc.Embedding = data.Embedding
	}

	if err := qdrant.IndexConsent(ctx, doc); err != nil {
		return fmt.Errorf("failed to index consent in Qdrant: %w", err)
	}

	return nil
}

func handleNotificationDispatch(ctx context.Context, data *NotificationData) error {
	_ = data
	return nil
}

func handleEventIndexing(ctx context.Context, data *EventIndexData, qdrant *qdrantclient.Client, rclient *redisclient.Client) error {
	if data.EventType == "ConsentRegistered" || data.EventType == "ConsentRevoked" {
		if err := rclient.InvalidateConsent(ctx, data.Chain, data.TxHash); err != nil {
			return fmt.Errorf("failed to invalidate cache for event: %w", err)
		}
	}

	_ = qdrant
	_ = rclient

	return nil
}

func NewTask(taskType TaskType, data interface{}) *Task {
	return &Task{
		ID:         uuid.New().String(),
		Type:       taskType,
		Data:       data,
		Status:     TaskPending,
		CreatedAt:  time.Now(),
		UpdatedAt:  time.Now(),
		MaxRetries: 3,
	}
}

func NewProofGenerationTask(consentID, proofType, chain string) *Task {
	return NewTask(TaskProofGeneration, &ProofGenData{
		ConsentID: consentID,
		ProofType: proofType,
		Chain:     chain,
	})
}

func NewQdrantIndexingTask(doc *QdrantIndexData) *Task {
	return NewTask(TaskQdrantIndexing, doc)
}

func NewNotificationTask(notifType, consentID, party, message string) *Task {
	return NewTask(TaskNotificationDispatch, &NotificationData{
		Type:      notifType,
		ConsentID: consentID,
		Party:     party,
		Message:   message,
	})
}

func NewEventIndexingTask(eventType, chain string, blockNum uint64, txHash, data string) *Task {
	return NewTask(TaskEventIndexing, &EventIndexData{
		EventType: eventType,
		Chain:     chain,
		BlockNum:  blockNum,
		TxHash:    txHash,
		Data:      data,
	})
}
