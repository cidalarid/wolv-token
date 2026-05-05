// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title WOLV - WolvCapital Profit Token
/// @notice Earned by investors as profits on the WolvCapital platform (wolvcapital.com)
/// @dev ERC20 with mint, burn, pause, and owner controls
contract WOLV is ERC20, ERC20Burnable, ERC20Pausable, Ownable {

    // Maximum supply: 1 billion WOLV (18 decimals)
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10 ** 18;

    // Events
    event ProfitDistributed(address indexed investor, uint256 amount);
    event TokensReclaimed(address indexed investor, uint256 amount);

    constructor() ERC20("Wolv Capital", "WOLV") Ownable(msg.sender) {
        // No initial mint — tokens are minted as investors earn profits
    }

    // ─────────────────────────────────────────────
    // MINT — called by WolvCapital when distributing profits
    // ─────────────────────────────────────────────

    /// @notice Mint WOLV profit tokens to an investor
    /// @param investor The investor's wallet address
    /// @param amount Amount of WOLV to mint (in wei, 18 decimals)
    function distributeProfits(address investor, uint256 amount)
        external
        onlyOwner
    {
        require(investor != address(0), "WOLV: invalid address");
        require(amount > 0, "WOLV: amount must be > 0");
        require(totalSupply() + amount <= MAX_SUPPLY, "WOLV: max supply exceeded");

        _mint(investor, amount);
        emit ProfitDistributed(investor, amount);
    }

    /// @notice Batch mint profits to multiple investors in one tx (gas efficient)
    /// @param investors Array of investor addresses
    /// @param amounts Array of amounts corresponding to each investor
    function distributeProfitsBatch(
        address[] calldata investors,
        uint256[] calldata amounts
    ) external onlyOwner {
        require(investors.length == amounts.length, "WOLV: length mismatch");

        uint256 totalToMint = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalToMint += amounts[i];
        }
        require(totalSupply() + totalToMint <= MAX_SUPPLY, "WOLV: max supply exceeded");

        for (uint256 i = 0; i < investors.length; i++) {
            require(investors[i] != address(0), "WOLV: invalid address");
            require(amounts[i] > 0, "WOLV: amount must be > 0");
            _mint(investors[i], amounts[i]);
            emit ProfitDistributed(investors[i], amounts[i]);
        }
    }

    // ─────────────────────────────────────────────
    // BURN — called when investor redeems/withdraws
    // ─────────────────────────────────────────────

    /// @notice Owner can reclaim (burn) WOLV from an investor on withdrawal
    /// @param investor The investor's wallet address
    /// @param amount Amount to burn
    function reclaimTokens(address investor, uint256 amount)
        external
        onlyOwner
    {
        require(investor != address(0), "WOLV: invalid address");
        require(amount > 0, "WOLV: amount must be > 0");
        require(balanceOf(investor) >= amount, "WOLV: insufficient balance");

        _burn(investor, amount);
        emit TokensReclaimed(investor, amount);
    }

    // ─────────────────────────────────────────────
    // PAUSE — emergency compliance freeze
    // ─────────────────────────────────────────────

    /// @notice Pause all token transfers (compliance/emergency use)
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Resume all token transfers
    function unpause() external onlyOwner {
        _unpause();
    }

    // ─────────────────────────────────────────────
    // VIEW HELPERS
    // ─────────────────────────────────────────────

    /// @notice Remaining supply that can still be minted
    function remainingSupply() external view returns (uint256) {
        return MAX_SUPPLY - totalSupply();
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