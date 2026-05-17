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
Cross Chain Callback Injection Rejected
    [Documentation]    A10 - Malicious cross-chain callback URLs must be rejected
    ${malicious_callback}=    Set Variable    http://169.254.169.254/latest/meta-data/
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}"],"scopes":["photo"],"callbackUrl":"${malicious_callback}"}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
    Should Contain    ${response.text}    callback    msg=SSRF callback to metadata service must be rejected

Malicious Delegatecall Target Rejected
    [Documentation]    A10 - Delegatecall to untrusted contract addresses should be blocked
    ${malicious_target}=    Set Variable    0x0000000000000000000000000000000000000000
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent/delegate
    ...    json={"target":"${malicious_target}","data":"0xDEADBEEF"}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
    Should Contain    ${response.text}    invalid    msg=Delegatecall to zero address must be rejected

Unauthorized Rpc Endpoint Access
    [Documentation]    A10 - API should not expose internal RPC endpoints
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    GET    ${BASE_URL}/api/v1/rpc
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    403    ${response}
    ${response2}=    GET    ${BASE_URL}/api/v1/rpc/eth/blockNumber
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    403    ${response2}

Internal Network Scanning Via Url Parameters Blocked
    [Documentation]    A10 - SSRF attempts to internal network via URL params must be blocked
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}"],"scopes":["photo"],"metadataUri":"http://10.0.0.1/admin"}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
    Should Contain    ${response.text}    metadata    msg=Internal IP in metadata must be rejected
    ${response2}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}"],"scopes":["photo"],"metadataUri":"http://192.168.1.1/config"}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response2}
    Should Contain    ${response2.text}    metadata    msg=Private IP in metadata must be rejected

Dns Rebinding Attack Protection
    [Documentation]    A10 - DNS rebinding via metadata URI must be prevented
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}"],"scopes":["photo"],"metadataUri":"http://169.254.169.254.xip.io/latest"}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
    Should Contain    ${response.text}    metadata    msg=DNS rebinding attempt must be rejected

Callback To Loopback Interface Blocked
    [Documentation]    A10 - Callback to localhost/loopback must be blocked
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}"],"scopes":["photo"],"callbackUrl":"http://127.0.0.1:8545"}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
    Should Contain    ${response.text}    callback    msg=Loopback callback must be rejected
    ${response2}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}"],"scopes":["photo"],"callbackUrl":"http://localhost:8545"}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response2}
    Should Contain    ${response2.text}    callback    msg=Localhost callback must be rejected

File Uri Scheme Blocked
    [Documentation]    A10 - File:// URI scheme should be blocked in metadata
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}"],"scopes":["photo"],"metadataUri":"file:///etc/passwd"}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
    Should Contain    ${response.text}    scheme    msg=File URI scheme must be rejected

Data Uri Scheme With Excessive Size Blocked
    [Documentation]    A10 - Data URI with oversized payload should be rejected
    ${large_data_uri}=    Set Variable    data:text/plain;base64,${LARGE_BASE64}
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}"],"scopes":["photo"],"metadataUri":"${large_data_uri}"}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}

Webhook Url To Untrusted Domain Rejected
    [Documentation]    A10 - Webhook URLs to untrusted external domains should be validated
    ${headers}=    Create Dictionary    Authorization=Bearer ${VALID_API_KEY}
    ${response}=    POST    ${BASE_URL}/api/v1/consent
    ...    json={"parties":["${PARTY_A}"],"scopes":["photo"],"webhookUrl":"http://evil.com/hook"}
    ...    headers=${headers}
    ...    expected_status=any
    Status Should Be    400    ${response}
    Should Contain    ${response.text}    domain    msg=Untrusted webhook domain must be rejected
