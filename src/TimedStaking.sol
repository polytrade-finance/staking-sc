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
    uint256 public interestStartTimestamp; // Interest start time in EPOCH
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
        uint256 interestStartEpoch_,
        address owner_
    ) Ownable(owner_) {
        stakingToken = IERC20(stakingToken_);
        rewardToken = IERC20(rewardToken_);
        maxStake = maxStake_;
        lockInPeriod = lockInPeriod_;
        apr = apr_;
        interestStartTimestamp = interestStartTimestamp_;
        isClaimActive = false;

        // Calculate initial rate per second based on APR and maxStake
        ratePerSecond = (apr * maxStake) / (365 days * 1e4); 
    }

    function stake(uint256 amount) external {
        require(block.timestamp < interestStartTimestamp, "Deposits closed");
        require(depositsOpen, "Deposits are currently closed");
        require(_totalStaked + amount <= maxStake, "Exceeds max stake limit");

        StakerInfo storage staker = stakerInfo[msg.sender];

        // Accumulate pending rewards for the staker
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

        // Adjust rate per second dynamically
        ratePerSecond = (_totalStaked * apr) / (365 days * 1e4);

        // Check if the pool has reached maxStake
        if (_totalStaked >= maxStake) {
            depositsOpen = false;
        }
    }

    function withdraw(uint256 amount) external {
        StakerInfo storage staker = stakerInfo[msg.sender];
        require(staker.stakedAmount >= amount, "Not enough balance");
        require(block.timestamp >= interestStartTimestamp + lockInPeriod, "Lock-in period active");

        _updatePool();

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

        _updatePool();

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
        StakerInfo memory staker = stakerInfo[msg.sender];
        if (staker.stakedAmount == 0) {
            revert NotEnoughBalance();
        }
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

    function _updatePool() private {
        if (block.timestamp <= lastRewardTimestamp || _totalStaked == 0) {
            return;
        }

        uint256 reward = (block.timestamp - lastRewardTimestamp) * ratePerSecond;
        accRewardsPerShare += (reward * 1e24) / _totalStaked;
        lastRewardTimestamp = block.timestamp;
    }
}
