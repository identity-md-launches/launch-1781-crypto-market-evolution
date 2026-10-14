// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Crypto Market Evolution
/// @notice An immutable ERC-20 with one billion tokens and 18 decimals.
/// @dev The entire supply is minted once to the immediate deployer. When a factory
/// deploys this contract, the factory receives the supply and handles distribution.
contract CMEToken is ERC20 {
    /// @notice Fixed supply in the smallest token units (1 CME = 10^18 units).
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Mints the whole supply to msg.sender; there are no constructor arguments.
    constructor() ERC20("Crypto Market Evolution", "CME") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
