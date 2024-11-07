// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Staking} from "../src/Staking.sol";
import {TRADE_TOKEN} from "test/utils/constant_pol.sol";
import "forge-std/console.sol";

contract DeployStakingScript is Script {
    uint256 ratePerSecond = 5787040 gwei;
    address token = 0x16221C54aC110943d4fd7BF940F15dfAAe3BBAFB;

    function run() public {

        uint256 mainnetPrivateKey = vm.envUint("MAINNET_PRIVATE_KEY");
        uint256 mumbaiPrivateKey = vm.envUint("TESTNET_PRIVATE_KEY");

        address owner = vm.addr(mumbaiPrivateKey);
        vm.startBroadcast(mumbaiPrivateKey);

        Staking staking = new Staking(token, token, ratePerSecond, owner);

        vm.stopBroadcast();
    }
}
