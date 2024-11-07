// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "contracts/TimedStaking.sol";
import "contracts/interface/IStaking.sol";
import "test/utils/TestERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


// Tests
contract TimedStakingTest is Test {
    TimedStaking staking;
    TestERC20 stakingToken;
    TestERC20 rewardToken;
    address owner = address(1);
    address user1 = address(2);
    address user2 = address(3);

    uint256 maxStake = 1_000 ether;
    uint256 lockInPeriod = 30 days;
    uint256 apr = 10;  // 10% APR

    function setUp() public {
        // Deploy mock tokens and mint balances
        stakingToken = new TestERC20();
        rewardToken = new TestERC20();
        stakingToken.mint(user1, 1_000 ether);
        stakingToken.mint(user2, 1_000 ether);
        rewardToken.mint(owner, 100_000 ether);

        // Deploy staking contract with parameters
        staking = new TimedStaking(
            address(stakingToken),
            address(rewardToken),
            maxStake,
            lockInPeriod,
            apr,
            owner
        );

        // Fund staking contract with reward tokens
        vm.prank(owner);
        rewardToken.transfer(address(staking), 100_000 ether);
    }

    function testConstructorInitialization() public {
        assertEq(address(staking.stakingToken()), address(stakingToken));
        assertEq(address(staking.rewardToken()), address(rewardToken));
        assertEq(staking.maxStake(), maxStake);
        assertEq(staking.lockInPeriod(), lockInPeriod);
        assertEq(staking.apr(), apr);
        assertFalse(staking.isClaimActive());
    }

    function testStakeWithinLimit() public {
        uint256 amount = 500 ether;

        vm.startPrank(user1);
        stakingToken.approve(address(staking), amount);
        staking.stake(amount);

        // Verify staked amount and total staked
        IStaking.StakerInfo memory info = staking.stakerInfo(user1);
        assertEq(info.stakedAmount, amount);
        assertEq(staking.totalStaked(), amount);
    }

    function testStakeExceedsMaxLimit() public {
        uint256 amount = maxStake + 1 ether;

        vm.startPrank(user1);
        stakingToken.approve(address(staking), amount);

        vm.expectRevert("Exceeds max stake limit");
        staking.stake(amount);
    }

    function testWithdrawBeforeLockPeriod() public {
        uint256 amount = 100 ether;

        vm.startPrank(user1);
        stakingToken.approve(address(staking), amount);
        staking.stake(amount);

        vm.warp(block.timestamp + lockInPeriod - 1);

        vm.expectRevert("Lock-in period active");
        staking.withdraw(amount);
    }

    function testWithdrawAfterLockPeriod() public {
        uint256 amount = 100 ether;

        vm.startPrank(user1);
        stakingToken.approve(address(staking), amount);
        staking.stake(amount);

        vm.warp(block.timestamp + lockInPeriod);

        staking.withdraw(amount);

        IStaking.StakerInfo memory info = staking.stakerInfo(user1);
        assertEq(info.stakedAmount, 0);
    }

    function testClaimRewardsAfterStaking() public {
        uint256 amount = 100 ether;

        vm.startPrank(user1);
        stakingToken.approve(address(staking), amount);
        staking.stake(amount);

        vm.warp(block.timestamp + 10 days);
        
        staking.setClaimActive(true);
        uint256 reward = staking.claim();
        
        assertGt(reward, 0, "Expected non-zero rewards");
    }

    function testEmergencyWithdraw() public {
        uint256 amount = 200 ether;

        vm.startPrank(user1);
        stakingToken.approve(address(staking), amount);
        staking.stake(amount);

        staking.emergencyWithdraw();

        IStaking.StakerInfo memory info = staking.stakerInfo(user1);
        assertEq(info.stakedAmount, 0);
    }

    function testOwnerOnlyUpdateRate() public {
        uint256 newRate = 2 ether;

        vm.prank(owner);
        staking.updateRate(newRate);

        assertEq(staking.ratePerSecond(), newRate);
    }

    function testNonOwnerCannotUpdateRate() public {
        uint256 newRate = 2 ether;

        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        staking.updateRate(newRate);
    }

    function testSetClaimActive() public {
        vm.prank(owner);
        staking.setClaimActive(true);

        assertTrue(staking.isClaimActive());
    }
}
