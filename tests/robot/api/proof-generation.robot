*** Settings ***
Library             RequestsLibrary
Library             Collections
Library             ../resources/web3_keywords.py
Resource            ../resources/chain_config.robot

*** Variables ***
${BASE_URL}         http://localhost:8080
${VALID_API_KEY}    test-valid-api-key
${PARTY_A}          0x70997970C51812dc3A010C7d01b50e0d17dc79C8
${PARTY_B}          0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC

*** Test Cases ***
Generate Age Proof For Valid Consent
    [Documentation]    PROOF - Generate ZK age proof for a valid consent
    ${consent_id}=    Register Test Consent    ${PARTY_A}    ${PARTY_B}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent/${consent_id}/proof
    ...    json={"proofType":"age","publicInputs":[${consent_id}]}
    ...    headers=${headers}
    ...    expected_status=200
    Dictionary Should Contain Key    ${response.json()}    proof    msg=Response must contain proof field
    Dictionary Should Contain Key    ${response.json()}    publicInputs    msg=Response must contain publicInputs
    Should Not Be Empty    ${response.json()['proof']}    msg=Proof must not be empty
    [Teardown]    Cleanup Test Consent    ${consent_id}

Generate Party Inclusion Proof
    [Documentation]    PROOF - Generate ZK proof that a party is included in consent
    ${consent_id}=    Register Test Consent    ${PARTY_A}    ${PARTY_B}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent/${consent_id}/proof
    ...    json={"proofType":"party","publicInputs":[${consent_id},"${PARTY_A}"]}
    ...    headers=${headers}
    ...    expected_status=200
    Dictionary Should Contain Key    ${response.json()}    proof    msg=Response must contain proof
    Should Not Be Empty    ${response.json()['proof']}    msg=Party inclusion proof must not be empty
    [Teardown]    Cleanup Test Consent    ${consent_id}

Generate Scope Inclusion Proof
    [Documentation]    PROOF - Generate ZK proof that a scope is included in consent
    ${consent_id}=    Register Test Consent    ${PARTY_A}    ${PARTY_B}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent/${consent_id}/proof
    ...    json={"proofType":"scope","publicInputs":[${consent_id},"photo"]}
    ...    headers=${headers}
    ...    expected_status=200
    Dictionary Should Contain Key    ${response.json()}    proof    msg=Response must contain proof
    Should Not Be Empty    ${response.json()['proof']}    msg=Scope inclusion proof must not be empty
    [Teardown]    Cleanup Test Consent    ${consent_id}

Verify Proof Via Api
    [Documentation]    PROOF - Verify a generated proof via the verification endpoint
    ${consent_id}=    Register Test Consent    ${PARTY_A}    ${PARTY_B}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${proof_response}=    POST    ${BASE_URL}/api/v1/consent/${consent_id}/proof
    ...    json={"proofType":"age","publicInputs":[${consent_id}]}
    ...    headers=${headers}
    ...    expected_status=200
    ${proof}=    Set Variable    ${proof_response.json()['proof']}
    ${public_inputs}=    Set Variable    ${proof_response.json()['publicInputs']}
    ${verify_response}=    POST    ${BASE_URL}/api/v1/consent/${consent_id}/proof/verify
    ...    json={"proofType":"age","proof":"${proof}","publicInputs":${public_inputs}}
    ...    headers=${headers}
    ...    expected_status=200
    Should Be True    ${verify_response.json()['valid']}    msg=Valid proof must be verified successfully
    [Teardown]    Cleanup Test Consent    ${consent_id}

Proof Reuse Is Prevented
    [Documentation]    PROOF - Same proof cannot be used twice (replay protection)
    ${consent_id}=    Register Test Consent    ${PARTY_A}    ${PARTY_B}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${proof_response}=    POST    ${BASE_URL}/api/v1/consent/${consent_id}/proof
    ...    json={"proofType":"age","publicInputs":[${consent_id}]}
    ...    headers=${headers}
    ...    expected_status=200
    ${proof}=    Set Variable    ${proof_response.json()['proof']}
    ${public_inputs}=    Set Variable    ${proof_response.json()['publicInputs']}
    POST    ${BASE_URL}/api/v1/consent/${consent_id}/proof/verify
    ...    json={"proofType":"age","proof":"${proof}","publicInputs":${public_inputs}}
    ...    headers=${headers}
    ...    expected_status=200
    ${replay_response}=    POST    ${BASE_URL}/api/v1/consent/${consent_id}/proof/verify
    ...    json={"proofType":"age","proof":"${proof}","publicInputs":${public_inputs}}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${replay_response}
    Should Contain    ${replay_response.text}    used    msg=Reused proof must be detected and rejected
    [Teardown]    Cleanup Test Consent    ${consent_id}

Generate Proof For Invalid Consent Id Rejected
    [Documentation]    PROOF - Proof generation for nonexistent consent ID must fail
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent/0x0000000000000000000000000000000000000000000000000000000000000000/proof
    ...    json={"proofType":"age","publicInputs":["0x0000"]}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    404    ${response}

Proof Types Must Be Valid
    [Documentation]    PROOF - Invalid proof type string must be rejected
    ${consent_id}=    Register Test Consent    ${PARTY_A}    ${PARTY_B}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent/${consent_id}/proof
    ...    json={"proofType":"invalid_type","publicInputs":[]}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
    Should Contain    ${response.text}    type    msg=Invalid proof type must be rejected
    [Teardown]    Cleanup Test Consent    ${consent_id}

Revoked Consent Proof Generation Rejected
    [Documentation]    PROOF - Generating proof for revoked consent must be rejected
    ${consent_id}=    Register Test Consent    ${PARTY_A}    ${PARTY_B}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    POST    ${BASE_URL}/api/v1/consent/${consent_id}/revoke    headers=${headers}    expected_status=200
    ${response}=    POST    ${BASE_URL}/api/v1/consent/${consent_id}/proof
    ...    json={"proofType":"age","publicInputs":[${consent_id}]}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
    Should Contain    ${response.text}    revoked    msg=Proof for revoked consent must be rejected
    [Teardown]    Cleanup Test Consent    ${consent_id}

Verify Proof With Tampered Public Inputs
    [Documentation]    PROOF - Verification with tampered public inputs must fail
    ${consent_id}=    Register Test Consent    ${PARTY_A}    ${PARTY_B}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${proof_response}=    POST    ${BASE_URL}/api/v1/consent/${consent_id}/proof
    ...    json={"proofType":"age","publicInputs":[${consent_id}]}
    ...    headers=${headers}
    ...    expected_status=200
    ${proof}=    Set Variable    ${proof_response.json()['proof']}
    ${tampered_inputs}=    Create List    0x0000000000000000000000000000000000000000000000000000000000000000
    ${verify_response}=    POST    ${BASE_URL}/api/v1/consent/${consent_id}/proof/verify
    ...    json={"proofType":"age","proof":"${proof}","publicInputs":${tampered_inputs}}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${verify_response}
    Should Contain    ${verify_response.text}    invalid    msg=Tampered public inputs must cause verification failure
    [Teardown]    Cleanup Test Consent    ${consent_id}
