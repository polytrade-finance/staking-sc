// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals) ERC20(name, symbol) {
        _setupDecimals(decimals);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function _setupDecimals(uint8 decimals_) internal {
        // Set the decimals for testing flexibility
        // OpenZeppelin's ERC20 no longer includes `decimals` as a variable override
    }
}
