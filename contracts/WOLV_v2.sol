// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";

/// @title WOLV — WolvCapital Profit Reward Token
/// @notice Fixed supply token. All tokens minted at deployment to treasury.
/// @dev No mint function. No owner. Optional pause via multisig.
/// @custom:website https://wolvcapital.com
/// @custom:bscscan https://bscscan.com/token/0xbcb3d35bcbbd141f1955aaf8f51b48b801b117bf

contract WOLV is ERC20, ERC20Burnable, ERC20Pausable {

    // ─────────────────────────────────────────────
    // CONSTANTS
    // ─────────────────────────────────────────────

    /// @notice Hard cap — 1 billion WOLV minted once at deployment
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Treasury wallet — holds reward pool for investor distributions
    address public immutable treasury;

    /// @notice Multisig wallet — only address that can pause/unpause
    address public immutable multisig;

    // ─────────────────────────────────────────────
    // EVENTS
    // ─────────────────────────────────────────────

    event ProfitDistributed(address indexed investor, uint256 amount);

    // ─────────────────────────────────────────────
    // CONSTRUCTOR
    // ─────────────────────────────────────────────

    /// @param _treasury Wallet that receives the full supply at deployment
    /// @param _multisig Wallet authorized to pause/unpause (use Gnosis Safe)
    constructor(address _treasury, address _multisig)
        ERC20("Wolv Capital", "WOLV")
    {
        require(_treasury != address(0), "WOLV: invalid treasury");
        require(_multisig != address(0), "WOLV: invalid multisig");

        treasury = _treasury;
        multisig = _multisig;

        // Mint entire supply to treasury once — no future minting possible
        _mint(_treasury, TOTAL_SUPPLY);
    }

    // ─────────────────────────────────────────────
    // PAUSE — multisig only, emergency use
    // ─────────────────────────────────────────────

    modifier onlyMultisig() {
        require(msg.sender == multisig, "WOLV: not multisig");
        _;
    }

    /// @notice Pause all transfers — emergency compliance use only
    function pause() external onlyMultisig {
        _pause();
    }

    /// @notice Resume all transfers
    function unpause() external onlyMultisig {
        _unpause();
    }

    // ─────────────────────────────────────────────
    // DECIMALS
    // ─────────────────────────────────────────────

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    // ─────────────────────────────────────────────
    // REQUIRED OVERRIDE
    // ─────────────────────────────────────────────

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Pausable)
    {
        super._update(from, to, value);
    }
}
