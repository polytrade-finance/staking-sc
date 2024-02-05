// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IStaking {
    struct StakerInfo {
        uint256 stakedAmount;
        uint256 rewardDebt;
        uint256 accRewards;
    }

    event Deposit(address indexed staker, uint256 amount);
    event Withdraw(address indexed staker, uint256 amount);
    event Claim(address indexed staker, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 amount
    );
}
