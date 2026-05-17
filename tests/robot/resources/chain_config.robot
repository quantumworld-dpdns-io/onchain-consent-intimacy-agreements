*** Settings ***
Library    Collections
Library    ../resources/web3_keywords.py

*** Variables ***
${SEPOLIA_RPC}          ${EMPTY}
${BSC_TESTNET_RPC}      ${EMPTY}
${AMOY_RPC}             ${EMPTY}
${PALM_TESTNET_RPC}     ${EMPTY}
${BASE_SEPOLIA_RPC}     ${EMPTY}
${SOLANA_DEVNET_RPC}    ${EMPTY}
${LOCAL_RPC}            http://localhost:8545
${DEFAULT_CHAIN}        local
${SEPOLIA_CHAIN_ID}     11155111
${BSC_TESTNET_CHAIN_ID} 97
${AMOY_CHAIN_ID}        80002
${PALM_TESTNET_CHAIN_ID} 11297108109
${BASE_SEPOLIA_CHAIN_ID} 84532
${SOLANA_DEVNET_CHAIN_ID} devnet
${LOCAL_CHAIN_ID}       31337

*** Keywords ***
Get Chain RPC
    [Arguments]    ${chain}
    IF    '${chain}' == 'sepolia'
        ${rpc}=    Set Variable    ${SEPOLIA_RPC}
    ELSE IF    '${chain}' == 'bsc_testnet'
        ${rpc}=    Set Variable    ${BSC_TESTNET_RPC}
    ELSE IF    '${chain}' == 'amoy'
        ${rpc}=    Set Variable    ${AMOY_RPC}
    ELSE IF    '${chain}' == 'palm_testnet'
        ${rpc}=    Set Variable    ${PALM_TESTNET_RPC}
    ELSE IF    '${chain}' == 'base_sepolia'
        ${rpc}=    Set Variable    ${BASE_SEPOLIA_RPC}
    ELSE IF    '${chain}' == 'solana_devnet'
        ${rpc}=    Set Variable    ${SOLANA_DEVNET_RPC}
    ELSE IF    '${chain}' == 'local'
        ${rpc}=    Set Variable    ${LOCAL_RPC}
    ELSE
        Fail    Unknown chain: ${chain}
    END
    IF    '${rpc}' == '${EMPTY}'
        Fail    RPC URL not configured for chain: ${chain}. Set ${chain}_RPC environment variable.
    END
    RETURN    ${rpc}

Get Chain Id
    [Arguments]    ${chain}
    IF    '${chain}' == 'sepolia'
        RETURN    ${SEPOLIA_CHAIN_ID}
    ELSE IF    '${chain}' == 'bsc_testnet'
        RETURN    ${BSC_TESTNET_CHAIN_ID}
    ELSE IF    '${chain}' == 'amoy'
        RETURN    ${AMOY_CHAIN_ID}
    ELSE IF    '${chain}' == 'palm_testnet'
        RETURN    ${PALM_TESTNET_CHAIN_ID}
    ELSE IF    '${chain}' == 'base_sepolia'
        RETURN    ${BASE_SEPOLIA_CHAIN_ID}
    ELSE IF    '${chain}' == 'solana_devnet'
        RETURN    ${SOLANA_DEVNET_CHAIN_ID}
    ELSE IF    '${chain}' == 'local'
        RETURN    ${LOCAL_CHAIN_ID}
    ELSE
        Fail    Unknown chain: ${chain}
    END

Setup Local Chain
    [Documentation]    Start a local Anvil instance if not already running
    ${web3}=    web3_keywords.Web3Keywords
    ${web3.setup_local_chain}

Cleanup Local Chain
    [Documentation]    Kill the local Anvil process
    ${web3}=    web3_keywords.Web3Keywords
    ${web3.cleanup_local_chain}

Generate Test Headers
    [Arguments]    ${api_key}=test-valid-api-key    ${signer}=${EMPTY}
    ${headers}=    Create Dictionary    Authorization=Bearer ${api_key}
    IF    '${signer}' != '${EMPTY}'
        Set To Dictionary    ${headers}    X-Signer-Address=${signer}
    END
    RETURN    ${headers}

Assert Consent Fields Match
    [Arguments]    ${consent}    ${expected_parties}    ${expected_scopes}
    ${actual_parties}=    Set Variable    ${consent['parties']}
    ${actual_scopes}=    Set Variable    ${consent['scopes']}
    Lists Should Be Equal    ${actual_parties}    ${expected_parties}    msg=Parties do not match
    Lists Should Be Equal    ${actual_scopes}    ${expected_scopes}    msg=Scopes do not match
    Dictionary Should Contain Key    ${consent}    id
    Dictionary Should Contain Key    ${consent}    validFrom
    Dictionary Should Contain Key    ${consent}    validUntil
    Dictionary Should Contain Key    ${consent}    revoked

Wait For Condition
    [Arguments]    ${condition_func}    ${timeout}=30    ${interval}=1
    ${deadline}=    Evaluate    time.time() + ${timeout}    time
    WHILE    True
        ${result}=    Evaluate    ${condition_func}()
        IF    ${result}    BREAK
        ${elapsed}=    Evaluate    time.time() - (${deadline} - ${timeout})
        IF    ${elapsed} > ${timeout}
            Fail    Condition not met within ${timeout}s
        END
        Sleep    ${interval}
    END
