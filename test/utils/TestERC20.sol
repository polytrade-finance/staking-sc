// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock token for testing
contract TestERC20 is ERC20 {
    constructor() ERC20("MockToken", "MCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}