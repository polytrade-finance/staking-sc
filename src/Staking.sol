// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStaking} from "contracts/interface/IStaking.sol";

contract Staking {
    using SafeERC20 for IERC20;

    struct StakerInfo {
        uint256 stakedAmount;
        uint256 debtReward;
        uint256 accumulatedRewards;
        uint256 lastUpdate;
    }

    IERC20 public stakingToken;
    IERC20 public rewardToken;
    uint256 public ratePerSecond;

    mapping(address => StakerInfo) public stakerInfo;

    constructor(
        address stakingToken_,
        address rewardToken_,
        uint256 ratePerSecond_
    ) {
        stakingToken = IERC20(stakingToken_);
        rewardToken = IERC20(rewardToken_);
        ratePerSecond = ratePerSecond_;
    }
}
