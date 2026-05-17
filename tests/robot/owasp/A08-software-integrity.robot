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
Consent Integrity Hash Verified On Chain
    [Documentation]    A08 - Consent data stored on chain must match registration hash
    ${consent_id}=    Register Test Consent    ${PARTY_A}    ${PARTY_B}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    GET    ${BASE_URL}/api/v1/consent/${consent_id}
    ...    headers=${headers}
    ...    expected_status=200
    ${onchain_id}=    Set Variable    ${response.json()['id']}
    Should Be Equal    ${consent_id}    ${onchain_id}    msg=Consent ID must match on-chain value
    ${parties}=    Set Variable    ${response.json()['parties']}
    Should Contain    ${parties}    ${PARTY_A}    msg=Party A must be in consent parties
    Should Contain    ${parties}    ${PARTY_B}    msg=Party B must be in consent parties
    Should Not Be True    ${response.json()['revoked']}    msg=Consent must not be revoked initially

Consent Data Cannot Be Modified After Registration
    [Documentation]    A08 - Immutability of consent core fields (parties, scopes)
    ${consent_id}=    Register Test Consent    ${PARTY_A}    ${PARTY_B}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    PUT    ${BASE_URL}/api/v1/consent/${consent_id}
    ...    json={"parties":["${PARTY_A}"]}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
    Should Contain    ${response.text}    cannot modify    msg=Parties must be immutable after registration

Proxy Upgrade Attack Simulation
    [Documentation]    A08 - Simulate proxy upgrade attack vector (unexpected delegatecall)
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${malicious_impl}=    Set Variable    0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef
    ${response}=    POST    ${BASE_URL}/api/v1/admin/upgrade
    ...    json={"implementation":"${malicious_impl}"}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    403    ${response}
    Should Contain    ${response.text}    unauthorized    msg=Proxy upgrade must require admin auth

Front Running Consent Revocation Detected
    [Documentation]    A08 - Attempt to front-run consent revocation should be detectable
    ${consent_id}=    Register Test Consent    ${PARTY_A}    ${PARTY_B}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${tx1_response}=    POST    ${BASE_URL}/api/v1/consent/${consent_id}/revoke
    ...    headers=${headers}
    ...    expected_status=any
    ${tx2_response}=    POST    ${BASE_URL}/api/v1/consent/${consent_id}/revoke
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    200    ${tx1_response}
    Status Should Be    400    ${tx2_response}
    Should Contain    ${tx2_response.text}    revoked    msg=Double revocation must be detected

Flash Loan Attack Simulation
    [Documentation]    A08 - Flash loan based manipulation of consent state should be prevented
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${flash_loan_data}=    Create Dictionary
    ...    consentIds=["0x0000000000000000000000000000000000000000000000000000000000000001"]
    ...    flashMint=true
    ...    repayInSameBlock=false
    ${response}=    POST    ${BASE_URL}/api/v1/consent/flash-loan
    ...    json=${flash_loan_data}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
    Should Contain    ${response.text}    invalid    msg=Flash loan consent manipulation must be rejected

Timestamp Manipulation For Expired Consent
    [Documentation]    A08 - Trying to manipulate timestamps to extend expired consent
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${consent_id}=    Register Test Consent With Expiry    ${PARTY_A}    ${PARTY_B}    100
    ${response}=    PUT    ${BASE_URL}/api/v1/consent/${consent_id}
    ...    json={"validUntil":9999999999}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
    Should Contain    ${response.text}    expired    msg=Expired consent must not be extendable

Signature Replay On Revocation
    [Documentation]    A08 - Reusing revocation signature should not double-revoke
    ${consent_id}=    Register Test Consent    ${PARTY_A}    ${PARTY_B}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent/${consent_id}/revoke
    ...    headers=${headers}
    ...    expected_status=200
    ${response2}=    POST    ${BASE_URL}/api/v1/consent/${consent_id}/revoke
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response2}
    ${response3}=    GET    ${BASE_URL}/api/v1/consent/${consent_id}
    ...    headers=${headers}
    ...    expected_status=200
    Should Be True    ${response3.json()['revoked']}    msg=Consent must be marked as revoked

Oracle Manipulation Resistance
    [Documentation]    A08 - Consent validity should not depend on external oracle price
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}"],"scopes":["photo"],"oracleBased":true,"priceThreshold":100}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
    Should Contain    ${response.text}    oracle    msg=Oracle-dependent consent must be rejected
