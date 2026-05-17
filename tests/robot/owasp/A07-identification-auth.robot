*** Settings ***
Library             RequestsLibrary
Library             Collections
Library             ../resources/web3_keywords.py
Library             ../resources/test_data.py
Resource            ../resources/chain_config.robot

*** Variables ***
${BASE_URL}         http://localhost:8080
${VALID_API_KEY}    test-valid-api-key
${PARTY_A}          0x70997970C51812dc3A010C7d01b50e0d17dc79C8
${PARTY_B}          0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
${TEST_PRIVKEY}     0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d

*** Test Cases ***
Signature Replay Across Chains Rejected
    [Documentation]    A07 - EIP-155 signature from one chain should not work on another chain
    ${consent_data}=    Create Dictionary
    ...    parties=${PARTY_A}
    ...    scopes=photo
    ...    validFrom=100
    ...    validUntil=9999999999
    ...    encryptedMetadataUri=
    ${sig_chain_1}=    Sign Consent Message With Chain    ${consent_data}    ${TEST_PRIVKEY}    31337
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"consent":${consent_data},"signatures":[${sig_chain_1}],"chainId":1}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
    Should Contain    ${response.text}    chain    msg=Cross-chain signature replay must be rejected

Nonce Reuse Detection
    [Documentation]    A07 - Reusing the same nonce should be detected and rejected
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${nonce}=    Set Variable    42
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}"],"scopes":["photo"],"nonce":${nonce}}
    ...    headers=${headers}
    ...    expected_status=201
    ${response2}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}"],"scopes":["photo"],"nonce":${nonce}}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    409    ${response2}
    Should Contain    ${response2.text}    nonce    msg=Nonce reuse must be detected

Blind Signing Attack Prevented
    [Documentation]    A07 - Users should not be able to sign opaque data blobs without consent decoding
    ${opaque_hash}=    Set Variable    0x0000000000000000000000000000000000000000000000000000000000000001
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/signature/verify
    ...    json={"hash":${opaque_hash},"signature":"0x1234"}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
    Should Contain    ${response.text}    decoded    msg=Opaque blind signing must be rejected

Jwt Token Manipulation Detected
    [Documentation]    A07 - Tampered JWT tokens should be rejected
    ${tampered_token}=    Set Variable    eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhZG1pbiIsInJvbGUiOiJhZG1pbiJ9.tampered
    ${headers}=    Create Dictionary    Authorization=Bearer ${tampered_token}
    ${response}=    GET    ${BASE_URL}/api/v1/consent/0x1234
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    401    ${response}
    Should Contain    ${response.text}    token    msg=Tampered JWT must be rejected
    ${expired_token}=    Set Variable    eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyIiwiZXhwIjoxNTAwMDAwMDAwfQ.dGVzdA
    ${headers2}=    Create Dictionary    Authorization=Bearer ${expired_token}
    ${response2}=    GET    ${BASE_URL}/api/v1/consent/0x1234
    ...    headers=${headers2}
    ...    expected_status=any
    Status Should Be    401    ${response2}

Expired Signature Rejection
    [Documentation]    A07 - Signatures with expired timestamps should not be accepted
    ${past_timestamp}=    Evaluate    int(time.time()) - 7200    time
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}"],"scopes":["photo"],"timestamp":${past_timestamp}}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
    Should Contain    ${response.text}    expired    msg=Expired timestamps must be rejected

Future Signature Timestamp Rejection
    [Documentation]    A07 - Signatures with future timestamps should be rejected
    ${future_timestamp}=    Evaluate    int(time.time()) + 86400    time
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}"],"scopes":["photo"],"timestamp":${future_timestamp}}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
    Should Contain    ${response.text}    future    msg=Future timestamps must be rejected

Invalid Eip 155 V Value Rejected
    [Documentation]    A07 - Invalid signature v values should be rejected
    ${bad_v_sig}=    Generate Invalid V Signature
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}"],"scopes":["photo"],"signature":"${bad_v_sig}"}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}

Signature With Wrong Signer Rejected
    [Documentation]    A07 - Signature from non-party address must be rejected
    ${wrong_signer_sig}=    Sign Consent Message    {"parties":["${PARTY_A}"],"scopes":["photo"],"validFrom":100,"validUntil":9999999999,"encryptedMetadataUri":""}    0x0000000000000000000000000000000000000000000000000000000000000001
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}"],"scopes":["photo"],"signature":"${wrong_signer_sig}"}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}

Replay Attack Within Same Chain Prevented
    [Documentation]    A07 - Same consent data used twice should be detected as duplicate
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}","${PARTY_B}"],"scopes":["photo"],"validFrom":100,"validUntil":9999999999}
    ...    headers=${headers}
    ...    expected_status=201
    ${consent_id}=    Set Variable    ${response.json()['id']}
    ${response2}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}","${PARTY_B}"],"scopes":["photo"],"validFrom":100,"validUntil":9999999999}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    409    ${response2}
    Should Contain    ${response2.text}    exists    msg=Duplicate consent must be detected
