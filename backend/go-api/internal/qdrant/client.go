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

	"github.com/onchain-consent/backend/go-api/internal/config"
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

type SearchParams struct {
	Query   string   `json:"query"`
	Chain   string   `json:"chain"`
	Party   string   `json:"party"`
	Scope   string   `json:"scope"`
	Limit   int      `json:"limit"`
	Offset  int      `json:"offset"`
}

type Client struct {
	conn         *grpc.ClientConn
	points       pb.PointsClient
	collections  pb.CollectionsClient
	config       config.QdrantConfig
	logger       *zerolog.Logger
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
		conn:         conn,
		points:       pb.NewPointsClient(conn),
		collections:  pb.NewCollectionsClient(conn),
		config:       cfg,
		logger:       logger,
	}

	if err := c.ensureCollection(context.Background()); err != nil {
		logger.Warn().Err(err).Msg("failed to ensure Qdrant collection exists")
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

func (c *Client) ensureCollection(ctx context.Context) error {
	ctx = c.authContext(ctx)

	listResp, err := c.collections.List(ctx, &pb.ListCollectionsRequest{})
	if err != nil {
		return fmt.Errorf("failed to list collections: %w", err)
	}

	for _, col := range listResp.GetCollections() {
		if col.GetName() == c.config.CollectionName {
			c.logger.Info().Str("collection", c.config.CollectionName).Msg("collection already exists")
			return nil
		}
	}

	distance := pb.Distance_Cosine
	onDisk := true

	req := &pb.CreateCollection{
		CollectionName: c.config.CollectionName,
		VectorsConfig: &pb.VectorsConfig{
			Config: &pb.VectorsConfig_Params{
				Params: &pb.VectorParams{
					Size:     uint64(c.config.VectorSize),
					Distance: distance,
					OnDisk:   &onDisk,
				},
			},
		},
	}

	_, err = c.collections.Create(ctx, req)
	if err != nil {
		return fmt.Errorf("failed to create collection: %w", err)
	}

	c.logger.Info().Str("collection", c.config.CollectionName).Int("vector_size", c.config.VectorSize).Msg("collection created")
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

func (c *Client) UpdateConsentRevoked(ctx context.Context, consentID string, revoked bool) error {
	ctx = c.authContext(ctx)

	points, err := c.findByConsentID(ctx, consentID)
	if err != nil {
		return err
	}

	for _, p := range points {
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

func (c *Client) findByConsentID(ctx context.Context, consentID string) ([]*pb.RetrievedPoint, error) {
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

	resp, err := c.points.Scroll(ctx, &pb.ScrollPoints{
		CollectionName: c.config.CollectionName,
		Filter:         filter,
		Limit:          100,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to scroll points: %w", err)
	}

	return resp.GetResult(), nil
}

func (c *Client) Search(ctx context.Context, params *SearchParams) ([]*ConsentDocument, error) {
	ctx = c.authContext(ctx)

	conditions := make([]*pb.Condition, 0)

	if params.Chain != "" {
		conditions = append(conditions, &pb.Condition{
			ConditionOneOf: &pb.Condition_Field{
				Field: &pb.FieldCondition{
					Key: "chain",
					Match: &pb.Match{
						MatchValue: &pb.Match_Keyword{Keyword: params.Chain},
					},
				},
			},
		})
	}
	if params.Party != "" {
		conditions = append(conditions, &pb.Condition{
			ConditionOneOf: &pb.Condition_Field{
				Field: &pb.FieldCondition{
					Key: "parties",
					Match: &pb.Match{
						MatchValue: &pb.Match_Keyword{Keyword: params.Party},
					},
				},
			},
		})
	}
	if params.Scope != "" {
		conditions = append(conditions, &pb.Condition{
			ConditionOneOf: &pb.Condition_Field{
				Field: &pb.FieldCondition{
					Key: "scopes",
					Match: &pb.Match{
						MatchValue: &pb.Match_Keyword{Keyword: params.Scope},
					},
				},
			},
		})
	}

	if params.Limit <= 0 {
		params.Limit = 20
	}

	searchParams := &pb.SearchPoints{
		CollectionName: c.config.CollectionName,
		Vector:         make([]float32, c.config.VectorSize),
		Limit:          uint64(params.Limit),
		WithPayload:    &pb.WithPayloadSelector{SelectorOptions: &pb.WithPayloadSelector_Enable{Enable: true}},
	}

	if len(conditions) > 0 {
		searchParams.Filter = &pb.Filter{
			Must: conditions,
		}
	}

	resp, err := c.points.Search(ctx, searchParams)
	if err != nil {
		return nil, fmt.Errorf("failed to search points: %w", err)
	}

	results := make([]*ConsentDocument, 0, len(resp.GetResult()))
	for _, r := range resp.GetResult() {
		doc := pointToDocument(r)
		if doc != nil {
			results = append(results, doc)
		}
	}

	return results, nil
}

func (c *Client) GetConsentsByParty(ctx context.Context, party string) ([]*ConsentDocument, error) {
	return c.Search(ctx, &SearchParams{
		Party: party,
		Limit: 100,
	})
}

func pointToDocument(p *pb.ScoredPoint) *ConsentDocument {
	if p == nil {
		return nil
	}

	payload := p.GetPayload()

	doc := &ConsentDocument{}

	if v, ok := payload["consent_id"]; ok {
		doc.ConsentID = v.GetStringValue()
	}
	if v, ok := payload["chain"]; ok {
		doc.Chain = v.GetStringValue()
	}
	if v, ok := payload["tx_hash"]; ok {
		doc.TxHash = v.GetStringValue()
	}
	if v, ok := payload["revoked"]; ok {
		doc.Revoked = v.GetBoolValue()
	}

	if parties, ok := payload["parties"]; ok {
		lv := parties.GetListValue()
		for _, pv := range lv.GetValues() {
			doc.Parties = append(doc.Parties, pv.GetStringValue())
		}
	}
	if scopes, ok := payload["scopes"]; ok {
		lv := scopes.GetListValue()
		for _, sv := range lv.GetValues() {
			doc.Scopes = append(doc.Scopes, sv.GetStringValue())
		}
	}

	return doc
}
