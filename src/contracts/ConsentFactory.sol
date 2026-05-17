// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract ConsentFactory is ReentrancyGuard {
    event ContractDeployed(address indexed deployedAddress, bytes32 indexed salt, bytes32 indexed deploymentId);
    event ContractCreationFailed(bytes32 indexed salt, bytes reason);

    address[] private deployedConsents;
    mapping(address => bool) private isDeployedByFactory;
    mapping(bytes32 => address) private saltToAddress;
    mapping(bytes32 => bool) private saltUsed;

    bytes32 public constant INIT_CODE_HASH = keccak256(type(MinimalProxy).creationCode);

    address public immutable defaultImplementation;

    constructor(address _defaultImplementation) {
        if (_defaultImplementation == address(0)) revert("ConsentFactory: invalid implementation");
        defaultImplementation = _defaultImplementation;
    }

    function deployConsentContract(
        bytes32 _salt,
        bytes calldata _initializer
    ) external nonReentrant returns (address deployedAddress) {
        if (saltUsed[_salt]) revert("ConsentFactory: salt already used");

        deployedAddress = address(new MinimalProxy{salt: _salt}(defaultImplementation));

        if (deployedAddress == address(0)) {
            emit ContractCreationFailed(_salt, "deployment returned zero address");
            revert("ConsentFactory: deployment failed");
        }

        if (_initializer.length > 0) {
            (bool success, bytes memory returnData) = deployedAddress.call(_initializer);
            if (!success) {
                emit ContractCreationFailed(_salt, returnData);
                revert("ConsentFactory: initialization failed");
            }
        }

        deployedConsents.push(deployedAddress);
        isDeployedByFactory[deployedAddress] = true;
        saltToAddress[_salt] = deployedAddress;
        saltUsed[_salt] = true;

        bytes32 deploymentId = keccak256(abi.encodePacked(_salt, deployedAddress, block.timestamp));
        emit ContractDeployed(deployedAddress, _salt, deploymentId);
    }

    function getDeployedConsents() external view returns (address[] memory) {
        return deployedConsents;
    }

    function isDeployedFromFactory(address _contract) external view returns (bool) {
        return isDeployedByFactory[_contract];
    }

    function getDeployedAddress(bytes32 _salt) external view returns (address) {
        return saltToAddress[_salt];
    }

    function isSaltUsed(bytes32 _salt) external view returns (bool) {
        return saltUsed[_salt];
    }

    function getDeploymentCount() external view returns (uint256) {
        return deployedConsents.length;
    }

    function predictDeploymentAddress(bytes32 _salt) external view returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            _salt,
                            INIT_CODE_HASH
                        )
                    )
                )
            )
        );
    }
}

contract MinimalProxy {
    address public immutable implementation;

    constructor(address _implementation) {
        if (_implementation == address(0)) revert("MinimalProxy: invalid implementation");
        implementation = _implementation;
    }

    fallback() external payable {
        address impl = implementation;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}
