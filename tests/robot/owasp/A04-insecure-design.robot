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

*** Test Cases ***
Timestamp Front Running Prevented
    [Documentation]    A04 - Consent with manipulated timestamps (front-running) should be rejected
    ${past_valid_from}=    Evaluate    int(time.time()) - 86400    time
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}","${PARTY_B}"],"scopes":["photo"],"validFrom":${past_valid_from},"validUntil":9999999999}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
    Should Contain    ${response.text}    past    msg=Past timestamps should be rejected

Consent Expiration Defaults Enforced
    [Documentation]    A04 - Consent without explicit expiration should use safe defaults
    ${now}=    Evaluate    int(time.time())    time
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}","${PARTY_B}"],"scopes":["photo"]}
    ...    headers=${headers}
    ...    expected_status=201
    ${consent_id}=    Set Variable    ${response.json()['id']}
    ${get_response}=    GET    ${BASE_URL}/api/v1/consent/${consent_id}
    ...    headers=${headers}
    ...    expected_status=200
    ${valid_until}=    Set Variable    ${get_response.json()['validUntil']}
    ${max_validity}=    Evaluate    365 * 86400    # 1 year max default
    ${duration}=    Evaluate    ${valid_until} - ${now}
    Should Be True    ${duration} <= ${max_validity}    msg=Consent duration must not exceed safe default maximum

Unlimited Consent Duration Rejected
    [Documentation]    A04 - Excessively long consent durations should be rejected
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}","${PARTY_B}"],"scopes":["photo"],"validFrom":100,"validUntil":999999999999999}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
    Should Contain    ${response.text}    duration    msg=Unlimited duration should be rejected

Insufficient Scope Validation
    [Documentation]    A04 - Unknown or empty scopes should be rejected
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}"],"scopes":[],"validFrom":100,"validUntil":9999999999}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
    Should Contain    ${response.text}    scope    msg=Empty scopes must be rejected
    ${response2}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}"],"scopes":["invalid_scope_xyz"],"validFrom":100,"validUntil":9999999999}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response2}
    Should Contain    ${response2.text}    scope    msg=Unregistered scopes must be rejected

Missing Rate Limits On Proof Generation
    [Documentation]    A04 - Proof generation endpoint should have rate limiting
    ${consent_id}=    Register Test Consent    ${PARTY_A}    ${PARTY_B}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${too_many}=    Set Variable    ${FALSE}
    FOR    ${i}    IN RANGE    100
        ${response}=    POST    ${BASE_URL}/api/v1/consent/${consent_id}/proof
        ...    json={"proofType":"age"}
        ...    headers=${headers}
        ...    expected_status=any
        ${status}=    Set Variable    ${response.status_code}
        IF    ${status} == 429
            ${too_many}=    Set Variable    ${TRUE}
            BREAK
        END
    END
    Should Be True    ${too_many}    msg=Rate limiting must be enforced on proof generation endpoint

Duplicate Party Registration Rejected
    [Documentation]    A04 - Same party listed multiple times should be rejected
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}","${PARTY_A}","${PARTY_B}"],"scopes":["photo"],"validFrom":100,"validUntil":9999999999}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
    Should Contain    ${response.text}    duplicate    msg=Duplicate parties must be rejected

Empty Party List Rejected
    [Documentation]    A04 - Consent with zero parties should be rejected
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":[],"scopes":["photo"],"validFrom":100,"validUntil":9999999999}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}

ValidFrom After ValidUntil Rejected
    [Documentation]    A04 - Consent with validFrom after validUntil should be rejected
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}","${PARTY_B}"],"scopes":["photo"],"validFrom":9999999999,"validUntil":100}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
    Should Contain    ${response.text}    valid    msg=Invalid time range must be rejected

Merkle Root Validation For Batch Consents
    [Documentation]    A04 - Batch consent without proof of individual party agreement
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent/batch
    ...    json={"parties":["${PARTY_A}","${PARTY_B}","${PARTY_A}","${PARTY_B}"],"scopes":["photo"]}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
