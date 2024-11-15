// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/TimedStaking.sol";
import "./utils/ERC20Mock.sol";

contract TimedStakingTest is Test {
    TimedStaking public staking;
    ERC20Mock public stakingToken;
    ERC20Mock public rewardToken;
    address public ownerAddr = address(0x1);
    address public user = address(0x2);

    uint256 public maxStake = 1000 ether;
    uint256 public lockInPeriod = 30 days;
    uint256 public apr = 10; // 10% APR for simplicity
    uint256 public interestStartTimestamp;

    function setUp() public {
        stakingToken = new ERC20Mock("StakingToken", "STK", 18);
        rewardToken = new ERC20Mock("RewardToken", "RWD", 18);

        // Set the interest start timestamp to 2 days from the current time
        interestStartTimestamp = block.timestamp + 2 days;

        staking = new TimedStaking(
            address(stakingToken),
            address(rewardToken),
            maxStake,
            lockInPeriod,
            apr,
            interestStartTimestamp,
            ownerAddr // owner
        );

        // Mint and allocate tokens for the user and staking contract
        stakingToken.mint(user, 100 ether);
        rewardToken.mint(address(staking), 1000 ether);
    }

    function testStakeTokens() public {
        vm.startPrank(user);
        stakingToken.approve(address(staking), 10 ether);
        staking.stake(10 ether);

        assertEq(staking.balanceOf(user), 10 ether, "User's staked amount should be 10 ether");
        assertEq(staking.totalStaked(), 10 ether, "Total staked amount should be 10 ether");
        vm.stopPrank();
    }

    function testWithdrawTokens() public {
        vm.startPrank(user);
        stakingToken.approve(address(staking), 10 ether);
        staking.stake(10 ether);

        // Fast-forward time beyond the lock-in period + interest start time
        vm.warp(interestStartTimestamp + lockInPeriod + 1);
        staking.withdraw(10 ether);

        assertEq(staking.balanceOf(user), 0, "User's balance should be 0 after withdrawal");
        assertEq(staking.totalStaked(), 0, "Total staked amount should be 0 after withdrawal");
        vm.stopPrank();
    }

    function testClaimRewards() public {
        vm.startPrank(ownerAddr);
        staking.setClaimActive(true);
        vm.stopPrank();
        
        vm.startPrank(user);
        stakingToken.approve(address(staking), 10 ether);
        staking.stake(10 ether);

        // Fast-forward time to enable rewards
        vm.warp(interestStartTimestamp + 1 days);
        staking.claim();

        uint256 claimedRewards = rewardToken.balanceOf(user);
        assertGt(claimedRewards, 0, "Claimed rewards should be greater than 0");
        vm.stopPrank();
    }

    function testEmergencyWithdraw() public {
        vm.startPrank(user);
        stakingToken.approve(address(staking), 10 ether);
        staking.stake(10 ether);
        vm.stopPrank();

        vm.startPrank(ownerAddr);
        // Perform emergency withdraw by the owner
        uint256 contractBalanceBefore = stakingToken.balanceOf(address(staking));
        staking.emergencyWithdraw();
        uint256 contractBalanceAfter = stakingToken.balanceOf(address(staking));
        vm.stopPrank(); 

        assertEq(contractBalanceAfter, 0, "Staking contract balance should be 0 after emergency withdraw");
        assertEq(
            stakingToken.balanceOf(ownerAddr),
            contractBalanceBefore,
            "Owner should receive all staked tokens after emergency withdraw"
        );
    }

    function testSetClaimActive() public {
        vm.startPrank(ownerAddr);
        assertFalse(staking.isClaimActive(), "Claim should be initially inactive");
        staking.setClaimActive(true);
        assertTrue(staking.isClaimActive(), "Claim should be active after setting it");
        vm.stopPrank();
    }
}
