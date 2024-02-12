// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/console.sol";
import {Test, console2} from "forge-std/Test.sol";
import {Staking} from "contracts/Staking.sol";
import {TRADE_TOKEN, TRADE_PROVIDER} from "test/utils/constant_pol.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StakingTest is Test {
    uint256 mainnetFork;
    uint256 ratePerSecond = 5787040 gwei;
    string POLYGON_ARCHIVAL_RPC = vm.envString("POLYGON_ARCHIVAL_RPC");
    address owner;
    address staker1;
    address staker2;

    IERC20 trade;
    Staking pool;

    function setUp() public {
        mainnetFork = vm.createFork(POLYGON_ARCHIVAL_RPC);
        vm.selectFork(mainnetFork);
        owner = TRADE_PROVIDER;
        staker1 = makeAddr("staker1");
        staker2 = makeAddr("staker2");
        trade = IERC20(TRADE_TOKEN);

        vm.deal(owner, 200 ether);

        vm.startPrank(owner);
        pool = new Staking(TRADE_TOKEN, TRADE_TOKEN, ratePerSecond, owner);
        
        trade.transfer(address(pool), 1000 * 86400 * ratePerSecond);
        trade.transfer(staker1, 10000 ether);
        trade.transfer(staker2, 10000 ether);
        vm.stopPrank();
        vm.prank(staker1);
        trade.approve(address(pool), type(uint256).max);
        vm.prank(staker2);
        trade.approve(address(pool), type(uint256).max);
    }

    function testStake() public {
        uint256 stakeAmount = 100 ether;
        uint256 duration = 1 weeks;
        uint256 expectReward1 = duration * ratePerSecond;
        uint256 accRewardsPerShare;

        vm.prank(staker1);
        pool.stake(stakeAmount);
        assertEq(pool.lastRewardTimestamp(), block.timestamp);
        assertEq(pool.accRewardsPerShare(), accRewardsPerShare);
        skip(duration);

        assertEq(expectReward1, pool.getReward(staker1));

        uint256 expectReward2 = 2 * duration * ratePerSecond / 3;
        expectReward1 += duration * ratePerSecond / 3;
        accRewardsPerShare =  (duration * ratePerSecond * 1e24) / stakeAmount;

        vm.prank(staker2);
        pool.stake(2 * stakeAmount);
        assertEq(pool.lastRewardTimestamp(), block.timestamp);
        assertEq(pool.accRewardsPerShare(), accRewardsPerShare);
        skip(duration);

        assertEq(expectReward2, pool.getReward(staker2));
        assertEq(expectReward1, pool.getReward(staker1));

        expectReward2 += 13 * 2 * duration * ratePerSecond / 15;
        expectReward1 += 13 * 13 * duration * ratePerSecond / 15;

        vm.prank(staker1);
        pool.stake(12 * stakeAmount);
        assertEq(pool.lastRewardTimestamp(), block.timestamp);
        skip(13 * duration);

        assertEq(expectReward2, pool.getReward(staker2));
        assertEq(expectReward1, pool.getReward(staker1));

        expectReward2 += 20 * 3 * duration * ratePerSecond / 17;
        expectReward1 += 20 * 14 * duration * ratePerSecond / 17;

        vm.prank(staker1);
        pool.stake(stakeAmount);
        vm.prank(staker2);
        pool.stake(stakeAmount);
        assertEq(pool.lastRewardTimestamp(), block.timestamp);
        skip(20 * duration);
        
        assertEq(expectReward2, pool.getReward(staker2));
        assertEq(expectReward1, pool.getReward(staker1));
    }

    function testClaim() public {
        uint256 stakeAmount = 313 ether;
        uint256 duration = 1 weeks + 317;
        uint256 expectReward1 = duration * ratePerSecond;

        vm.prank(staker1);
        pool.stake(stakeAmount);
        skip(duration);

        uint256 calculatedReward1 = pool.getReward(staker1);

        assertApproxEqRel(expectReward1, calculatedReward1, 1);

        uint256 beforeClaim = trade.balanceOf(staker1);
        vm.prank(staker1);
        pool.claim();
        uint256 afterClaim = trade.balanceOf(staker1);

        assertEq(afterClaim - beforeClaim, calculatedReward1);

        uint256 expectReward2 = 2 * duration * ratePerSecond / 3;
        expectReward1 = duration * ratePerSecond / 3;

        vm.prank(staker2);
        pool.stake(2 * stakeAmount);
        skip(duration);

        calculatedReward1 = pool.getReward(staker1);
        uint256 calculatedReward2 = pool.getReward(staker2);

        assertApproxEqRel(expectReward2, calculatedReward2, 1);
        assertApproxEqRel(expectReward1, calculatedReward1, 1);

        beforeClaim = trade.balanceOf(staker1);
        vm.prank(staker1);
        pool.claim();
        afterClaim = trade.balanceOf(staker1);

        assertEq(afterClaim - beforeClaim, calculatedReward1);

        beforeClaim = trade.balanceOf(staker2);
        vm.prank(staker2);
        pool.claim();
        afterClaim = trade.balanceOf(staker2);

        assertEq(afterClaim - beforeClaim, calculatedReward2);

        expectReward2 = 13 * 2 * duration * ratePerSecond / 15;
        expectReward1 = 13 * 13 * duration * ratePerSecond / 15;

        vm.prank(staker1);
        pool.stake(12 * stakeAmount);
        skip(13 * duration);

        calculatedReward1 = pool.getReward(staker1);
        calculatedReward2 = pool.getReward(staker2);

        assertApproxEqRel(expectReward2, calculatedReward2, 1);
        assertApproxEqRel(expectReward1, calculatedReward1, 1);

        beforeClaim = trade.balanceOf(staker1);
        vm.prank(staker1);
        pool.claim();
        afterClaim = trade.balanceOf(staker1);

        assertEq(afterClaim - beforeClaim, calculatedReward1);

        beforeClaim = trade.balanceOf(staker2);
        vm.prank(staker2);
        pool.claim();
        afterClaim = trade.balanceOf(staker2);

        assertEq(afterClaim - beforeClaim, calculatedReward2);

        expectReward2 = 20 * 3 * duration * ratePerSecond / 17;
        expectReward1 = 20 * 14 * duration * ratePerSecond / 17;

        vm.prank(staker1);
        pool.stake(stakeAmount);
        vm.prank(staker2);
        pool.stake(stakeAmount);
        skip(20 * duration);
        
        calculatedReward1 = pool.getReward(staker1);
        calculatedReward2 = pool.getReward(staker2);

        assertApproxEqRel(expectReward2, calculatedReward2, 1);
        assertApproxEqRel(expectReward1, calculatedReward1, 1);

        beforeClaim = trade.balanceOf(staker1);
        vm.prank(staker1);
        pool.claim();
        afterClaim = trade.balanceOf(staker1);

        assertEq(afterClaim - beforeClaim, calculatedReward1);

        beforeClaim = trade.balanceOf(staker2);
        vm.prank(staker2);
        pool.claim();
        afterClaim = trade.balanceOf(staker2);

        assertEq(afterClaim - beforeClaim, calculatedReward2);
    }
}
