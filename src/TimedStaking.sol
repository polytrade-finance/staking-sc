// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IStaking} from "contracts/interface/IStaking.sol";

contract TimedStaking is Ownable, IStaking {
    using SafeERC20 for IERC20;

    IERC20 public stakingToken;
    IERC20 public rewardToken;
    uint256 public ratePerSecond;
    uint256 public lastRewardTimestamp;
    uint256 public accRewardsPerShare;
    uint256 public maxStake;      // Maximum total tokens in pool
    uint256 public lockInPeriod;  // Lock-in period for pool
    uint256 public apr;           // Annual Percentage Rate
    uint256 private _totalStaked;
    bool public isClaimActive;
    bool public depositsOpen = true;

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

        // Calculate a fixed rate per second based on APR and maxStake
        ratePerSecond = (apr * maxStake) / (365 days * 1e4);
    }

    function stake(uint256 amount) external {
        require(block.timestamp < interestStartTimestamp, "Deposits closed");
        require(depositsOpen, "Deposits are currently closed");
        require(_totalStaked + amount <= maxStake, "Exceeds max stake limit");

        StakerInfo storage staker = stakerInfo[msg.sender];

        // Accumulate pending rewards for the staker only if after interest start
        if (block.timestamp >= interestStartTimestamp && staker.stakedAmount > 0) {
            uint256 pending = ((staker.stakedAmount * accRewardsPerShare) / 1e24) - staker.rewardDebt;
            staker.accRewards += pending;
        }

        _totalStaked += amount;
        staker.stakedAmount += amount;
        staker.rewardDebt = (staker.stakedAmount * accRewardsPerShare) / 1e24;
        staker.stakeTimestamp = block.timestamp;

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Stake(msg.sender, amount);

        // Check if the pool has reached maxStake
        if (_totalStaked >= maxStake) {
            depositsOpen = false;
        }
    }

    function withdraw(uint256 amount) external {
        StakerInfo storage staker = stakerInfo[msg.sender];
        require(staker.stakedAmount >= amount, "Not enough balance");
        require(block.timestamp >= interestStartTimestamp + lockInPeriod, "Lock-in period active");

        uint256 pending = ((staker.stakedAmount * accRewardsPerShare) / 1e24) - staker.rewardDebt;
        staker.accRewards += pending;
        _totalStaked -= amount;
        staker.stakedAmount -= amount;
        staker.rewardDebt = (staker.stakedAmount * accRewardsPerShare) / 1e24;

        _withdraw(amount);
    }

    function claim() external returns (uint256 rewards) {
        require(isClaimActive, "Claiming is not active yet.");
        StakerInfo storage staker = stakerInfo[msg.sender];
        require(staker.stakedAmount > 0 || staker.accRewards > 0, "No rewards to claim");

        rewards = ((staker.stakedAmount * accRewardsPerShare) / 1e24) + staker.accRewards - staker.rewardDebt;
        staker.accRewards = 0;
        staker.rewardDebt = (staker.stakedAmount * accRewardsPerShare) / 1e24;

        _claim(rewards);
    }

     /**
     * @dev Toggles deposits open or closed based on admin.
     */
    function toggleDeposits(bool _status) external onlyOwner {
        depositsOpen = _status;
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
        StakerInfo storage staker = stakerInfo[msg.sender];
        require(staker.stakedAmount > 0, "Not enough balance");

        // Ensure the lock-in period has passed
        require(block.timestamp >= interestStartTimestamp + lockInPeriod, "Lock-in period active");

        // Ensure claiming is active
        require(isClaimActive, "Claiming is not active yet");

        // Calculate rewards
        rewards = ((staker.stakedAmount * accRewardsPerShare) / 1e24) + staker.accRewards - staker.rewardDebt;

        // Reset staker's reward tracking
        staker.accRewards = 0;
        staker.rewardDebt = 0;

        // Update total staked
        _totalStaked -= staker.stakedAmount;

        // Delete staker info
        uint256 stakedAmount = staker.stakedAmount;
        delete stakerInfo[msg.sender];

        // Claim rewards and withdraw staked tokens
        _claim(rewards);
        _withdraw(stakedAmount);
    }

    /**
     * @dev See {IStaking-getReward}.
     */
    function getReward(address account) external view returns (uint256) {
        if (_totalStaked == 0 || block.timestamp < interestStartTimestamp) {
            return 0;
        }
        StakerInfo memory staker = stakerInfo[account];
        uint256 reward = (block.timestamp - lastRewardTimestamp) * ratePerSecond;
        uint256 rewardsPerShare = accRewardsPerShare + (reward * 1e24) / _totalStaked;
        return
            ((staker.stakedAmount * rewardsPerShare) / 1e24) +
            staker.accRewards -
            staker.rewardDebt;
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
        ratePerSecond = rate;
        emit RateUpdate(apr, rate);
    }

     /**
     * @dev See {IStaking-getAPR}.
     */
    function getAPR() external view returns (uint256) {
        return apr;
    }
    uint256 public interestStartTimestamp; // Interest start time in EPOCH

    /**
     * @dev See {IStaking-getInterestStartTimestamp}.
     */
    function getInterestStartTimestamp() external view returns (uint256) {
        return interestStartTimestamp;
    }
}
