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
contract TimedStaking is Ownable, IStaking {
    using SafeERC20 for IERC20;

    IERC20 public stakingToken;
    IERC20 public rewardToken;
    uint256 public ratePerSecond;
    uint256 public lastRewardTimestamp;
    uint256 public accRewardsPerShare;
    uint256 public maxStake;      // Maximum total tokens in pool
    uint256 public lockInPeriod;  // Lock-in period for each staker
    uint256 public apr;           // Annual Percentage Rate
    uint256 private _totalStaked;
    bool public stakingStarted;
    bool public isClaimActive;

    mapping(address => StakerInfo) public stakerInfo;
    
    /**
     * @param stakingToken_ address of ERC20 underlying token
     * @param rewardToken_ address of ERC20 reward token
     * @param maxStake_ is max stake amount per staker
     * @param lockInPeriod_ is lock-in period for pool
     * @param apr_ is annual percentage rate for reward distribution
     * @param owner_, address of the owner of contract to update rate
     */
    constructor(
        address stakingToken_,
        address rewardToken_,
        uint256 maxStake_,
        uint256 lockInPeriod_,
        uint256 apr_,
        address owner_
    ) Ownable(owner_) {
        stakingToken = IERC20(stakingToken_);
        rewardToken = IERC20(rewardToken_);
        maxStake = maxStake_;
        lockInPeriod = lockInPeriod_;
        apr = apr_;
        isClaimActive = false;  // Initialize claim as in active

        // Calculate rate per second based on APR and max cap
        //TODO
        ratePerSecond = (apr * maxStake) / (365 days); // APR, calculated per second
    }

    /**
     * @dev Stake function with lock-in and max cap per staker.
     */
    function stake(uint256 amount) external {
        require(_totalStaked + amount <= maxStake, "Exceeds max stake limit");

        StakerInfo storage staker = stakerInfo[msg.sender];
        _updatePool();

        if (staker.stakedAmount == 0) {
            staker.stakeTimestamp = block.timestamp;
        }
        if (staker.stakedAmount > 0) {
            uint256 pending = ((staker.stakedAmount * accRewardsPerShare) / 1e24) - staker.rewardDebt;
            staker.accRewards += pending;
        }

        _totalStaked += amount;
        staker.stakedAmount += amount;
        staker.rewardDebt = (staker.stakedAmount * accRewardsPerShare) / 1e24;
        staker.stakeTimestamp = block.timestamp;

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Stake(msg.sender, amount);

        if (!stakingStarted) {
            stakingStarted = true;
            lastRewardTimestamp = block.timestamp;
        }
        // Dynamically adjust the rate per second based on APR and total staked
        ratePerSecond = (_totalStaked * apr) / (365 days * 1e4);
    }

    /**
     * @dev See {IStaking-withdraw}.
     */
    function withdraw(uint256 amount) external {
        StakerInfo storage staker = stakerInfo[msg.sender];
        require(staker.stakedAmount >= amount, "Not enough balance");
        require(block.timestamp >= staker.stakeTimestamp + lockInPeriod, "Lock-in period active");

        _updatePool();

        uint256 pending = ((staker.stakedAmount * accRewardsPerShare) / 1e24) - staker.rewardDebt;
        staker.accRewards += pending;
        _totalStaked -= amount;
        staker.stakedAmount -= amount;
        staker.rewardDebt = (staker.stakedAmount * accRewardsPerShare) / 1e24;

        _withdraw(amount);
    }

    /**
     * @dev See {IStaking-claim}.
     */
    function claim() external returns (uint256 rewards) {
        require(isClaimActive, "Claiming is disabled");
        StakerInfo storage staker = stakerInfo[msg.sender];
        require(staker.stakedAmount > 0 || staker.accRewards > 0, "No rewards to claim");

        _updatePool();

        rewards =
            ((staker.stakedAmount * accRewardsPerShare) / 1e24) +
            staker.accRewards -
            staker.rewardDebt;
        staker.accRewards = 0;
        staker.rewardDebt = (staker.stakedAmount * accRewardsPerShare) / 1e24;

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

        rewards =
            ((staker.stakedAmount * accRewardsPerShare) / 1e24) +
            staker.accRewards -
            staker.rewardDebt;
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

    function setClaimActive(bool _isClaimActive) external onlyOwner {
        isClaimActive = _isClaimActive;
        emit ClaimStatusUpdate(_isClaimActive);
    }

    /**
     * @dev See {IStaking-getReward}.
     */
    function getReward(address account) external view returns (uint256) {
        if (_totalStaked == 0) {
            return 0;
        }
        StakerInfo memory staker = stakerInfo[account];

        uint256 reward = (block.timestamp - lastRewardTimestamp) *
            ratePerSecond;
        uint256 rewardsPerShare = accRewardsPerShare +
            (reward * 1e24) /
            _totalStaked;

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

        uint256 reward = (block.timestamp - lastRewardTimestamp) *
            ratePerSecond;

        accRewardsPerShare += (reward * 1e24) / _totalStaked;
        lastRewardTimestamp = block.timestamp;
    }

    function getStakerInfo(address account) external view returns (StakerInfo memory) {
        return stakerInfo[account];
    }
}
