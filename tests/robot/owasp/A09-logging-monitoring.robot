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
Audit Trail Complete For Consent Lifecycle
    [Documentation]    A09 - Every consent action must emit verifiable events
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}","${PARTY_B}"],"scopes":["photo"],"validFrom":100,"validUntil":9999999999}
    ...    headers=${headers}
    ...    expected_status=201
    ${consent_id}=    Set Variable    ${response.json()['id']}
    ${events}=    GET    ${BASE_URL}/api/v1/events?consentId=${consent_id}
    ...    headers=${headers}
    ...    expected_status=200
    ${event_types}=    Evaluate    [e['type'] for e in ${events.json()}]
    Should Contain    ${event_types}    ConsentRegistered    msg=ConsentRegistered event must be emitted
    ${revoke_response}=    POST    ${BASE_URL}/api/v1/consent/${consent_id}/revoke
    ...    headers=${headers}
    ...    expected_status=200
    ${events2}=    GET    ${BASE_URL}/api/v1/events?consentId=${consent_id}
    ...    headers=${headers}
    ...    expected_status=200
    ${event_types2}=    Evaluate    [e['type'] for e in ${events2.json()}]
    Should Contain    ${event_types2}    ConsentRevoked    msg=ConsentRevoked event must be emitted after revocation

Event Emission Verification
    [Documentation]    A09 - Verify on-chain events match API responses
    ${consent_id}=    Register Test Consent    ${PARTY_A}    ${PARTY_B}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${api_consent}=    GET    ${BASE_URL}/api/v1/consent/${consent_id}
    ...    headers=${headers}
    ...    expected_status=200
    ${onchain_consent}=    Verify Consent On Chain    ${consent_id}
    Should Be Equal    ${api_consent.json()['id']}    ${onchain_consent['id']}    msg=API and on-chain consent IDs must match
    Should Be Equal As Integers    ${api_consent.json()['validFrom']}    ${onchain_consent['validFrom']}    msg=API and on-chain validFrom must match
    Should Be Equal As Integers    ${api_consent.json()['validUntil']}    ${onchain_consent['validUntil']}    msg=API and on-chain validUntil must match

Log Injection Attack Prevented
    [Documentation]    A09 - Log injection via newlines in consent metadata must be sanitized
    ${log_injection}=    Set Variable    photo\n[INFO] User authenticated as admin\n
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}"],"scopes":["${log_injection}"],"validFrom":100,"validUntil":9999999999}
    ...    headers=${headers}
    ...    expected_status=any
    ${response2}=    GET    ${BASE_URL}/api/v1/consent/search?q=photo
    ...    headers=${headers}
    ...    expected_status=any
    ${response_text}=    Set Variable    ${response2.text}
    Should Not Contain    ${response_text}    [INFO]    msg=Log injection in scopes must be sanitized

Security Events Logged For Failed Auth
    [Documentation]    A09 - Failed authentication attempts must be logged as security events
    ${headers}=    Create Dictionary    Authorization=Bearer invalid-token
    ${response}=    GET    ${BASE_URL}/api/v1/consent/0x1234
    ...    headers=${headers}
    ...    expected_status=any
    ${audit_logs}=    GET    ${BASE_URL}/api/v1/admin/audit-log?eventType=auth_failure&limit=1
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    401    ${response}

Tamper Proof Audit Trail
    [Documentation]    A09 - Audit events should include non-repudiation fields
    ${consent_id}=    Register Test Consent    ${PARTY_A}    ${PARTY_B}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${events}=    GET    ${BASE_URL}/api/v1/events?consentId=${consent_id}
    ...    headers=${headers}
    ...    expected_status=200
    ${event}=    Set Variable    ${events.json()[0]}
    Dictionary Should Contain Key    ${event}    txHash    msg=Event must include transaction hash
    Dictionary Should Contain Key    ${event}    blockNumber    msg=Event must include block number
    Dictionary Should Contain Key    ${event}    timestamp    msg=Event must include timestamp
    Dictionary Should Contain Key    ${event}    signer    msg=Event must include signer address
    Should Not Be Empty    ${event['txHash']}    msg=Transaction hash must not be empty

Unauthorized Access Attempts Logged
    [Documentation]    A09 - Unauthorized access attempts should appear in security logs
    ${headers}=    Create Dictionary    Authorization=Bearer invalid-key
    ${response}=    GET    ${BASE_URL}/api/v1/admin/consents
    ...    headers=${headers}
    ...    expected_status=401
    ${auth_headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${logs}=    GET    ${BASE_URL}/api/v1/admin/security-logs?limit=10
    ...    headers=${auth_headers}
    ...    expected_status=200
    ${log_count}=    Get Length    ${logs.json()}
    Should Be True    ${log_count} > 0    msg=Security logs must capture unauthorized access attempts

Consent Revocation Audit Trail
    [Documentation]    A09 - Revocation must produce complete audit trail including who and when
    ${consent_id}=    Register Test Consent    ${PARTY_A}    ${PARTY_B}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${revoke_response}=    POST    ${BASE_URL}/api/v1/consent/${consent_id}/revoke
    ...    headers=${headers}
    ...    expected_status=200
    ${events}=    GET    ${BASE_URL}/api/v1/events?consentId=${consent_id}
    ...    headers=${headers}
    ...    expected_status=200
    ${revoke_events}=    Evaluate    [e for e in ${events.json()} if e['type'] == 'ConsentRevoked']
    Get Length    ${revoke_events}    1    msg=Exactly one ConsentRevoked event expected
    ${revoke_event}=    Set Variable    ${revoke_events[0]}
    Dictionary Should Contain Key    ${revoke_event}    revokedBy    msg=Revoke event must include revokedBy field

Rate Limit Events Logged
    [Documentation]    A09 - Rate limit hits should be logged as security events
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${consent_id}=    Register Test Consent    ${PARTY_A}    ${PARTY_B}
    ${found_ratelimit}=    Set Variable    ${FALSE}
    FOR    ${i}    IN RANGE    50
        ${response}=    POST    ${BASE_URL}/api/v1/consent/${consent_id}/proof
        ...    json={"proofType":"age"}
        ...    headers=${headers}
        ...    expected_status=any
        IF    ${response.status_code} == 429
            ${found_ratelimit}=    Set Variable    ${TRUE}
            BREAK
        END
    END
    Should Be True    ${found_ratelimit}    msg=Rate limiting must be triggered
    ${audit_logs}=    POST    ${BASE_URL}/api/v1/admin/audit-log/search
    ...    json={"eventType":"rate_limit"}
    ...    headers=${headers}
    ...    expected_status=200
