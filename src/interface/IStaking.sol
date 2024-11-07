// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IStaking {
    struct StakerInfo {
        uint256 stakedAmount;
        uint256 rewardDebt;
        uint256 accRewards;
    }

    event Stake(address indexed staker, uint256 amount);
    event Withdraw(address indexed staker, uint256 amount);
    event Claim(address indexed staker, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event RateUpdate(uint256 oldRate, uint256 newRate);

    error NotEnoughBalance();
    error NoRewards();

    /**
     * @dev Stake the amount of staking token to the pool
     * @dev staker should have approved contract to transfer the tokens
     * @dev staker should have the amount in staking token balance
     * @param amount, number of tokens to stake
     */
    function stake(uint256 amount) external;

    /**
     * @dev Withdraw the staked amount of tokens only for the caller
     * @dev staker should have the amount staked before
     * @param amount, number of tokens to withdraw
     */
    function withdraw(uint256 amount) external;

    /**
     * @dev Claim the time weighted accumulated rewards for the caller
     * @dev staker should have either pending reward or staked an amount
     * @dev contract should have enough balance to transfer the rewards
     * @return the amount of claimed rewards
     */
    function claim() external returns (uint256);

    /**
     * @dev Withdraws all staked amount with all rewards
     * @dev contract should have enough balance to transfer the rewards
     * @dev staker should have the amount staked before
     * @return the amount of claimed rewards
     */
    function withdrawAll() external returns (uint256);

    /**
     * @dev Transfer the staked amount to the staker without any rewards
     * @dev staker should have the amount staked before
     */
    function emergencyWithdraw() external;

    /**
     * @dev Updates rate per second for the rewards
     * @param rate new amount of rate
     */
    function updateRate(uint256 rate) external;
}
