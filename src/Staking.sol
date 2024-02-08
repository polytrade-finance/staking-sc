// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IStaking} from "contracts/interface/IStaking.sol";

/**
 * @notice Staking contract that distribute a fixed reward rate per second among
 * stakers according to their time-weighted contributions to this pool
 * @dev Rewarding rate for staked tokens is per second
 * @dev Each contract represents a pool for an ERC20 pair tokens
 */
contract Staking is Ownable, IStaking {
    using SafeERC20 for IERC20;

    IERC20 public stakingToken;
    IERC20 public rewardToken;
    uint256 public ratePerSecond;
    uint256 public lastRewardTimestamp;
    uint256 public accRewardsPerShare;

    mapping(address => StakerInfo) public stakerInfo;
    uint256 private _totalStaked;

    /**
     * @param stakingToken_ address of ERC20 underlying token
     * @param rewardToken_ address of ERC20 reward token
     * @param ratePerSecond_ is reward token rate per second to distribute among stakers
     * @param owner_, address of the owner of contract to update rate
     */
    constructor(address stakingToken_, address rewardToken_, uint256 ratePerSecond_, address owner_) Ownable(owner_) {
        stakingToken = IERC20(stakingToken_);
        rewardToken = IERC20(rewardToken_);
        ratePerSecond = ratePerSecond_;
    }

    /**
     * @dev See {IStaking-stake}.
     */
    function stake(uint256 amount) external {
        StakerInfo storage staker = stakerInfo[msg.sender];
        _updatePool();
        if (staker.stakedAmount > 0) {
            uint256 pending = (staker.stakedAmount * accRewardsPerShare) - staker.rewardDebt;

            staker.accRewards += pending;
        }

        _totalStaked += amount;
        staker.stakedAmount += amount;
        staker.rewardDebt = staker.stakedAmount * accRewardsPerShare;

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Stake(msg.sender, amount);
    }

    /**
     * @dev See {IStaking-withdraw}.
     */
    function withdraw(uint256 amount) external {
        StakerInfo storage staker = stakerInfo[msg.sender];
        if (staker.stakedAmount < amount) {
            revert NotEnoughBalance();
        }

        _updatePool();

        uint256 pending = (staker.stakedAmount * accRewardsPerShare) - staker.rewardDebt;
        staker.accRewards += pending;
        _totalStaked -= amount;
        staker.stakedAmount -= amount;
        staker.rewardDebt = staker.stakedAmount * accRewardsPerShare;

        _withdraw(amount);
    }

    /**
     * @dev See {IStaking-claim}.
     */
    function claim() external returns (uint256 rewards) {
        StakerInfo storage staker = stakerInfo[msg.sender];
        if (staker.stakedAmount == 0 && staker.accRewards == 0) {
            revert NoRewards();
        }

        _updatePool();

        rewards = (staker.stakedAmount * accRewardsPerShare) + staker.accRewards - staker.rewardDebt;
        staker.accRewards = 0;
        staker.rewardDebt = staker.stakedAmount * accRewardsPerShare;

        _claim(rewards);
    }

    /**
     * @dev See {IStaking-withdrawAll}.
     */
    function withdrawAll() external returns (uint256 rewards) {
        StakerInfo memory staker = stakerInfo[msg.sender];
        if (staker.stakedAmount == 0) {
            revert NotEnoughBalance();
        }

        _updatePool();

        rewards = (staker.stakedAmount * accRewardsPerShare) + staker.accRewards - staker.rewardDebt;
        _totalStaked -= staker.stakedAmount;
        delete stakerInfo[msg.sender];

        _claim(rewards);
        _withdraw(staker.stakedAmount);
    }

    /**
     * @dev See {IStaking-emergencyWithdraw}.
     */
    function emergencyWithdraw() external {
        StakerInfo memory staker = stakerInfo[msg.sender];
        if (staker.stakedAmount == 0) {
            revert NotEnoughBalance();
        }

        delete stakerInfo[msg.sender];

        stakingToken.safeTransfer(msg.sender, staker.stakedAmount);
        emit EmergencyWithdraw(msg.sender, staker.stakedAmount);
    }

    /**
     * @dev See {IStaking-updateRate}.
     */
    function updateRate(uint256 rate) external onlyOwner {
        _updatePool();

        emit RateUpdate(ratePerSecond, rate);
        ratePerSecond = rate;
    }

    /**
     * @dev See {IStaking-getReward}.
     */
    function getReward(address account) external view returns (uint256) {
        if (_totalStaked == 0) {
            return 0;
        }
        StakerInfo memory staker = stakerInfo[account];

        uint256 reward = (block.timestamp - lastRewardTimestamp) * ratePerSecond;
        uint256 rewardsPerShare = accRewardsPerShare + (reward / _totalStaked);

        return (staker.stakedAmount * rewardsPerShare) + staker.accRewards - staker.rewardDebt;
    }

    /**
     * @dev See {IStaking-totalStaked}.
     */
    function totalStaked() external view returns (uint256) {
        return _totalStaked;
    }

    /**
     * @dev See {IStaking-balanceOf}.
     */
    function balanceOf(address account) external view returns (uint256) {
        return stakerInfo[account].stakedAmount;
    }

    /**
     * @dev Transfer the rewards to `msg.sender` and emits the Claim event
     * @param rewards, amount of reward to claim
     */
    function _claim(uint256 rewards) private {
        rewardToken.safeTransfer(msg.sender, rewards);
        emit Claim(msg.sender, rewards);
    }

    /**
     * @dev Transfer the amount to `msg.sender` and emits the Withdraw event
     * @param amount, amount of token to withdraw
     */
    function _withdraw(uint256 amount) private {
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }

    /**
     * @dev Updates pool parameters on Stake, Withdraw and Claim
     * @dev only updates timestamp if there is no staked amount
     * @dev skip update if called in same updated timestamp
     */
    function _updatePool() private {
        if (block.timestamp <= lastRewardTimestamp) {
            return;
        }

        if (_totalStaked == 0) {
            lastRewardTimestamp = block.timestamp;
            return;
        }

        uint256 reward = (block.timestamp - lastRewardTimestamp) * ratePerSecond;

        accRewardsPerShare += (reward / _totalStaked);
        lastRewardTimestamp = block.timestamp;
    }
}
