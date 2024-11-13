// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";
import {TimedStaking} from "../src/TimedStaking.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployTimedStaking is Script {
    // Define constructor parameters here
    address public stakingToken;
    address public rewardToken;
    uint256 public maxStake;
    uint256 public lockInPeriod;
    uint256 public apr;
    uint256 public interestStartTimestamp;
    address public owner;

    // Specify network-specific constructor parameters using environment variables
    function setUp() public {
        stakingToken = vm.envAddress("STAKE_TOKEN");
        rewardToken = vm.envAddress("REWARD_TOKEN");
        maxStake = vm.envUint("MAX_STAKE");
        lockInPeriod = vm.envUint("LOCK_IN_PERIOD");
        apr = vm.envUint("APR");
        interestStartTimestamp = vm.envUint("INTEREST_START_TIMESTAMP");
        owner = vm.envAddress("OWNER");
    }

    function run() public {
        // Fetch private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Begin broadcasting transactions using deployer's private key
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the TimedStaking contract
        TimedStaking stakingContract = new TimedStaking(
            stakingToken,
            rewardToken,
            maxStake,
            lockInPeriod,
            apr,
            interestStartTimestamp,
            owner
        );

        vm.stopBroadcast();

        // Log the address for reference
        console.log("TimedStaking deployed at:", address(stakingContract));

    }

}
