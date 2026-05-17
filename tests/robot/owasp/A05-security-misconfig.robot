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
Debug Endpoints Not Exposed
    [Documentation]    A05 - Debug and admin endpoints should not be accessible in production
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    GET    ${BASE_URL}/debug
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    403    ${response}
    ${response2}=    GET    ${BASE_URL}/debug/vars
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    403    ${response2}
    ${response3}=    GET    ${BASE_URL}/debug/pprof/
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    403    ${response3}
    ${response4}=    GET    ${BASE_URL}/api/v1/admin
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    403    ${response4}

Default Credentials Rejected
    [Documentation]    A05 - Default or weak credentials must be rejected
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/auth/login
    ...    json={"username":"admin","password":"admin"}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    401    ${response}
    ${response2}=    POST    ${BASE_URL}/api/v1/auth/login
    ...    json={"username":"admin","password":"password"}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    401    ${response2}
    ${response3}=    POST    ${BASE_URL}/api/v1/auth/login
    ...    json={"username":"admin","password":"123456"}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    401    ${response3}

Verbose Error Messages Do Not Leak Chain Info
    [Documentation]    A05 - Error messages should not leak RPC URLs or internal addresses
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["invalid"],"scopes":[]}
    ...    headers=${headers}
    ...    expected_status=any
    Should Not Contain    ${response.text}    http://    msg=Error must not leak RPC URLs
    Should Not Contain    ${response.text}    rpc_url    msg=Error must not leak RPC config
    Should Not Contain    ${response.text}    localhost    msg=Error must not leak internal hostnames
    Should Not Contain    ${response.text}    8545    msg=Error must not leak port numbers
    Should Not Contain    ${response.text}    contract_address    msg=Error must not leak contract addresses
    Should Not Contain    ${response.text}    private_key    msg=Error must not leak private keys

Cors Headers Properly Configured
    [Documentation]    A05 - CORS headers should be present and restrictive
    ${headers}=    Create Dictionary    Origin=https://malicious-site.com
    ${response}=    OPTIONS    ${BASE_URL}/api/v1/consent
    ...    headers=${headers}
    ...    expected_status=any
    ${cors_origin}=    Get Variable Value    ${response.headers['Access-Control-Allow-Origin']}
    Should Not Be Equal    ${cors_origin}    *    msg=CORS should not allow wildcard origin
    Should Not Contain    ${response.headers}    Access-Control-Allow-Credentials: true    msg=CORS should not allow credentials with wildcard

Http Requests Redirect To Https
    [Documentation]    A05 - HTTP endpoints should redirect or reject non-HTTPS traffic
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    GET    http://localhost:8080/api/v1/health
    ...    headers=${headers}
    ...    expected_status=any
    ${status}=    Set Variable    ${response.status_code}
    IF    ${status} == 200
        ${strict_transport}=    Get Variable Value    ${response.headers['Strict-Transport-Security']}
        Should Not Be Empty    ${strict_transport}    msg=HSTS header must be present on HTTP responses
    ELSE
        Status Should Be    426    ${response}
    END

Sensitive Data In Url Parameters
    [Documentation]    A05 - API keys must not be accepted via URL query parameters
    ${response}=    GET    ${BASE_URL}/api/v1/consent/0x1234?api_key=sk-1234567890abcdef
    ...    expected_status=any
    Status Should Be    401    ${response}

Directory Listing Disabled
    [Documentation]    A05 - Directory listing should be disabled
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    GET    ${BASE_URL}/api/
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    403    ${response}

Stack Traces Hidden In Production
    [Documentation]    A05 - Stack traces must not be exposed in API responses
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={invalid}
    ...    headers=${headers}
    ...    expected_status=any
    Should Not Contain    ${response.text}    File    msg=Stack traces must not be exposed
    Should Not Contain    ${response.text}    .go:    msg=Go file references must not be exposed
    Should Not Contain    ${response.text}    .sol:    msg=Solidity file references must not be exposed
    Should Not Contain    ${response.text}    at\s    msg=Stack trace patterns must not be exposed

Excessive Timeout On Idle Connections
    [Documentation]    A05 - Idle connection timeout should be reasonable
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    GET    ${BASE_URL}/api/v1/health
    ...    headers=${headers}
    ...    expected_status=any
    Dictionary Should Contain Key    ${response.headers}    Keep-Alive
    ${keep_alive}=    Set Variable    ${response.headers['Keep-Alive']}
    Should Not Be Empty    ${keep_alive}    msg=Keep-Alive header should be present
