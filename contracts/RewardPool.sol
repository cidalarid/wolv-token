// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title RewardPool — Holds WOLV tokens funded by treasury, releases to StakingContract
/// @notice Treasury sends WOLV here periodically. Only StakingContract can withdraw.
/// @custom:website https://wolvcapital.com
contract RewardPool {

    // ─────────────────────────────────────────────
    // STATE
    // ─────────────────────────────────────────────

    IERC20 public immutable wolv;           // WOLV token address
    address public immutable treasury;      // Can fund the pool
    address public immutable multisig;      // Emergency controls
    address public stakingContract;         // Set once after staking deploy

    bool public stakingSet;

    // ─────────────────────────────────────────────
    // EVENTS
    // ─────────────────────────────────────────────

    event Funded(address indexed from, uint256 amount);
    event Released(address indexed to, uint256 amount);
    event StakingContractSet(address indexed stakingContract);

    // ─────────────────────────────────────────────
    // CONSTRUCTOR
    // ─────────────────────────────────────────────

    constructor(address _wolv, address _treasury, address _multisig) {
        require(_wolv != address(0), "RewardPool: invalid wolv");
        require(_treasury != address(0), "RewardPool: invalid treasury");
        require(_multisig != address(0), "RewardPool: invalid multisig");

        wolv     = IERC20(_wolv);
        treasury = _treasury;
        multisig = _multisig;
    }

    // ─────────────────────────────────────────────
    // MODIFIERS
    // ─────────────────────────────────────────────

    modifier onlyMultisig() {
        require(msg.sender == multisig, "RewardPool: not multisig");
        _;
    }

    modifier onlyStaking() {
        require(msg.sender == stakingContract, "RewardPool: not staking");
        _;
    }

    // ─────────────────────────────────────────────
    // SETUP
    // ─────────────────────────────────────────────

    function setStakingContract(address _staking) external onlyMultisig {
        require(!stakingSet, "RewardPool: already set");
        require(_staking != address(0), "RewardPool: invalid address");
        stakingContract = _staking;
        stakingSet = true;
        emit StakingContractSet(_staking);
    }

    // ─────────────────────────────────────────────
    // FUND & RELEASE
    // ─────────────────────────────────────────────

    function fund(uint256 amount) external {
        require(amount > 0, "RewardPool: zero amount");
        wolv.transferFrom(msg.sender, address(this), amount);
        emit Funded(msg.sender, amount);
    }

    function release(address to, uint256 amount) external onlyStaking {
        require(amount > 0, "RewardPool: zero amount");
        require(wolv.balanceOf(address(this)) >= amount, "RewardPool: insufficient balance");
        wolv.transfer(to, amount);
        emit Released(to, amount);
    }

    // ─────────────────────────────────────────────
    // VIEW & EMERGENCY
    // ─────────────────────────────────────────────

    function poolBalance() external view returns (uint256) {
        return wolv.balanceOf(address(this));
    }

    function emergencyWithdraw(uint256 amount) external onlyMultisig {
        wolv.transfer(multisig, amount);
    }
}