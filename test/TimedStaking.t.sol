// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/console.sol";
import {Test, console2} from "forge-std/Test.sol";
import {TimedStaking} from "contracts/TimedStaking.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IStaking} from "contracts/interface/IStaking.sol";

contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1_000_000 * 1e18); // Mint 1 million tokens for testing
    }
}

contract TimedStakingTest is Test {
    TimedStaking public staking;
    MockToken public stakingToken;
    MockToken public rewardToken;
    address public user = address(0x123);
    uint256 public initialStakeAmount = 1000 * 1e18;

    function setUp() public {
        stakingToken = new MockToken("Staking Token", "STK");
        rewardToken = new MockToken("Reward Token", "RWD");

        staking = new TimedStaking(
            address(stakingToken),
            address(rewardToken),
            10_000 * 1e18,    // max stake
            30 days,          // lock-in period
            500,              // APR (5%)
            block.timestamp + 1 days, // interest start timestamp
            address(this)     // owner
        );

        stakingToken.transfer(user, initialStakeAmount);
        vm.startPrank(user);
        stakingToken.approve(address(staking), initialStakeAmount);
        vm.stopPrank();
    }

    // Test cases

    function testStake() public {
        vm.startPrank(user);
        staking.stake(500 * 1e18);
        vm.stopPrank();

        (stakedAmount,,,) = staking.stakerInfo(user);
        assertEq(stakedAmount, 500 * 1e18, "Stake amount should be 500 tokens");
    }

    function testExceedMaxStakeFails() public {
        vm.startPrank(user);
        staking.stake(10_000 * 1e18); // Full max stake
        vm.expectRevert("Exceeds max stake limit");
        staking.stake(1 * 1e18); // Exceed max stake
        vm.stopPrank();
    }

    function testWithdrawBeforeLockInFails() public {
        vm.startPrank(user);
        staking.stake(500 * 1e18);
        vm.expectRevert("Lock-in period active");
        staking.withdraw(500 * 1e18);
        vm.stopPrank();
    }

    function testWithdrawAfterLockInPeriod() public {
        vm.startPrank(user);
        staking.stake(500 * 1e18);
        skip(30 days); // Move time forward past lock-in period
        staking.withdraw(500 * 1e18);
        vm.stopPrank();

        (stakedAmount,,,) = staking.stakerInfo(user);
        assertEq(stakedAmount, 0, "Stake should be withdrawn fully");
    }

    function testClaimBeforeActiveFails() public {
        vm.startPrank(user);
        staking.stake(500 * 1e18);
        staking.setClaimActive(false); // Make sure claim is inactive
        vm.expectRevert("Claiming is not active yet.");
        staking.claim();
        vm.stopPrank();
    }

    function testClaimAfterActive() public {
        vm.startPrank(user);
        staking.stake(500 * 1e18);
        staking.setClaimActive(true); // Enable claiming

        skip(10 days); // Accumulate some rewards
        uint256 rewards = staking.claim();

        assertGt(rewards, 0, "Rewards should be greater than zero");
        vm.stopPrank();
    }

    function testWithdrawAll() public {
        vm.startPrank(user);
        staking.stake(500 * 1e18);
        staking.setClaimActive(true); // Enable claim functionality

        skip(30 days); // Pass lock-in period
        uint256 rewards = staking.withdrawAll();

        assertGt(rewards, 0, "Rewards should be non-zero after withdrawAll");

        (stakedAmount,,,) = staking.stakerInfo(user);
        assertEq(stakedAmount, 0, "Staked amount should be zero after withdrawAll");
        vm.stopPrank();
    }

    function testToggleDeposits() public {
        staking.toggleDeposits(false);
        vm.startPrank(user);
        vm.expectRevert("Deposits are currently closed");
        staking.stake(500 * 1e18);
        vm.stopPrank();
    }

    function testInterestAccrual() public {
        vm.startPrank(user);
        staking.stake(500 * 1e18);
        skip(15 days);
        uint256 accruedReward = staking.getReward(user);

        assertGt(accruedReward, 0, "Accrued reward should be non-zero after 15 days");
        vm.stopPrank();
    }

    function testStakeAndClaimWithMultipleUsers() public {
        address user2 = address(0x456);
        stakingToken.transfer(user2, initialStakeAmount);

        vm.startPrank(user);
        staking.stake(500 * 1e18);
        vm.stopPrank();

        vm.startPrank(user2);
        stakingToken.approve(address(staking), initialStakeAmount);
        staking.stake(500 * 1e18);
        vm.stopPrank();

        staking.setClaimActive(true);
        skip(30 days);

        vm.startPrank(user);
        uint256 user1Rewards = staking.claim();
        assertGt(user1Rewards, 0, "User1 should have non-zero rewards");
        vm.stopPrank();

        vm.startPrank(user2);
        uint256 user2Rewards = staking.claim();
        assertGt(user2Rewards, 0, "User2 should have non-zero rewards");
        vm.stopPrank();
    }
}
