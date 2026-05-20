// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "../src/myToken.sol";

contract DeployMyToken is Script {
    function run() external {
        // ---------------------------------------------------------------
        // 安全的 keystore 部署脚本 —— 私钥永不出现在脚本或环境变量中
        //
        // 前提：已通过 cast wallet import 将私钥加密存储到 keystore
        // 运行：forge script ... --account <name> --rpc-url sepolia --broadcast
        //       Foundry 会交互式询问 keystore 密码来解锁签名密钥
        //
        // vm.startBroadcast() 不带参数 = 使用 --account 解锁的所有签名者
        // ---------------------------------------------------------------

        console.log("=== MyToken Deployment (keystore) ===");
        console.log("Chain ID:", block.chainid);
        console.log("======================================");

        vm.startBroadcast();

        // 代币名: MyToken | 符号: MTK | 初始供应: 100 亿 (1e10 * 1e18)
        MyToken token = new MyToken("MyToken", "MTK");

        vm.stopBroadcast();

        console.log("");
        console.log("=== Deployment Result ===");
        console.log("MyToken address:", address(token));
        console.log("Total supply  :", token.totalSupply() / 1e18, "MTK");
        console.log("");
        console.log("View on Etherscan:");
        console.log("https://sepolia.etherscan.io/address/", address(token));
        console.log("=========================");
    }
}
