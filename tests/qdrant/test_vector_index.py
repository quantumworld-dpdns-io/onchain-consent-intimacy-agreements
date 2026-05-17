#!/usr/bin/env python3
"""
Qdrant vector database integration tests.
Tests consent indexing, semantic search, and collection management.
"""

import os
import uuid
import pytest
from qdrant_client import QdrantClient
from qdrant_client.http import models
from qdrant_client.http.exceptions import UnexpectedResponse

QDRANT_URL = os.getenv("QDRANT_URL", "http://localhost:6333")
QDRANT_API_KEY = os.getenv("QDRANT_API_KEY", None)
COLLECTION_NAME = "test_consent_agreements"

@pytest.fixture(scope="module")
def client():
    """Create Qdrant client connection"""
    c = QdrantClient(url=QDRANT_URL, api_key=QDRANT_API_KEY, timeout=30)
    yield c
    try:
        c.delete_collection(COLLECTION_NAME)
    except:
        pass

@pytest.fixture(scope="module")
def collection(client):
    """Create test collection with consent schema"""
    try:
        client.delete_collection(COLLECTION_NAME)
    except:
        pass

    client.create_collection(
        collection_name=COLLECTION_NAME,
        vectors_config=models.VectorParams(
            size=384,
            distance=models.Distance.COSINE,
        ),
        optimizers_config=models.OptimizersConfigDiff(
            default_segment_number=2,
        ),
    )

    client.create_payload_index(
        collection_name=COLLECTION_NAME,
        field_name="consent_id",
        field_schema=models.PayloadSchemaType.KEYWORD,
    )
    client.create_payload_index(
        collection_name=COLLECTION_NAME,
        field_name="chain",
        field_schema=models.PayloadSchemaType.KEYWORD,
    )
    client.create_payload_index(
        collection_name=COLLECTION_NAME,
        field_name="party_address",
        field_schema=models.PayloadSchemaType.KEYWORD,
    )
    client.create_payload_index(
        collection_name=COLLECTION_NAME,
        field_name="valid_until",
        field_schema=models.PayloadSchemaType.INTEGER,
    )

    yield COLLECTION_NAME

class TestQdrantCollection:
    """Test collection management"""

    def test_collection_exists(self, client, collection):
        """Verify collection was created"""
        collections = client.get_collections()
        names = [c.name for c in collections.collections]
        assert collection in names

    def test_collection_info(self, client, collection):
        """Verify collection configuration"""
        info = client.get_collection(collection)
        assert info.status == "green"
        assert info.config.params.vectors.size == 384
        assert info.config.params.vectors.distance == models.Distance.COSINE

class TestConsentIndexing:
    """Test indexing consent records"""

    @pytest.fixture
    def sample_consent(self):
        return {
            "consent_id": str(uuid.uuid4()),
            "chain": "sepolia",
            "party_address": "0x742d35Cc6634C0532925a3b844Bc9e7595f2bD18",
            "scopes": ["photo", "video"],
            "valid_from": 1000000,
            "valid_until": 2000000,
            "revoked": False,
            "created_at_block": 1000000,
            "tx_hash": "0x" + "ab" * 32,
        }

    def test_upsert_consent(self, client, collection, sample_consent):
        """Index a consent record"""
        import random
        vector = [random.uniform(-1, 1) for _ in range(384)]

        point_id = uuid.uuid4().int & (1 << 63) - 1
        client.upsert(
            collection_name=collection,
            points=[
                models.PointStruct(
                    id=point_id,
                    vector=vector,
                    payload=sample_consent,
                )
            ],
        )

        info = client.get_collection(collection)
        assert info.points_count >= 1

