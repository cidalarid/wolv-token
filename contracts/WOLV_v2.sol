// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/// @title WOLV — WolvCapital Profit Reward Token
/// @notice Fixed supply. 1 billion minted once to treasury. No mint. No pause. No owner.
/// @custom:website https://wolvcapital.com
contract WOLV is ERC20, ERC20Burnable {

    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** 18;
    address public immutable treasury;

    constructor(address _treasury, address)
        ERC20("Wolv Capital", "WOLV")
    {
        require(_treasury != address(0), "WOLV: invalid treasury");
        treasury = _treasury;
        _mint(_treasury, TOTAL_SUPPLY);
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }
}
