*** Settings ***
Library             RequestsLibrary
Library             Collections
Library             ../resources/web3_keywords.py
Resource            ../resources/chain_config.robot

*** Variables ***
${BASE_URL}         http://localhost:8080
${INVALID_API_KEY}  invalid-api-key
${VALID_API_KEY}    test-valid-api-key
${PARTY_A}          0x70997970C51812dc3A010C7d01b50e0d17dc79C8
${PARTY_B}          0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
${NON_PARTY}        0x90F79bf6EB2c4f870365E785982E1f101E93b906

*** Test Cases ***
Unauthorized Cannot Revoke Consent
    [Documentation]    A01 - Unauthorized address cannot revoke another party's consent
    ${signature}=    Sign Consent Message    {"parties":["${PARTY_A}","${PARTY_B}"],"scopes":["photo"],"validFrom":100,"validUntil":200,"encryptedMetadataUri":""}    ${INVALID_API_KEY}
    ${headers}=    Create Dictionary    Authorization=Bearer ${INVALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent/0x1234/revoke
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    401    ${response}
    Should Contain    ${response.text}    unauthorized    msg=Should indicate unauthorized access

Consent Registration Requires Authentication
    [Documentation]    A01 - Test auth enforcement on consent creation endpoint
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}","${PARTY_B}"],"scopes":["photo"]}
    ...    expected_status=any
    Status Should Be    401    ${response}
    Should Contain    ${response.text}    authentication    msg=Should indicate missing auth

Non-Party Cannot Query Consent Details
    [Documentation]    A01 - Only consent parties can access sensitive consent details
    ${consent_id}=    Register Test Consent    ${PARTY_A}    ${PARTY_B}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}    X-Signer-Address=${NON_PARTY}
    ${response}=    GET    ${BASE_URL}/api/v1/consent/${consent_id}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    403    ${response}
    Should Contain    ${response.text}    forbidden    msg=Should indicate forbidden access

Non-Party Cannot Revoke Consent
    [Documentation]    A01 - Only consent parties should be allowed to revoke
    ${consent_id}=    Register Test Consent    ${PARTY_A}    ${PARTY_B}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}    X-Signer-Address=${NON_PARTY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent/${consent_id}/revoke
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    403    ${response}

Unauthorized Access To Admin Endpoints
    [Documentation]    A01 - Admin endpoints should require elevated privileges
    ${headers}=    Create Dictionary    Authorization=Bearer ${INVALID_API_KEY}
    ${response}=    GET    ${BASE_URL}/api/v1/admin/consents
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    401    ${response}

Missing Authorization Header
    [Documentation]    A01 - Requests without any auth header should be rejected
    ${response}=    GET    ${BASE_URL}/api/v1/consent/0x0000000000000000000000000000000000000000000000000000000000000001
    ...    expected_status=any
    Status Should Be    401    ${response}

Non-Party Cannot Update Consent
    [Documentation]    A01 - Only parties should update consent parameters
    ${consent_id}=    Register Test Consent    ${PARTY_A}    ${PARTY_B}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}    X-Signer-Address=${NON_PARTY}
    ${update_body}=    Create Dictionary    validUntil=9999999999    encryptedMetadataUri=https://new-uri.example
    ${response}=    PUT    ${BASE_URL}/api/v1/consent/${consent_id}
    ...    json=${update_body}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    403    ${response}

Blacklisted Address Cannot Interact
    [Documentation]    A01 - Blacklisted addresses should be blocked from any consent action
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}    X-Signer-Address=0x000000000000000000000000000000000000dead
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["0xdead"],"scopes":["photo"]}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    403    ${response}
