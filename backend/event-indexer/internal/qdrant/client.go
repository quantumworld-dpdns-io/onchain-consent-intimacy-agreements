package qdrant

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	pb "github.com/qdrant/go-client/qdrant"
	"github.com/rs/zerolog"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/metadata"
	"google.golang.org/protobuf/types/known/structpb"

	"github.com/onchain-consent/backend/event-indexer/internal/config"
)

type ConsentDocument struct {
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

type Client struct {
	conn        *grpc.ClientConn
	points      pb.PointsClient
	collections pb.CollectionsClient
	config      config.QdrantConfig
	logger      *zerolog.Logger
}

func NewClient(cfg config.QdrantConfig, logger *zerolog.Logger) (*Client, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	conn, err := grpc.DialContext(ctx, cfg.URL,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithBlock(),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to Qdrant: %w", err)
	}

	c := &Client{
		conn:        conn,
		points:      pb.NewPointsClient(conn),
		collections: pb.NewCollectionsClient(conn),
		config:      cfg,
		logger:      logger,
	}

	return c, nil
}

func (c *Client) Close() error {
	return c.conn.Close()
}

func (c *Client) authContext(ctx context.Context) context.Context {
	if c.config.APIKey != "" {
		return metadata.AppendToOutgoingContext(ctx, "api-key", c.config.APIKey)
	}
	return ctx
}

func (c *Client) UpdateConsentRevoked(ctx context.Context, consentID string, revoked bool) error {
	ctx = c.authContext(ctx)

	filterVal := structpb.NewStringValue(consentID)
	filter := &pb.Filter{
		Must: []*pb.Condition{
			{
				ConditionOneOf: &pb.Condition_Field{
					Field: &pb.FieldCondition{
						Key: "consent_id",
						Match: &pb.Match{
							MatchValue: &pb.Match_Text{
								Text: filterVal.GetStringValue(),
							},
						},
					},
				},
			},
		},
	}

	scrollResp, err := c.points.Scroll(ctx, &pb.ScrollPoints{
		CollectionName: c.config.CollectionName,
		Filter:         filter,
		Limit:          100,
	})
	if err != nil {
		return fmt.Errorf("failed to scroll points: %w", err)
	}

	for _, p := range scrollResp.GetResult() {
		payload, err := structpb.NewStruct(map[string]interface{}{
			"revoked": revoked,
		})
		if err != nil {
			return fmt.Errorf("failed to create payload: %w", err)
		}

		_, err = c.points.SetPayload(ctx, &pb.SetPayloadPoints{
			CollectionName: c.config.CollectionName,
			Payload:        payload,
			Points:         []*pb.PointId{p.GetId()},
		})
		if err != nil {
			return fmt.Errorf("failed to update consent payload: %w", err)
		}
	}

	return nil
}

func (c *Client) IndexConsent(ctx context.Context, doc *ConsentDocument) error {
	ctx = c.authContext(ctx)

	payloadMap := map[string]interface{}{
		"consent_id":  doc.ConsentID,
		"parties":     doc.Parties,
		"scopes":      doc.Scopes,
		"valid_from":  fmt.Sprintf("%d", doc.ValidFrom),
		"valid_until": fmt.Sprintf("%d", doc.ValidUntil),
		"revoked":     doc.Revoked,
		"chain":       doc.Chain,
		"tx_hash":     doc.TxHash,
		"created_at":  fmt.Sprintf("%d", doc.CreatedAt),
	}

	payload, err := structpb.NewStruct(payloadMap)
	if err != nil {
		return fmt.Errorf("failed to create payload struct: %w", err)
	}

	pointID := uuid.New().String()

	_, err = c.points.Upsert(ctx, &pb.UpsertPoints{
		CollectionName: c.config.CollectionName,
		Points: []*pb.PointStruct{
			{
				Id:      &pb.PointId{PointIdOptions: &pb.PointId_Uuid{Uuid: pointID}},
				Payload: payload,
				Vectors: &pb.Vectors{VectorsOptions: &pb.Vectors_Vector{Vector: &pb.Vector{Data: doc.Embedding}}},
			},
		},
	})
	if err != nil {
		return fmt.Errorf("failed to index consent in Qdrant: %w", err)
	}

	return nil
}
