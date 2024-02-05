// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IStaking} from "contracts/interface/IStaking.sol";

contract Staking is Ownable, IStaking {
    using SafeERC20 for IERC20;

    IERC20 public stakingToken;
    IERC20 public rewardToken;
    uint256 public ratePerSecond;
    uint256 public lastRewardTimestamp;
    uint256 public accRewardsPerShare;

    mapping(address => StakerInfo) public stakerInfo;

    constructor(address stakingToken_, address rewardToken_, uint256 ratePerSecond_, address owner_) Ownable(owner_) {
        stakingToken = IERC20(stakingToken_);
        rewardToken = IERC20(rewardToken_);
        ratePerSecond = ratePerSecond_;
    }

    function deposit(uint256 amount) external {
        StakerInfo storage staker = stakerInfo[msg.sender];
        _updatePool();
        if (staker.stakedAmount > 0) {
            uint256 pending = (staker.stakedAmount * accRewardsPerShare) - staker.rewardDebt;

            staker.accRewards += pending;
        }

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        staker.stakedAmount += amount;
        staker.rewardDebt = amount * (accRewardsPerShare);

        emit Deposit(msg.sender, amount);
    }

    function _updatePool() private {
        if (block.timestamp <= lastRewardTimestamp) {
            return;
        }

        uint256 stakedAmount = stakingToken.balanceOf(address(this));
        if (stakedAmount == 0) {
            lastRewardTimestamp = block.timestamp;
            return;
        }

        uint256 reward = (block.timestamp - lastRewardTimestamp) * ratePerSecond;

        accRewardsPerShare += (reward / stakedAmount);
        lastRewardTimestamp = block.timestamp;
    }
}
