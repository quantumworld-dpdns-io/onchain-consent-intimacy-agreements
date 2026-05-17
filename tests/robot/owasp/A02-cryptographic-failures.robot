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
Invalid Signature Is Rejected
    [Documentation]    A02 - Test that invalid signatures are rejected during consent registration
    ${bad_sig}=    Generate Invalid Signature
    ${parties}=    Create List    ${PARTY_A}    ${PARTY_B}
    ${scopes}=    Create List    photo
    ${consent_data}=    Create Dictionary
    ...    parties=${parties}
    ...    scopes=${scopes}
    ...    validFrom=100
    ...    validUntil=9999999999
    ...    encryptedMetadataUri=
    ${signatures}=    Create List    ${bad_sig}    ${bad_sig}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"consent":${consent_data},"signatures":${signatures}}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
    Should Contain    ${response.text}    invalid signature    msg=Should reject invalid signature

Signature Malleability Detected
    [Documentation]    A02 - Modified signatures (s malleability) should be rejected
    ${original_sig}=    Sign Consent Message    {"parties":["${PARTY_A}","${PARTY_B}"],"scopes":["photo"],"validFrom":100,"validUntil":9999999999,"encryptedMetadataUri":""}    ${TEST_PRIVKEY}
    ${tampered_sig}=    Tamper Signature    ${original_sig}
    ${parties}=    Create List    ${PARTY_A}    ${PARTY_B}
    ${scopes}=    Create List    photo
    ${consent_data}=    Create Dictionary
    ...    parties=${parties}
    ...    scopes=${scopes}
    ...    validFrom=100
    ...    validUntil=9999999999
    ...    encryptedMetadataUri=
    ${signatures}=    Create List    ${tampered_sig}    ${original_sig}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"consent":${consent_data},"signatures":${signatures}}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
    Should Contain    ${response.text}    invalid signature    msg=Malleable signatures must be rejected

Consent Hash Cannot Be Tampered With
    [Documentation]    A02 - Tampered consent data should produce different hash
    ${parties}=    Create List    ${PARTY_A}    ${PARTY_B}
    ${scopes}=    Create List    photo
    ${valid_until}=    Evaluate    9999999999
    ${original_hash}=    Generate Consent Hash    ${parties}    ${scopes}    ${valid_until}
    ${tampered_parties}=    Create List    ${PARTY_A}    0xdead000000000000000000000000000000000000
    ${tampered_hash}=    Generate Consent Hash    ${tampered_parties}    ${scopes}    ${valid_until}
    Should Not Be Equal    ${original_hash}    ${tampered_hash}    msg=Different consent data must produce different hashes
    ${consent_id}=    Register Test Consent    ${PARTY_A}    ${PARTY_B}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${tampered_body}=    Create Dictionary
    ...    id=${consent_id}
    ...    parties=${tampered_parties}
    ...    scopes=${scopes}
    ${response}=    POST    ${BASE_URL}/api/v1/consent/verify
    ...    json=${tampered_body}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}

Response Headers Enforce Encryption
    [Documentation]    A02 - API responses should include security-related headers
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    GET    ${BASE_URL}/api/v1/health
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    200    ${response}
    Dictionary Should Contain Key    ${response.headers}    Strict-Transport-Security
    Dictionary Should Contain Key    ${response.headers}    X-Content-Type-Options
    Dictionary Should Contain Key    ${response.headers}    X-Frame-Options

Weak Signature Length Rejected
    [Documentation]    A02 - Signatures with incorrect length (not 65 bytes) should be rejected
    ${short_sig}=    Set Variable    0x${EMPTY}
    ${parties}=    Create List    ${PARTY_A}
    ${scopes}=    Create List    photo
    ${consent_data}=    Create Dictionary
    ...    parties=${parties}
    ...    scopes=${scopes}
    ...    validFrom=100
    ...    validUntil=9999999999
    ...    encryptedMetadataUri=
    ${signatures}=    Create List    ${short_sig}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"consent":${consent_data},"signatures":${signatures}}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}

Private Key Not Leaked In Error Messages
    [Documentation]    A02 - Error responses must not expose private keys or secrets
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":[],"scopes":[]}
    ...    headers=${headers}
    ...    expected_status=any
    Should Not Contain    ${response.text}    0x    msg=Error should not leak hex values
    Should Not Contain    ${response.text}    private_key    msg=Error should not leak private key
    Should Not Contain    ${response.text}    privatekey    msg=Error should not leak private key
    Should Not Contain    ${response.text}    secret    msg=Error should not leak secrets

EIP-712 Domain Binding Enforced
    [Documentation]    A02 - Signature from wrong chain/domain should be rejected
    ${sig}=    Sign Consent Message With Domain    {"parties":["${PARTY_A}"],"scopes":["photo"],"validFrom":100,"validUntil":9999999999,"encryptedMetadataUri":""}    ${TEST_PRIVKEY}    chainId=99999
    ${parties}=    Create List    ${PARTY_A}
    ${scopes}=    Create List    photo
    ${consent_data}=    Create Dictionary
    ...    parties=${parties}
    ...    scopes=${scopes}
    ...    validFrom=100
    ...    validUntil=9999999999
    ...    encryptedMetadataUri=
    ${signatures}=    Create List    ${sig}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"consent":${consent_data},"signatures":${signatures}}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
