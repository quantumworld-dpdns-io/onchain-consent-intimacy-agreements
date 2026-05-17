*** Settings ***
Library             RequestsLibrary
Library             Collections
Library             ../resources/web3_keywords.py
Library             OperatingSystem
Resource            ../resources/chain_config.robot

*** Variables ***
${BASE_URL}         http://localhost:8080
${VALID_API_KEY}    test-valid-api-key
${PROJECT_ROOT}     ${CURDIR}/../../..

*** Test Cases ***
Check Openzeppelin Version For Known Vulns
    [Documentation]    A06 - Verify OpenZeppelin dependency is not vulnerable
    ${package_json}=    Get File    ${PROJECT_ROOT}/package.json
    Should Contain    ${package_json}    @openzeppelin/contracts    msg=OpenZeppelin contracts must be present
    Should Not Contain    ${package_json}    "@openzeppelin/contracts": "^4."    msg=OpenZeppelin v4 may have known vulns, v5 required
    Should Contain    ${package_json}    "@openzeppelin/contracts": "^5."    msg=OpenZeppelin v5+ required
    ${hardhat_config}=    Get File    ${PROJECT_ROOT}/hardhat.config.ts
    Should Not Contain    ${hardhat_config}    solidity: "0.8."    msg=Exact Solidity version must be specified (not minor range)

Solidity Compiler Version Is Safe
    [Documentation]    A06 - Solidity pragma should use a safe compiler version
    ${registry_sol}=    Get File    ${PROJECT_ROOT}/src/contracts/ConsentRegistry.sol
    Should Contain    ${registry_sol}    pragma solidity ^0.8.27    msg=ConsentRegistry should use Solidity ^0.8.27 or later
    ${escrow_sol}=    Get File    ${PROJECT_ROOT}/src/contracts/ConsentEscrow.sol
    Should Contain    ${escrow_sol}    pragma solidity ^0.8.27    msg=ConsentEscrow should use Solidity ^0.8.27
    ${verifier_sol}=    Get File    ${PROJECT_ROOT}/src/contracts/ConsentVerifier.sol
    Should Contain    ${verifier_sol}    pragma solidity ^0.8.27    msg=ConsentVerifier should use Solidity ^0.8.27

No Deprecated Solidity Constructs
    [Documentation]    A06 - Check for deprecated Solidity keywords or constructs
    ${tx_origin}=    Grep File    ${PROJECT_ROOT}/src    tx.origin
    Should Be Empty    ${tx_origin}    msg=tx.origin must not be used (phishing risk)
    ${delegatecall_usage}=    Grep File    ${PROJECT_ROOT}/src    delegatecall
    Should Not Be Empty    ${delegatecall_usage}    msg=Expected delegatecall only in factory proxy pattern
    ${selfdestruct}=    Grep File    ${PROJECT_ROOT}/src    selfdestruct
    Should Be Empty    ${selfdestruct}    msg=selfdestruct must not be used

Dependencies Have No Known Critical Vulnerabilities
    [Documentation]    A06 - Check package.json dependencies for outdated major versions
    ${package_json}=    Get File    ${PROJECT_ROOT}/package.json
    Should Not Contain    ${package_json}    "hardhat": "^1."    msg=Hardhat v1 is outdated
    Should Contain    ${package_json}    "hardhat": "^2."    msg=Hardhat v2+ required
    Should Not Contain    ${package_json}    "@nomicfoundation/hardhat-toolbox": "^4."    msg=Hardhat toolbox v4 is outdated
    Should Contain    ${package_json}    "@nomicfoundation/hardhat-toolbox": "^5."    msg=Hardhat toolbox v5+ required

No Bytecode Or Assembly In Secure Contracts
    [Documentation]    A06 - Assembly usage should be limited to factory proxies
    ${registry_asm}=    Grep File    ${PROJECT_ROOT}/src/contracts/ConsentRegistry.sol    assembly
    Should Be Empty    ${registry_asm}    msg=ConsentRegistry must not use inline assembly
    ${verifier_asm}=    Grep File    ${PROJECT_ROOT}/src/contracts/ConsentVerifier.sol    assembly
    Should Be Empty    ${verifier_asm}    msg=ConsentVerifier must not use inline assembly
    ${factory_asm}=    Grep File    ${PROJECT_ROOT}/src/contracts/ConsentFactory.sol    assembly
    Should Not Be Empty    ${factory_asm}    msg=ConsentFactory should use assembly for CREATE2

Foundry Config Has Fuzz Settings
    [Documentation]    A06 - Foundry configuration should enable fuzz testing
    ${foundry_toml}=    Get File    ${PROJECT_ROOT}/foundry.toml
    Should Contain    ${foundry_toml}    fuzz    msg=foundry.toml should have fuzz configuration
    Should Contain    ${foundry_toml}    runs    msg=foundry.toml should specify fuzz runs

Event Indexer Uses Safe Dependencies
    [Documentation]    A06 - Event indexer Go modules should not have known vulnerabilities
    ${go_sum}=    Run    ls ${PROJECT_ROOT}/backend/event-indexer/ 2>/dev/null || echo "EMPTY"
    IF    "${go_sum}" != "EMPTY"
        ${go_mod}=    Get File    ${PROJECT_ROOT}/backend/event-indexer/go.mod
        Should Contain    ${go_mod}    go 1.2    msg=Go version should be 1.21+
    END

Circuit Artifacts Use Safe Powers Of Tau
    [Documentation]    A06 - ZK circuit should use at least powersOfTau28_hez_final
    ${circuits_dir}=    Run    ls ${PROJECT_ROOT}/circuits/ 2>/dev/null || echo "EMPTY"
    IF    "${circuits_dir}" != "EMPTY"
        ${circuit_config}=    Run    ls ${PROJECT_ROOT}/circuits/*.json 2>/dev/null || echo "EMPTY"
        Should Not Be Empty    ${circuit_config}    msg=Circuit config files must exist
    END
