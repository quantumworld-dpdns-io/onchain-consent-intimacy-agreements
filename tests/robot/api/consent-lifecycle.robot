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
${PARTY_C}          0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65

*** Test Cases ***
Create Consent With Valid Parameters
    [Documentation]    API - Create a basic consent with all required valid parameters
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${now}=    Evaluate    int(time.time())    time
    ${valid_from}=    Evaluate    ${now} + 10
    ${valid_until}=    Evaluate    ${now} + 86400
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}","${PARTY_B}"],"scopes":["photo","video"],"validFrom":${valid_from},"validUntil":${valid_until},"encryptedMetadataUri":"https://example.com/metadata"}
    ...    headers=${headers}
    ...    expected_status=201
    ${consent_id}=    Set Variable    ${response.json()['id']}
    Should Not Be Empty    ${consent_id}    msg=Consent ID must be returned
    Should Be Equal    ${response.json()['parties'][0]}    ${PARTY_A}    msg=First party must match
    Should Be Equal    ${response.json()['parties'][1]}    ${PARTY_B}    msg=Second party must match
    Should Contain    ${response.json()['scopes']}    photo    msg=Scope photo must be included
    Should Contain    ${response.json()['scopes']}    video    msg=Scope video must be included
    [Teardown]    Cleanup Test Consent    ${consent_id}

Verify Consent Is Valid
    [Documentation]    API - Verify a newly created consent is valid
    ${consent_id}=    Register Test Consent    ${PARTY_A}    ${PARTY_B}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    GET    ${BASE_URL}/api/v1/consent/${consent_id}
    ...    headers=${headers}
    ...    expected_status=200
    Should Be Equal    ${response.json()['id']}    ${consent_id}    msg=Consent ID must match
    Should Not Be True    ${response.json()['revoked']}    msg=New consent must not be revoked
    ${valid_response}=    GET    ${BASE_URL}/api/v1/consent/${consent_id}/valid
    ...    headers=${headers}
    ...    expected_status=200
    Should Be True    ${valid_response.json()['valid']}    msg=New consent must be valid
    [Teardown]    Cleanup Test Consent    ${consent_id}

Revoke Consent
    [Documentation]    API - Revoke an existing consent and verify status
    ${consent_id}=    Register Test Consent    ${PARTY_A}    ${PARTY_B}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${revoke_response}=    POST    ${BASE_URL}/api/v1/consent/${consent_id}/revoke
    ...    headers=${headers}
    ...    expected_status=200
    Should Contain    ${revoke_response.text}    revoked    msg=Revoke confirmation must be returned
    [Teardown]    Cleanup Test Consent    ${consent_id}

Verify Consent Is Invalid After Revocation
    [Documentation]    API - Verify consent is marked invalid after successful revocation
    ${consent_id}=    Register Test Consent    ${PARTY_A}    ${PARTY_B}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    POST    ${BASE_URL}/api/v1/consent/${consent_id}/revoke    headers=${headers}    expected_status=200
    ${get_response}=    GET    ${BASE_URL}/api/v1/consent/${consent_id}
    ...    headers=${headers}
    ...    expected_status=200
    Should Be True    ${get_response.json()['revoked']}    msg=Consent must be revoked after revocation
    ${valid_response}=    GET    ${BASE_URL}/api/v1/consent/${consent_id}/valid
    ...    headers=${headers}
    ...    expected_status=200
    Should Not Be True    ${valid_response.json()['valid']}    msg=Revoked consent must not be valid
    [Teardown]    Cleanup Test Consent    ${consent_id}

Create Consent With Multiple Parties
    [Documentation]    API - Create consent involving three or more parties
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${now}=    Evaluate    int(time.time())    time
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}","${PARTY_B}","${PARTY_C}"],"scopes":["photo"],"validFrom":${now},"validUntil":${now}+86400}
    ...    headers=${headers}
    ...    expected_status=201
    ${consent_id}=    Set Variable    ${response.json()['id']}
    ${parties}=    Set Variable    ${response.json()['parties']}
    ${party_count}=    Get Length    ${parties}
    Should Be Equal As Integers    ${party_count}    3    msg=Must have exactly 3 parties
    [Teardown]    Cleanup Test Consent    ${consent_id}

Create Consent With Multiple Scopes
    [Documentation]    API - Create consent with several authorized scopes
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${now}=    Evaluate    int(time.time())    time
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}","${PARTY_B}"],"scopes":["photo","video","audio","metadata","distribution"],"validFrom":${now},"validUntil":${now}+86400}
    ...    headers=${headers}
    ...    expected_status=201
    ${consent_id}=    Set Variable    ${response.json()['id']}
    ${scopes}=    Set Variable    ${response.json()['scopes']}
    ${scope_count}=    Get Length    ${scopes}
    Should Be Equal As Integers    ${scope_count}    5    msg=Must have exactly 5 scopes
    [Teardown]    Cleanup Test Consent    ${consent_id}

Get Consent By Id
    [Documentation]    API - Retrieve a consent by its ID
    ${consent_id}=    Register Test Consent    ${PARTY_A}    ${PARTY_B}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    GET    ${BASE_URL}/api/v1/consent/${consent_id}
    ...    headers=${headers}
    ...    expected_status=200
    Should Be Equal    ${response.json()['id']}    ${consent_id}    msg=Returned consent must match requested ID
    Dictionary Should Contain Key    ${response.json()}    parties    msg=Response must contain parties
    Dictionary Should Contain Key    ${response.json()}    scopes    msg=Response must contain scopes
    Dictionary Should Contain Key    ${response.json()}    validFrom    msg=Response must contain validFrom
    Dictionary Should Contain Key    ${response.json()}    validUntil    msg=Response must contain validUntil
    Dictionary Should Contain Key    ${response.json()}    revoked    msg=Response must contain revoked flag
    [Teardown]    Cleanup Test Consent    ${consent_id}

Get Consent Returns 404 For Nonexistent Id
    [Documentation]    API - Requesting nonexistent consent ID returns 404
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    GET    ${BASE_URL}/api/v1/consent/0x0000000000000000000000000000000000000000000000000000000000000000
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    404    ${response}

List Consents For Party
    [Documentation]    API - Retrieve all consents associated with a party
    ${consent_id}=    Register Test Consent    ${PARTY_A}    ${PARTY_B}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    GET    ${BASE_URL}/api/v1/party/${PARTY_A}/consents
    ...    headers=${headers}
    ...    expected_status=200
    ${consent_ids}=    Set Variable    ${response.json()}
    Should Contain    ${consent_ids}    ${consent_id}    msg=Party's consent list must include created consent
    [Teardown]    Cleanup Test Consent    ${consent_id}
