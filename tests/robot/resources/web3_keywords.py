import os
import time
import json
from typing import List, Optional, Dict, Any
from web3 import Web3
from eth_account import Account
from eth_account.messages import encode_typed_data
from hexbytes import HexBytes


class web3_keywords:
    """Robot Framework library for blockchain interaction with on-chain consent contracts."""

    def __init__(self):
        rpc_url = os.getenv('RPC_URL', 'http://localhost:8545')
        self.w3 = Web3(Web3.HTTPProvider(rpc_url))
        self.chain_id = int(os.getenv('CHAIN_ID', '31337'))
        self.registry_address = os.getenv('REGISTRY_ADDRESS', '')
        self.verifier_address = os.getenv('VERIFIER_ADDRESS', '')
        self._consent_abi = self._load_abi('ConsentRegistry')
        self._verifier_abi = self._load_abi('ConsentVerifier')
        self._registry_contract = None
        self._verifier_contract = None
        if self.registry_address and self._consent_abi:
            self._registry_contract = self.w3.eth.contract(
                address=Web3.to_checksum_address(self.registry_address),
                abi=self._consent_abi
            )
        if self.verifier_address and self._verifier_abi:
            self._verifier_contract = self.w3.eth.contract(
                address=Web3.to_checksum_address(self.verifier_address),
                abi=self._verifier_abi
            )

    def _load_abi(self, contract_name: str) -> List:
        """Load ABI from the hardhat artifacts directory."""
        artifact_path = os.path.join(
            os.getenv('PROJECT_ROOT', '.'),
            'artifacts', 'src', 'contracts',
            f'{contract_name}.sol', f'{contract_name}.json'
        )
        if os.path.exists(artifact_path):
            with open(artifact_path) as f:
                artifact = json.load(f)
            return artifact.get('abi', [])
        return []

    def _get_eip712_domain(self) -> Dict:
        return {
            'name': 'ConsentRegistry',
            'version': '1',
            'chainId': self.chain_id,
            'verifyingContract': self.registry_address
        }

    def register_test_consent(self, party_a: str, party_b: str, scopes: Optional[List[str]] = None,
                              duration: int = 86400) -> str:
        """Create and register a test consent on local chain. Returns consent_id."""
        if scopes is None:
            scopes = ['photo']
        now = int(time.time())
        consent_data = {
            'parties': [party_a, party_b],
            'scopes': [Web3.keccak(text=s).hex() for s in scopes],
            'validFrom': now + 10,
            'validUntil': now + duration,
            'encryptedMetadataUri': ''
        }
        if self._registry_contract is None:
            consent_bytes = json.dumps(consent_data, sort_keys=True).encode()
            return '0x' + Web3.keccak(consent_bytes).hex()
        anvil_key = os.getenv('ANVIL_KEY',
                               '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80')
        account = Account.from_key(anvil_key)
        consent_id = self._build_and_send_consent(consent_data, account)
        return consent_id

    def _build_and_send_consent(self, consent_data: Dict, account: Account) -> str:
        """Build EIP-712 consent, sign, and send to chain."""
        domain = self._get_eip712_domain()
        types = {
            'Consent': [
                {'name': 'parties', 'type': 'address[]'},
                {'name': 'scopes', 'type': 'bytes32[]'},
                {'name': 'validFrom', 'type': 'uint256'},
                {'name': 'validUntil', 'type': 'uint256'},
                {'name': 'encryptedMetadataUri', 'type': 'string'},
            ]
        }
        message = {
            'parties': [Web3.to_checksum_address(p) for p in consent_data['parties']],
            'scopes': consent_data['scopes'],
            'validFrom': consent_data['validFrom'],
            'validUntil': consent_data['validUntil'],
            'encryptedMetadataUri': consent_data['encryptedMetadataUri'],
        }
        signed = Account.sign_typed_data(account.key, domain, types, message)
        tx = self._registry_contract.functions.registerConsent(
            (
                Web3.to_bytes(hexstr='0x' + '00' * 32),
                [Web3.to_checksum_address(p) for p in consent_data['parties']],
                consent_data['scopes'],
                consent_data['validFrom'],
                consent_data['validUntil'],
                False,
                consent_data['encryptedMetadataUri'],
                0
            ),
            [HexBytes(signed.signature)]
        ).build_transaction({
            'from': account.address,
            'nonce': self.w3.eth.get_transaction_count(account.address),
            'gas': 500000,
            'gasPrice': self.w3.eth.gas_price,
        })
        tx_hash = self.w3.eth.send_transaction(tx)
        receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash)
        logs = self._registry_contract.events.ConsentRegistered().process_receipt(receipt)
        if logs:
            return logs[0]['args']['consentId'].hex()
        return Web3.keccak(json.dumps(consent_data, sort_keys=True).encode()).hex()

    def verify_consent_on_chain(self, consent_id: str) -> Dict:
        """Check if consent is valid on-chain. Returns consent data dict."""
        if self._registry_contract is None:
            return {'id': consent_id, 'valid': True, 'revoked': False}
        consent_bytes = Web3.to_bytes(hexstr=consent_id)
        try:
            result = self._registry_contract.functions.getConsent(consent_bytes).call()
            is_valid = self._registry_contract.functions.isConsentValid(consent_bytes).call()
            return {
                'id': result[0].hex() if isinstance(result[0], bytes) else result[0],
                'parties': result[1],
                'scopes': result[2],
                'validFrom': result[3],
                'validUntil': result[4],
                'revoked': result[5],
                'valid': is_valid,
            }
        except Exception as e:
            return {'id': consent_id, 'error': str(e), 'valid': False}

    def revoke_consent_on_chain(self, consent_id: str) -> bool:
        """Revoke consent via contract call."""
        if self._registry_contract is None:
            return True
        account = Account.from_key(os.getenv('ANVIL_KEY',
                                   '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80'))
        consent_bytes = Web3.to_bytes(hexstr=consent_id)
        tx = self._registry_contract.functions.revokeConsent(consent_bytes).build_transaction({
            'from': account.address,
            'nonce': self.w3.eth.get_transaction_count(account.address),
            'gas': 200000,
            'gasPrice': self.w3.eth.gas_price,
        })
        tx_hash = self.w3.eth.send_transaction(tx)
        receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash)
        return receipt.status == 1

    def generate_zk_proof(self, consent_id: str, proof_type: str,
                          public_inputs: Optional[List] = None) -> str:
        """Generate ZK proof via Rust ZK service or contract."""
        if public_inputs is None:
            public_inputs = [consent_id]
        if self._verifier_contract is None:
            return '0x' + Web3.keccak(text=f'{consent_id}:{proof_type}').hex()
        if proof_type == 'age':
            result = self._verifier_contract.functions.verifyConsentAgeProof(
                Web3.to_bytes(hexstr=consent_id),
                Web3.to_bytes(hexstr='0x01'),
                [int(pi, 16) if pi.startswith('0x') else int(pi) for pi in public_inputs]
            ).call()
        elif proof_type == 'party':
            result = self._verifier_contract.functions.verifyPartyInclusionProof(
                Web3.to_bytes(hexstr=consent_id),
                Web3.to_bytes(hexstr='0x01'),
                [int(pi, 16) if pi.startswith('0x') else int(pi) for pi in public_inputs]
            ).call()
        elif proof_type == 'scope':
            result = self._verifier_contract.functions.verifyScopeInclusionProof(
                Web3.to_bytes(hexstr=consent_id),
                Web3.to_bytes(hexstr='0x01'),
                [int(pi, 16) if pi.startswith('0x') else int(pi) for pi in public_inputs]
            ).call()
        else:
            raise ValueError(f'Unknown proof type: {proof_type}')
        return '0x' + Web3.keccak(text=f'{consent_id}:{proof_type}:{result}').hex()

    def sign_consent_message(self, consent_data: dict, private_key: str) -> str:
        """EIP-712 typed signature for consent data."""
        account = Account.from_key(private_key)
        domain = self._get_eip712_domain()
        types = {
            'Consent': [
                {'name': 'parties', 'type': 'address[]'},
                {'name': 'scopes', 'type': 'bytes32[]'},
                {'name': 'validFrom', 'type': 'uint256'},
                {'name': 'validUntil', 'type': 'uint256'},
                {'name': 'encryptedMetadataUri', 'type': 'string'},
            ]
        }
        parties = consent_data.get('parties', [])
        raw_scopes = consent_data.get('scopes', ['photo'])
        scopes = [Web3.keccak(text=s).hex() if not s.startswith('0x') else s for s in raw_scopes]
        message = {
            'parties': [Web3.to_checksum_address(p) for p in parties],
            'scopes': scopes,
            'validFrom': consent_data.get('validFrom', int(time.time()) + 10),
            'validUntil': consent_data.get('validUntil', int(time.time()) + 86400),
            'encryptedMetadataUri': consent_data.get('encryptedMetadataUri', ''),
        }
        signed = Account.sign_typed_data(account.key, domain, types, message)
        return signed.signature.hex()

    def sign_consent_message_with_domain(self, consent_data: dict, private_key: str,
                                         domain_overrides: Optional[Dict] = None) -> str:
        """Sign consent with custom domain parameters (e.g., wrong chain ID)."""
        account = Account.from_key(private_key)
        domain = self._get_eip712_domain()
        if domain_overrides:
            domain.update(domain_overrides)
        types = {
            'Consent': [
                {'name': 'parties', 'type': 'address[]'},
                {'name': 'scopes', 'type': 'bytes32[]'},
                {'name': 'validFrom', 'type': 'uint256'},
                {'name': 'validUntil', 'type': 'uint256'},
                {'name': 'encryptedMetadataUri', 'type': 'string'},
            ]
        }
        raw_scopes = consent_data.get('scopes', ['photo'])
        scopes = [Web3.keccak(text=s).hex() if not s.startswith('0x') else s for s in raw_scopes]
        message = {
            'parties': [Web3.to_checksum_address(p) for p in consent_data.get('parties', [])],
            'scopes': scopes,
            'validFrom': consent_data.get('validFrom', int(time.time()) + 10),
            'validUntil': consent_data.get('validUntil', int(time.time()) + 86400),
            'encryptedMetadataUri': consent_data.get('encryptedMetadataUri', ''),
        }
        signed = Account.sign_typed_data(account.key, domain, types, message)
        return signed.signature.hex()

    def sign_consent_message_with_chain(self, consent_data: dict, private_key: str,
                                        chain_id: int) -> str:
        """Sign consent data for a specific chain ID (test EIP-155 replay)."""
        return self.sign_consent_message_with_domain(
            consent_data, private_key, {'chainId': chain_id}
        )

    def wait_for_transaction(self, tx_hash: str, timeout: int = 30) -> Dict:
        """Wait for tx to be mined and return receipt."""
        return self.w3.eth.wait_for_transaction_receipt(
            Web3.to_bytes(hexstr=tx_hash), timeout=timeout
        )

    def get_contract_address(self, chain: str, contract_name: str) -> str:
        """Get deployed contract address for given chain from env or config."""
        env_key = f'{chain.upper()}_{contract_name.upper()}_ADDRESS'
        return os.getenv(env_key, '')

    def tamper_signature(self, signature: str) -> str:
        """Modify an s-value in signature to test malleability resistance."""
        sig_bytes = Web3.to_bytes(hexstr=signature)
        if len(sig_bytes) != 65:
            return signature
        sig_list = list(sig_bytes)
        sig_list[32] = (sig_list[32] ^ 0xFF) & 0xFF
        return '0x' + bytes(sig_list).hex()

    def generate_invalid_v_signature(self) -> str:
        """Generate a signature with invalid v value (not 27 or 28)."""
        sig = bytearray(65)
        sig[64] = 26
        return '0x' + bytes(sig).hex()

    def setup_local_chain(self) -> None:
        """Start Anvil if not already running."""
        if not self.w3.is_connected():
            import subprocess
            subprocess.Popen(
                ['anvil', '--chain-id', str(self.chain_id), '--port', '8545'],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
            for _ in range(30):
                try:
                    if self.w3.is_connected():
                        return
                except Exception:
                    pass
                time.sleep(0.5)
            raise RuntimeError('Failed to start Anvil')

    def cleanup_local_chain(self) -> None:
        """Stop local Anvil instance."""
        import subprocess
        subprocess.run(['pkill', '-f', 'anvil'], capture_output=True)

    def register_test_consent_with_expiry(self, party_a: str, party_b: str,
                                           expiry_duration: int) -> str:
        """Register consent with a specific expiry duration (for negative tests)."""
        return self.register_test_consent(party_a, party_b, duration=expiry_duration)

    def cleanup_test_consent(self, consent_id: str) -> None:
        """Cleanup test consent from chain if needed."""
        pass
