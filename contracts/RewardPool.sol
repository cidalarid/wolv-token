
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title RewardPool — Holds WOLV funded by treasury, releases to StakingContract
/// @notice emergencyWithdraw has a 48-hour timelock — no instant drain possible
/// @custom:website https://wolvcapital.com
contract RewardPool {

    // ─────────────────────────────────────────────
    // STATE
    // ─────────────────────────────────────────────

    IERC20  public immutable wolv;
    address public immutable treasury;
    address public immutable multisig;
    address public stakingContract;
    bool    public stakingSet;

    // Timelock for emergency withdraw
    uint256 public constant TIMELOCK_DELAY = 48 hours;
    uint256 public withdrawUnlocksAt;       // 0 = no pending withdrawal
    uint256 public pendingWithdrawAmount;

    // ─────────────────────────────────────────────
    // EVENTS
    // ─────────────────────────────────────────────

    event Funded(address indexed from, uint256 amount);
    event Released(address indexed to, uint256 amount);
    event StakingContractSet(address indexed stakingContract);
    event WithdrawQueued(uint256 amount, uint256 unlocksAt);
    event WithdrawExecuted(uint256 amount);
    event WithdrawCancelled();

    // ─────────────────────────────────────────────
    // CONSTRUCTOR
    // ─────────────────────────────────────────────

    constructor(address _wolv, address _treasury, address _multisig) {
        require(_wolv     != address(0), "RewardPool: invalid wolv");
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

    /// @notice Called once after StakingContract is deployed
    function setStakingContract(address _staking) external onlyMultisig {
        require(!stakingSet, "RewardPool: already set");
        require(_staking != address(0), "RewardPool: invalid address");
        stakingContract = _staking;
        stakingSet = true;
        emit StakingContractSet(_staking);
    }

    // ─────────────────────────────────────────────
    // FUND
    // ─────────────────────────────────────────────

    /// @notice Anyone can fund the pool — treasury approves then calls this
    function fund(uint256 amount) external {
        require(amount > 0, "RewardPool: zero amount");
        wolv.transferFrom(msg.sender, address(this), amount);
        emit Funded(msg.sender, amount);
    }

    // ─────────────────────────────────────────────
    // RELEASE — staking contract only
    // ─────────────────────────────────────────────

    /// @notice StakingContract calls this when user claims rewards
    function release(address to, uint256 amount) external onlyStaking {
        require(amount > 0, "RewardPool: zero amount");
        require(wolv.balanceOf(address(this)) >= amount, "RewardPool: insufficient balance");
        wolv.transfer(to, amount);
        emit Released(to, amount);
    }

    // ─────────────────────────────────────────────
    // TIMELOCK EMERGENCY WITHDRAW — 48hr delay
    // ─────────────────────────────────────────────

    /// @notice Step 1 — queue a withdrawal. Visible on-chain for 48hrs before execution.
    function queueWithdraw(uint256 amount) external onlyMultisig {
        require(amount > 0, "RewardPool: zero amount");
        require(wolv.balanceOf(address(this)) >= amount, "RewardPool: insufficient balance");
        withdrawUnlocksAt     = block.timestamp + TIMELOCK_DELAY;
        pendingWithdrawAmount = amount;
        emit WithdrawQueued(amount, withdrawUnlocksAt);
    }

    /// @notice Step 2 — execute after 48hrs have passed
    function executeWithdraw() external onlyMultisig {
        require(withdrawUnlocksAt != 0, "RewardPool: no queued withdrawal");
        require(block.timestamp >= withdrawUnlocksAt, "RewardPool: timelock active");
        uint256 amt = pendingWithdrawAmount;
        withdrawUnlocksAt     = 0;
        pendingWithdrawAmount = 0;
        wolv.transfer(multisig, amt);
        emit WithdrawExecuted(amt);
    }

    /// @notice Cancel a queued withdrawal
    function cancelWithdraw() external onlyMultisig {
        withdrawUnlocksAt     = 0;
        pendingWithdrawAmount = 0;
        emit WithdrawCancelled();
    }

    // ─────────────────────────────────────────────
    // VIEW
    // ─────────────────────────────────────────────

    function poolBalance() external view returns (uint256) {
        return wolv.balanceOf(address(this));
    }


}