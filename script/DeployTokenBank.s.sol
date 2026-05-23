// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/BaseERC20.sol";
import "../src/tokenBank.sol";

contract DeployTokenBank is Script {
    function run() external {
        vm.startBroadcast();

        BaseERC20 token = new BaseERC20();
        TokenBank bank = new TokenBank(address(token));

        vm.stopBroadcast();

        console.log("BaseERC20 address:", address(token));
        console.log("TokenBank address:", address(bank));
        console.log("Token name:", token.name());
        console.log("Token symbol:", token.symbol());
        console.log("Token totalSupply:", token.totalSupply());
    }
}
