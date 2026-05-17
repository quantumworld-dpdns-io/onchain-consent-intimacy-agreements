*** Settings ***
Library         ../resources/web3_keywords.py
Resource        ../resources/chain_config.robot
Library         Collections

*** Test Cases ***
Register Consent On Local Chain
    [Documentation]    Register consent via contract interaction
    ${parties}=    Create List    0x1111    0x2222
    ${scopes}=    Create List    photo    video
    ${consent_id}=    Register Test Consent    ${parties}    ${scopes}
    Should Not Be Empty    ${consent_id}

Verify Consent Is Valid
    [Documentation]    Verify consent is valid on-chain
    ${parties}=    Create List    0x1111    0x2222
    ${scopes}=    Create List    photo
    ${consent_id}=    Register Test Consent    ${parties}    ${scopes}
    ${valid}=    Verify Consent On Chain    ${consent_id}
    Should Be True    ${valid}

Revoke Consent
    [Documentation]    Revoke consent and verify it's no longer valid
    ${parties}=    Create List    0x1111    0x2222
    ${scopes}=    Create List    photo
    ${consent_id}=    Register Test Consent    ${parties}    ${scopes}
    Revoke Consent On Chain    ${consent_id}
    ${valid}=    Verify Consent On Chain    ${consent_id}
    Should Not Be True    ${valid}

Unauthorized Revocation Fails
    [Documentation]    Non-party cannot revoke consent
    ${parties}=    Create List    0x1111    0x2222
    ${scopes}=    Create List    photo
    ${consent_id}=    Register Test Consent    ${parties}    ${scopes}
    Run Keyword And Expect Error    *    Revoke Consent On Chain    ${consent_id}

Consent Expires
    [Documentation]    Test time-based expiration
    ${parties}=    Create List    0x1111    0x2222
    ${scopes}=    Create List    photo
    ${consent_id}=    Register Test Consent    ${parties}    ${scopes}    duration=1
    Sleep    2s
    ${valid}=    Verify Consent On Chain    ${consent_id}
    Should Not Be True    ${valid}
