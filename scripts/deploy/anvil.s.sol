// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {ConsentRegistry} from "src/contracts/ConsentRegistry.sol";
import {ConsentEscrow} from "src/contracts/ConsentEscrow.sol";
import {ConsentToken} from "src/contracts/ConsentToken.sol";
import {ConsentVerifier} from "src/contracts/ConsentVerifier.sol";
import {ConsentFactory} from "src/contracts/ConsentFactory.sol";

contract DeployAnvil is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        ConsentRegistry registry = new ConsentRegistry();
        ConsentEscrow escrow = new ConsentEscrow();
        ConsentToken token = new ConsentToken();
        ConsentVerifier verifier = new ConsentVerifier();

        registry.grantRole(registry.DEFAULT_ADMIN_ROLE(), deployer);

        ConsentFactory factory = new ConsentFactory{salt: 0x01}();

        vm.stopBroadcast();

        console.log("Deployer:", deployer);
        console.log("ConsentRegistry:", address(registry));
        console.log("ConsentEscrow:", address(escrow));
        console.log("ConsentToken:", address(token));
        console.log("ConsentVerifier:", address(verifier));
        console.log("ConsentFactory:", address(factory));
    }
}
