// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {ConsentVerifier} from "../../src/contracts/ConsentVerifier.sol";
import {ConsentRegistry} from "../../src/contracts/ConsentRegistry.sol";
import {MockVerifier} from "../../src/mocks/MockVerifier.sol";
import {IConsentVerifier} from "../../src/interfaces/IConsentVerifier.sol";

contract ConsentVerifierTest is Test {
    ConsentVerifier public verifier;
    ConsentRegistry public registry;
    MockVerifier public mockVerifier;

    bytes32 constant CONSENT_ID = keccak256("test-consent");

    bytes VALID_PROOF = hex"0123456789abcdef";
    bytes EMPTY_PROOF = hex"";

    uint256[] VALID_INPUTS = [1, 2, 3];
    uint256[] EMPTY_INPUTS;
    uint256[] SINGLE_INPUT = [42];

    event ProofVerified(bytes32 indexed consentId, string proofType, bytes32 proofHash);

    function setUp() public {
        registry = new ConsentRegistry();
        verifier = new ConsentVerifier(address(registry));
        mockVerifier = new MockVerifier();
    }

    function test_ConsentVerifier_Constructor_RevertsZeroAddress() public {
        vm.expectRevert("ConsentVerifier: invalid registry address");
        new ConsentVerifier(address(0));
    }

    function test_ConsentVerifier_RegistryAddress() public {
        assertEq(address(verifier.consentRegistry()), address(registry), "registry address should match");
    }

    function test_VerifyAgeProof_Success() public {
        vm.expectEmit(true, true, true, true);
        emit ProofVerified(CONSENT_ID, "age", keccak256(abi.encodePacked(CONSENT_ID, "age", VALID_PROOF, VALID_INPUTS)));

        bool result = verifier.verifyConsentAgeProof(CONSENT_ID, VALID_PROOF, VALID_INPUTS);
        assertTrue(result, "age proof should verify");
    }

    function test_VerifyPartyInclusionProof_Success() public {
        vm.expectEmit(true, true, true, true);
        emit ProofVerified(
            CONSENT_ID, "party", keccak256(abi.encodePacked(CONSENT_ID, "party", VALID_PROOF, VALID_INPUTS))
        );

        bool result = verifier.verifyPartyInclusionProof(CONSENT_ID, VALID_PROOF, VALID_INPUTS);
        assertTrue(result, "party inclusion proof should verify");
    }

    function test_VerifyScopeInclusionProof_Success() public {
        vm.expectEmit(true, true, true, true);
        emit ProofVerified(
            CONSENT_ID, "scope", keccak256(abi.encodePacked(CONSENT_ID, "scope", VALID_PROOF, VALID_INPUTS))
        );

        bool result = verifier.verifyScopeInclusionProof(CONSENT_ID, VALID_PROOF, VALID_INPUTS);
        assertTrue(result, "scope inclusion proof should verify");
    }

    function test_ProofReplayPrevention() public {
        verifier.verifyConsentAgeProof(CONSENT_ID, VALID_PROOF, VALID_INPUTS);

        bytes32 proofHash = keccak256(abi.encodePacked(CONSENT_ID, "age", VALID_PROOF, VALID_INPUTS));
        assertTrue(verifier.isProofUsed(proofHash), "proof hash should be marked used");

        vm.expectRevert(
            abi.encodeWithSelector(IConsentVerifier.ProofAlreadyUsed.selector, proofHash)
        );
        verifier.verifyConsentAgeProof(CONSENT_ID, VALID_PROOF, VALID_INPUTS);
    }

    function test_EmptyProof_Reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IConsentVerifier.InvalidProof.selector, CONSENT_ID, "age proof verification failed")
        );
        verifier.verifyConsentAgeProof(CONSENT_ID, EMPTY_PROOF, VALID_INPUTS);
    }

    function test_EmptyPublicInputs_Reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConsentVerifier.InvalidProof.selector, CONSENT_ID, "missing consent age public inputs"
            )
        );
        verifier.verifyConsentAgeProof(CONSENT_ID, VALID_PROOF, EMPTY_INPUTS);
    }

    function test_InsufficientPartyInputs_Reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConsentVerifier.InvalidProof.selector, CONSENT_ID, "missing party inclusion public inputs"
            )
        );
        verifier.verifyPartyInclusionProof(CONSENT_ID, VALID_PROOF, EMPTY_INPUTS);
    }

    function test_InsufficientScopeInputs_Reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConsentVerifier.InvalidProof.selector, CONSENT_ID, "missing scope inclusion public inputs"
            )
        );
        verifier.verifyScopeInclusionProof(CONSENT_ID, VALID_PROOF, EMPTY_INPUTS);
    }

    function test_GetUsedProofs() public {
        verifier.verifyConsentAgeProof(CONSENT_ID, VALID_PROOF, VALID_INPUTS);

        bytes32 proofHash = keccak256(abi.encodePacked(CONSENT_ID, "age", VALID_PROOF, VALID_INPUTS));
        bytes32[] memory used = verifier.getUsedProofs(CONSENT_ID);
        assertEq(used.length, 1, "should have 1 used proof");
        assertEq(used[0], proofHash, "proof hash should match");
    }

    function test_MultipleProofsForSameConsent() public {
        bytes memory proof1 = hex"01";
        bytes memory proof2 = hex"02";
        uint256[] memory inputs1 = new uint256[](1);
        inputs1[0] = 1;
        uint256[] memory inputs2 = new uint256[](1);
        inputs2[0] = 2;

        verifier.verifyConsentAgeProof(CONSENT_ID, proof1, inputs1);
        verifier.verifyConsentAgeProof(CONSENT_ID, proof2, inputs2);

        bytes32[] memory used = verifier.getUsedProofs(CONSENT_ID);
        assertEq(used.length, 2, "should have 2 used proofs");
    }

    function test_MockVerifier_AgeProof() public {
        bool result = mockVerifier.verifyConsentAgeProof(CONSENT_ID, VALID_PROOF, VALID_INPUTS);
        assertTrue(result, "mock should verify age proof");
    }

    function test_MockVerifier_EmptyProof_Reverts() public {
        vm.expectRevert("MockVerifier: empty proof");
        mockVerifier.verifyConsentAgeProof(CONSENT_ID, EMPTY_PROOF, VALID_INPUTS);
    }

    function test_MockVerifier_EmptyInputs_Reverts() public {
        vm.expectRevert("MockVerifier: empty public inputs");
        mockVerifier.verifyConsentAgeProof(CONSENT_ID, VALID_PROOF, EMPTY_INPUTS);
    }

    function test_MockVerifier_ZeroPublicInput_Reverts() public {
        uint256[] memory badInputs = new uint256[](1);
        badInputs[0] = 0;
        vm.expectRevert("MockVerifier: zero public input");
        mockVerifier.verifyConsentAgeProof(CONSENT_ID, VALID_PROOF, badInputs);
    }

    function test_MockVerifier_Replay_Reverts() public {
        mockVerifier.verifyConsentAgeProof(CONSENT_ID, VALID_PROOF, VALID_INPUTS);
        bytes32 proofHash = keccak256(abi.encodePacked(CONSENT_ID, "age", VALID_PROOF, VALID_INPUTS));

        assertTrue(mockVerifier.isProofUsed(proofHash), "proof should be used");
        vm.expectRevert(
            abi.encodeWithSelector(IConsentVerifier.ProofAlreadyUsed.selector, proofHash)
        );
        mockVerifier.verifyConsentAgeProof(CONSENT_ID, VALID_PROOF, VALID_INPUTS);
    }

    function test_MockVerifier_PartyAndScope() public {
        assertTrue(mockVerifier.verifyPartyInclusionProof(CONSENT_ID, VALID_PROOF, VALID_INPUTS));
        assertTrue(mockVerifier.verifyScopeInclusionProof(CONSENT_ID, VALID_PROOF, VALID_INPUTS));
    }
}
