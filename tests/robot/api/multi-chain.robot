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
Same Consent Registered On Multiple Chains
    [Documentation]    MULTI - Register same consent on two different chains and verify both
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${now}=    Evaluate    int(time.time())    time
    ${consent_data}=    Create Dictionary
    ...    parties=${PARTY_A},${PARTY_B}
    ...    scopes=photo,video
    ...    validFrom=${now}
    ...    validUntil=${now}+86400
    ...    chainIds=31337,11155111
    ${response}=    POST    ${BASE_URL}/api/v1/consent/multi-chain
    ...    json=${consent_data}
    ...    headers=${headers}
    ...    expected_status=201
    ${results}=    Set Variable    ${response.json()['results']}
    ${chain_count}=    Get Length    ${results}
    Should Be Equal As Integers    ${chain_count}    2    msg=Consent must be registered on 2 chains
    ${chain_0}=    Set Variable    ${results[0]}
    Should Contain    ${chain_0}    consentId    msg=Chain 0 must return a consent ID
    Should Contain    ${chain_0}    chainId    msg=Chain 0 must include chain ID
    ${chain_1}=    Set Variable    ${results[1]}
    Should Contain    ${chain_1}    consentId    msg=Chain 1 must return a consent ID
    Should Contain    ${chain_1}    chainId    msg=Chain 1 must include chain ID

Cross Chain Consent Verification
    [Documentation]    MULTI - Verify a consent registered on one chain from another chain
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${now}=    Evaluate    int(time.time())    time
    ${consent_data}=    Create Dictionary
    ...    parties=${PARTY_A},${PARTY_B}
    ...    scopes=photo
    ...    validFrom=${now}
    ...    validUntil=${now}+86400
    ...    sourceChainId=31337
    ...    targetChainIds=11155111
    ${response}=    POST    ${BASE_URL}/api/v1/consent/cross-chain-verify
    ...    json=${consent_data}
    ...    headers=${headers}
    ...    expected_status=200
    ${cross_results}=    Set Variable    ${response.json()['verifications']}
    Should Not Be Empty    ${cross_results}    msg=Cross-chain verification results must exist
    FOR    ${result}    IN    @{cross_results}
        Should Be True    ${result['verified']}    msg=Consent must be verifiable across chains
    END

Chain Specific Error Handling
    [Documentation]    MULTI - Registering on an unsupported chain should return chain-specific error
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${now}=    Evaluate    int(time.time())    time
    ${response}=    POST    ${BASE_URL}/api/v1/consent/multi-chain
    ...    json={"parties":["${PARTY_A}","${PARTY_B}"],"scopes":["photo"],"validFrom":${now},"validUntil":${now}+86400,"chainIds":[999999]}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
    Should Contain    ${response.text}    unsupported    msg=Unsupported chain must return appropriate error

Consistency Across Chain Registrations
    [Documentation]    MULTI - Same consent data must produce identical consent IDs across chains
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${now}=    Evaluate    int(time.time())    time
    ${consent_data}=    Create Dictionary
    ...    parties=${PARTY_A},${PARTY_B}
    ...    scopes=photo
    ...    validFrom=${now}
    ...    validUntil=${now}+86400
    ...    chainIds=31337,11155111
    ${response}=    POST    ${BASE_URL}/api/v1/consent/multi-chain
    ...    json=${consent_data}
    ...    headers=${headers}
    ...    expected_status=201
    ${chain_0_id}=    Set Variable    ${response.json()['results'][0]['consentId']}
    ${chain_1_id}=    Set Variable    ${response.json()['results'][1]['consentId']}
    Should Be Equal    ${chain_0_id}    ${chain_1_id}    msg=Consent IDs must be identical across chains for same data

Cross Chain Revocation
    [Documentation]    MULTI - Revoking consent on one chain should invalidate it on all
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${now}=    Evaluate    int(time.time())    time
    ${consent_data}=    Create Dictionary
    ...    parties=${PARTY_A},${PARTY_B}
    ...    scopes=photo
    ...    validFrom=${now}
    ...    validUntil=${now}+86400
    ...    chainIds=31337,11155111
    ${response}=    POST    ${BASE_URL}/api/v1/consent/multi-chain
    ...    json=${consent_data}
    ...    headers=${headers}
    ...    expected_status=201
    ${consent_id}=    Set Variable    ${response.json()['results'][0]['consentId']}
    ${revoke_response}=    POST    ${BASE_URL}/api/v1/consent/${consent_id}/revoke?chainId=31337
    ...    headers=${headers}
    ...    expected_status=200
    ${verify_response}=    GET    ${BASE_URL}/api/v1/consent/${consent_id}/valid?chainId=11155111
    ...    headers=${headers}
    ...    expected_status=200
    Should Not Be True    ${verify_response.json()['valid']}    msg=Cross-chain revoked consent must be invalid everywhere

Partial Chain Failure Handling
    [Documentation]    MULTI - One chain failure should not block success on other chains
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${now}=    Evaluate    int(time.time())    time
    ${response}=    POST    ${BASE_URL}/api/v1/consent/multi-chain
    ...    json={"parties":["${PARTY_A}","${PARTY_B}"],"scopes":["photo"],"validFrom":${now},"validUntil":${now}+86400,"chainIds":[31337,999999]}
    ...    headers=${headers}
    ...    expected_status=207
    ${results}=    Set Variable    ${response.json()['results']}
    ${success_count}=    Evaluate    sum(1 for r in ${results} if r['status'] == 'success')
    ${fail_count}=    Evaluate    sum(1 for r in ${results} if r['status'] == 'failed')
    Should Be Equal As Integers    ${success_count}    1    msg=At least one chain should succeed
    Should Be Equal As Integers    ${fail_count}    1    msg=Exactly one chain should fail

Chain Specific Proof Generation
    [Documentation]    MULTI - ZK proof generated for consent on one chain is verifiable on another
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${now}=    Evaluate    int(time.time())    time
    ${consent_data}=    Create Dictionary
    ...    parties=${PARTY_A},${PARTY_B}
    ...    scopes=photo
    ...    validFrom=${now}
    ...    validUntil=${now}+86400
    ...    chainIds=31337,11155111
    ${response}=    POST    ${BASE_URL}/api/v1/consent/multi-chain
    ...    json=${consent_data}
    ...    headers=${headers}
    ...    expected_status=201
    ${consent_id}=    Set Variable    ${response.json()['results'][0]['consentId']}
    ${proof_response}=    POST    ${BASE_URL}/api/v1/consent/${consent_id}/proof
    ...    json={"proofType":"age","publicInputs":[${consent_id}],"sourceChainId":31337}
    ...    headers=${headers}
    ...    expected_status=200
    ${proof}=    Set Variable    ${proof_response.json()['proof']}
    ${verify_response}=    POST    ${BASE_URL}/api/v1/consent/${consent_id}/proof/verify
    ...    json={"proofType":"age","proof":"${proof}","publicInputs":[${consent_id}],"targetChainId":11155111}
    ...    headers=${headers}
    ...    expected_status=200
    Should Be True    ${verify_response.json()['valid']}    msg=Proof generated on chain A must verify on chain B
