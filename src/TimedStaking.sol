// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IStaking} from "./interface/IStaking.sol";

contract TimedStaking is Ownable, IStaking {
    using SafeERC20 for IERC20;

    IERC20 public stakingToken;
    IERC20 public rewardToken;
    uint256 public lastRewardTimestamp;
    uint256 public accRewardsPerShare;
    uint256 public maxStake;      // Maximum total tokens in pool
    uint256 public lockInPeriod;  // Lock-in period for pool
    uint256 public apr;           // Annual Percentage Rate
    uint256 public interestStartTimestamp; // Interest start time in EPOCH
    uint256 private _totalStaked;
    uint256 private ratePerSecond;
    bool public isClaimActive;
    

    mapping(address => StakerInfo) public stakerInfo;

    constructor(
        address stakingToken_,
        address rewardToken_,
        uint256 maxStake_,
        uint256 lockInPeriod_,
        uint256 apr_,
        uint256 interestStartTimestamp_,
        address owner_
    ) Ownable(owner_) {
        stakingToken = IERC20(stakingToken_);
        rewardToken = IERC20(rewardToken_);
        maxStake = maxStake_;
        lockInPeriod = lockInPeriod_;
        apr = apr_;
        interestStartTimestamp = interestStartTimestamp_;
        isClaimActive = false;

        // Calculate ratePerSecond
        uint256 secondsInYear = 365 * 24 * 60 * 60; // Approximate seconds in a year
        ratePerSecond = (maxStake_ * apr_ * 1e24) / (100 * secondsInYear); // Scale by 1e24 to maintain precision
    }

    function stake(uint256 amount) external {
        require(block.timestamp < interestStartTimestamp, "Deposits closed");
        require(_totalStaked + amount <= maxStake, "Exceeds max stake limit");
        require(amount > 0, "Amount must be greater than 0");

        // Accumulate pending rewards for the staker if after interest start
        if (block.timestamp >= interestStartTimestamp && stakerInfo[msg.sender].stakedAmount > 0) {
            uint256 pendingReward = _calculateReward(msg.sender);
            stakerInfo[msg.sender].accRewards += pendingReward;
        }
        
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        
        _totalStaked += amount;
        stakerInfo[msg.sender].stakedAmount += amount;
        stakerInfo[msg.sender].rewardDebt = (stakerInfo[msg.sender].stakedAmount * accRewardsPerShare) / 1e24;
        stakerInfo[msg.sender].stakeTimestamp = block.timestamp;

        emit Stake(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
    
        require(stakerInfo[msg.sender].stakedAmount >= amount, "Not enough balance");
        require(block.timestamp >= interestStartTimestamp + lockInPeriod, "Lock-in period active");

        uint256 pending = ((stakerInfo[msg.sender].stakedAmount * accRewardsPerShare) / 1e24) - stakerInfo[msg.sender].rewardDebt;
        stakerInfo[msg.sender].accRewards += pending;
        _totalStaked -= amount;
        stakerInfo[msg.sender].stakedAmount -= amount;
        stakerInfo[msg.sender].rewardDebt = (stakerInfo[msg.sender].stakedAmount * accRewardsPerShare) / 1e24;

        _withdraw(amount);
    }

    function claim() external returns (uint256 rewards) {
        require(isClaimActive, "Claiming is not active yet.");
        require(stakerInfo[msg.sender].stakedAmount > 0 || stakerInfo[msg.sender].accRewards > 0, "No rewards to claim");

        rewards = ((stakerInfo[msg.sender].stakedAmount * accRewardsPerShare) / 1e24) + stakerInfo[msg.sender].accRewards - stakerInfo[msg.sender].rewardDebt;
        stakerInfo[msg.sender].accRewards = 0;
        stakerInfo[msg.sender].rewardDebt = (stakerInfo[msg.sender].stakedAmount * accRewardsPerShare) / 1e24;

        _claim(rewards);
    }

    /**
     * @dev Toggles claimActive open or closed based on admin.
     */
    function setClaimActive(bool _isClaimActive) external onlyOwner {
        isClaimActive = _isClaimActive;
        emit ClaimStatusUpdate(_isClaimActive);
    }

    /**
     * @dev See {IStaking-withdrawAll}.
     */
    function withdrawAll() external returns (uint256 rewards) {
        require(stakerInfo[msg.sender].stakedAmount > 0, "Not enough balance");

        // Ensure the lock-in period has passed
        require(block.timestamp >= interestStartTimestamp + lockInPeriod, "Lock-in period active");

        // Ensure claiming is active
        require(isClaimActive, "Claiming is not active yet");

        // Calculate rewards
        rewards = ((stakerInfo[msg.sender].stakedAmount * accRewardsPerShare) / 1e24) + 
            stakerInfo[msg.sender].accRewards - stakerInfo[msg.sender].rewardDebt;

        // Reset staker's reward tracking
        stakerInfo[msg.sender].accRewards = 0;
        stakerInfo[msg.sender].rewardDebt = 0;

        // Update total staked
        _totalStaked -= stakerInfo[msg.sender].stakedAmount;

        // Delete staker info
        uint256 stakedAmount = stakerInfo[msg.sender].stakedAmount;
        delete stakerInfo[msg.sender];

        // Claim rewards and withdraw staked tokens
        _claim(rewards);
        _withdraw(stakedAmount);
    }

    /**
     * @dev See {IStaking-getReward}.
     
    function getReward(address account) external view returns (uint256) {
        if (_totalStaked == 0 || block.timestamp < interestStartTimestamp) {
            return 0;
        }

        uint256 reward = (block.timestamp - lastRewardTimestamp) * ratePerSecond;
        uint256 rewardsPerShare = accRewardsPerShare + (reward * 1e24) / _totalStaked;
        return
            ((stakerInfo[msg.sender].stakedAmount * rewardsPerShare) / 1e24) +
            stakerInfo[msg.sender].accRewards -
            stakerInfo[msg.sender].rewardDebt;
    }
    */
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

    function _calculateReward(address user) internal view returns (uint256 reward) {
        // If user has no staked amount or rewards are before the interest start
        if (stakerInfo[user].stakedAmount == 0 || block.timestamp < interestStartTimestamp) {
            return 0;
        }

        // Calculate rewards for the period since the last update
        uint256 stakedDuration = block.timestamp > (interestStartTimestamp + lockInPeriod)
            ? (interestStartTimestamp + lockInPeriod) - stakerInfo[user].stakeTimestamp
            : block.timestamp - stakerInfo[user].stakeTimestamp;

        reward = (stakerInfo[user].stakedAmount * ratePerSecond * stakedDuration) / 1e24; // Unscale rewards
        return reward;
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
    * @dev Allows the owner to withdraw all staking tokens in an emergency.
    */
    function emergencyWithdraw() external onlyOwner(){
        uint256 balance = stakingToken.balanceOf(address(this));
        stakingToken.safeTransfer(owner(), balance);
        emit EmergencyWithdraw(owner(), balance);
    }

    /**
    * @dev Updates the rate per second. This might be needed for changing APR or reward structure.
    * @param rate New rate per second.
    */
    function updateRate(uint256 rate) external onlyOwner {
        emit RateUpdate(apr, rate);
        apr = rate;
    }
}
