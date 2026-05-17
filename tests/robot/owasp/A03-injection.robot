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
Reentrancy Via Callback Parameters Rejected
    [Documentation]    A03 - Solidity reentrancy attempt via malicious callback parameters
    ${malicious_data}=    Create Dictionary
    ...    callback=0xmalicious
    ...    data=0xDEADBEEF
    ...    gas=9999999999999999
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}"],"scopes":["photo"],"callback":${malicious_data}}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
    Should Contain    ${response.text}    invalid    msg=Reentrancy callback must be rejected

SQL Injection In Consent Search Rejected
    [Documentation]    A03 - SQL injection attempts in search parameters should be sanitized
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    GET    ${BASE_URL}/api/v1/consent/search?q=1%27%20OR%20%271%27%3D%271
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
    Should Contain    ${response.text}    invalid    msg=SQL injection must be rejected
    ${response2}=    GET    ${BASE_URL}/api/v1/consent/search?q=%3B%20DROP%20TABLE%20consents--
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response2}
    Should Contain    ${response2.text}    invalid    msg=SQL injection DROP TABLE must be rejected

NoSql Injection Via Json Body Rejected
    [Documentation]    A03 - NoSQL injection via JSON body operators should be sanitized
    ${injection_body}=    Create Dictionary
    ...    parties=${PARTY_A}
    ...    scopes={"$gt":""}
    ...    validFrom={"$ne":1}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json=${injection_body}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
    Should Contain    ${response.text}    invalid    msg=NoSQL injection $gt operator must be rejected

XSS In Consent Metadata Rejected
    [Documentation]    A03 - XSS attempts in consent metadata fields should be sanitized
    ${xss_payload}=    Set Variable    <script>alert('xss')</script>
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}"],"scopes":["photo"],"encryptedMetadataUri":"${xss_payload}"}
    ...    headers=${headers}
    ...    expected_status=any
    Should Not Contain    ${response.text}    <script>    msg=XSS payload must be sanitized in response

Json Injection In Consent Fields
    [Documentation]    A03 - Attempt JSON prototype pollution via __proto__
    ${proto_pollution}=    Create Dictionary
    ...    parties={"__proto__":{"admin":true}}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json=${proto_pollution}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}

Header Injection Attempt
    [Documentation]    A03 - CRLF injection in headers should be sanitized
    ${malicious_headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}    X-Forwarded-For=127.0.0.1%0d%0aX-Custom:%20injected
    ${response}=    GET    ${BASE_URL}/api/v1/consent/0x1234
    ...    headers=${malicious_headers}
    ...    expected_status=any
    Status Should Be    400    ${response}

Command Injection In Consent Id
    [Documentation]    A03 - Command injection attempts via consent ID parameter
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    GET    ${BASE_URL}/api/v1/consent/%3B%20rm%20-rf%20%2F
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
    Should Contain    ${response.text}    invalid    msg=Command injection must be rejected

Path Traversal In Metadata Uri
    [Documentation]    A03 - Path traversal in metadata URI should be rejected
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}"],"scopes":["photo"],"encryptedMetadataUri":"../../../etc/passwd"}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}

Malformed Json Body Rejected
    [Documentation]    A03 - Malformed JSON should be rejected with clear error
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    body={parties: [invalid]}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}

Unicode Injection Attempt
    [Documentation]    A03 - Unicode normalization attacks in scope names
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}"],"scopes":["photo\u202E"],"encryptedMetadataUri":""}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