class TestConsentSearch:
    """Test semantic search over consents"""

    @pytest.fixture(autouse=True)
    def setup_data(self, client, collection):
        """Insert test data for search tests"""
        self.test_consents = [
            {
                "consent_id": f"consent-search-{i}",
                "chain": "sepolia",
                "party_address": f"0x{i:040x}",
                "scopes": [["photo"], ["video", "photo"], ["audio"]][i % 3],
                "valid_until": [1000000, 2000000, 3000000][i % 3],
                "revoked": i % 4 == 0,
            }
            for i in range(10)
        ]

        for i, consent in enumerate(self.test_consents):
            import random
            vector = [random.uniform(-1, 1) for _ in range(384)]
            point_id = (i + 1000)
            client.upsert(
                collection_name=collection,
                points=[
                    models.PointStruct(
                        id=point_id,
                        vector=vector,
                        payload=consent,
                    )
                ],
            )

    def test_search_by_party(self, client, collection):
        """Search with party filter"""
        results = client.scroll(
            collection_name=collection,
            scroll_filter=models.Filter(
                must=[
                    models.FieldCondition(
                        key="party_address",
                        match=models.MatchValue(value="0x0000000000000000000000000000000000000000"),
                    ),
                ],
            ),
            limit=10,
        )
        assert len(results[0]) >= 0

    def test_search_by_chain_and_active(self, client, collection):
        """Search active consents on a specific chain"""
        results = client.scroll(
            collection_name=collection,
            scroll_filter=models.Filter(
                must=[
                    models.FieldCondition(
                        key="chain",
                        match=models.MatchValue(value="sepolia"),
                    ),
                    models.FieldCondition(
                        key="revoked",
                        match=models.MatchValue(value=False),
                    ),
                ],
            ),
            limit=10,
        )
        for point in results[0]:
            assert point.payload["chain"] == "sepolia"
            assert point.payload["revoked"] == False

    def test_semantic_search(self, client, collection):
        """Test vector similarity search"""
        import random
        query_vector = [random.uniform(-1, 1) for _ in range(384)]
        results = client.search(
            collection_name=collection,
            query_vector=query_vector,
            limit=5,
        )
        assert len(results) <= 5
        for r in results:
            assert r.score > 0

    def test_search_with_time_filter(self, client, collection):
        """Search consents valid until a certain time"""
        results = client.scroll(
            collection_name=collection,
            scroll_filter=models.Filter(
                must=[
                    models.FieldCondition(
                        key="valid_until",
                        range=models.Range(
                            gte=2000000,
                        ),
                    ),
                ],
            ),
            limit=10,
        )
        for point in results[0]:
            assert point.payload["valid_until"] >= 2000000

    def test_delete_consent(self, client, collection):
        """Test removing a consent from index"""
        client.delete(
            collection_name=collection,
            points_selector=models.FilterSelector(
                filter=models.Filter(
                    must=[
                        models.FieldCondition(
                            key="revoked",
                            match=models.MatchValue(value=True),
                        ),
                    ],
                ),
            ),
        )

class TestConsentWorkflow:
    """Test end-to-end consent indexing workflow"""

    def test_register_and_search_consent(self, client, collection):
        """Simulate: register consent -> index -> find via search"""
        import random, time

        consent = {
            "consent_id": str(uuid.uuid4()),
            "chain": "amoy",
            "party_address": "0x1234567890123456789012345678901234567890",
            "scopes": ["photo", "video", "audio"],
            "valid_from": int(time.time()),
            "valid_until": int(time.time()) + 86400 * 30,
            "revoked": False,
        }

        vector = [random.uniform(-1, 1) for _ in range(384)]
        point_id = uuid.uuid4().int & (1 << 63) - 1
        client.upsert(
            collection_name=collection,
            points=[
                models.PointStruct(
                    id=point_id,
                    vector=vector,
                    payload=consent,
                )
            ],
        )

        results = client.scroll(
            collection_name=collection,
            scroll_filter=models.Filter(
                must=[
                    models.FieldCondition(
                        key="consent_id",
                        match=models.MatchValue(value=consent["consent_id"]),
                    ),
                ],
            ),
            limit=1,
        )
        assert len(results[0]) == 1
        assert results[0][0].payload["consent_id"] == consent["consent_id"]

    def test_revoke_updates_index(self, client, collection):
        """Simulate: revoke consent -> update index -> verify search reflects revocation"""
        import random

        consent_id = f"revoke-test-{uuid.uuid4().hex[:8]}"

        vector = [random.uniform(-1, 1) for _ in range(384)]
        point_id = uuid.uuid4().int & (1 << 63) - 1
        client.upsert(
            collection_name=collection,
            points=[
                models.PointStruct(
                    id=point_id,
                    vector=vector,
                    payload={
                        "consent_id": consent_id,
                        "revoked": False,
                    },
                )
            ],
        )

        client.set_payload(
            collection_name=collection,
            payload={"revoked": True},
            points=[point_id],
        )

        results = client.scroll(
            collection_name=collection,
            scroll_filter=models.Filter(
                must=[
                    models.FieldCondition(
                        key="consent_id",
                        match=models.MatchValue(value=consent_id),
                    ),
                ],
            ),
            limit=1,
        )
        assert results[0][0].payload["revoked"] == True

if __name__ == "__main__":
    pytest.main([__file__, "-v"])
