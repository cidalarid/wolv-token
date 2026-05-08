// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IRewardPool {
    function release(address to, uint256 amount) external;
    function poolBalance() external view returns (uint256);
}

/// @title StakingContract — Users stake BNB or BUSD, earn WOLV rewards
/// @notice Plans mirror WolvCapital.com investment tiers
/// @custom:website https://wolvcapital.com
contract StakingContract is ReentrancyGuard {

    // ─────────────────────────────────────────────
    // PLAN DEFINITIONS — mirrors your 4 site plans
    // ─────────────────────────────────────────────

    struct Plan {
        string  name;
        uint256 minStakeUSD;   // in USD cents (e.g. 10000 = $100)
        uint256 lockDays;      // lock period in days
        uint256 apyBps;        // APY in basis points (e.g. 800 = 8%)
        uint256 exitFeeBps;    // exit fee in basis points (e.g. 200 = 2%)
    }

    Plan[4] public plans;

    // ─────────────────────────────────────────────
    // STAKE RECORD
    // ─────────────────────────────────────────────

    enum Token { BNB, BUSD }

    struct Stake {
        uint8   planId;
        Token   token;
        uint256 amountUSD;     // USD value at time of stake (18 decimals)
        uint256 stakedAt;
        uint256 unlocksAt;
        bool    claimed;
        bool    active;
    }

    // user => stakeId => Stake
    mapping(address => Stake[]) public stakes;

    // ─────────────────────────────────────────────
    // STATE
    // ─────────────────────────────────────────────

    address public immutable multisig;
    address public immutable busd;          // BUSD token on BSC
    IRewardPool public immutable rewardPool;

    // BNB/USD price — updated by multisig (simple oracle)
    uint256 public bnbPriceUSD;             // 18 decimals e.g. 600e18 = $600

    bool public paused;

    // ─────────────────────────────────────────────
    // EVENTS
    // ─────────────────────────────────────────────

    event Staked(address indexed user, uint8 planId, uint256 amountUSD, Token token, uint256 stakeId);
    event Claimed(address indexed user, uint256 stakeId, uint256 wolvAmount);
    event EarlyExit(address indexed user, uint256 stakeId, uint256 feeBps);
    event BnbPriceUpdated(uint256 newPrice);

    // ─────────────────────────────────────────────
    // CONSTRUCTOR
    // ─────────────────────────────────────────────

    constructor(
        address _multisig,
        address _busd,
        address _rewardPool,
        uint256 _bnbPriceUSD   // initial BNB price e.g. 600e18
    ) {
        require(_multisig    != address(0), "invalid multisig");
        require(_busd        != address(0), "invalid busd");
        require(_rewardPool  != address(0), "invalid pool");

        multisig    = _multisig;
        busd        = _busd;
        rewardPool  = IRewardPool(_rewardPool);
        bnbPriceUSD = _bnbPriceUSD;

        // Pioneer   — $100 min,   90 days,  8% APY,  2% exit fee
        plans[0] = Plan("Pioneer",   10_000, 90,  800,  200);
        // Vanguard  — $1000 min, 150 days, 12% APY, 2.5% exit fee
        plans[1] = Plan("Vanguard",  100_000, 150, 1200, 250);
        // Horizon   — $5000 min, 180 days, 18% APY,  3% exit fee
        plans[2] = Plan("Horizon",   500_000, 180, 1800, 300);
        // Summit VIP— $15000 min,365 days, 25% APY, 3.5% exit fee
        plans[3] = Plan("SummitVIP", 1_500_000, 365, 2500, 350);
    }

    // ─────────────────────────────────────────────
    // MODIFIERS
    // ─────────────────────────────────────────────

    modifier onlyMultisig() {
        require(msg.sender == multisig, "not multisig");
        _;
    }

    modifier notPaused() {
        require(!paused, "paused");
        _;
    }

    // ─────────────────────────────────────────────
    // STAKE — BNB
    // ─────────────────────────────────────────────

    /// @notice Stake BNB into a plan
    /// @param planId 0=Pioneer 1=Vanguard 2=Horizon 3=SummitVIP
    function stakeBNB(uint8 planId) external payable notPaused nonReentrant {
        require(planId < 4, "invalid plan");
        require(msg.value > 0, "zero amount");

        uint256 usdValue = (msg.value * bnbPriceUSD) / 1e18;
        Plan memory p = plans[planId];
        require(usdValue >= p.minStakeUSD * 1e14, "below minimum");

        _createStake(planId, Token.BNB, usdValue);
    }

    // ─────────────────────────────────────────────
    // STAKE — BUSD
    // ─────────────────────────────────────────────

    /// @notice Stake BUSD into a plan (approve this contract first)
    function stakeBUSD(uint8 planId, uint256 amount) external notPaused nonReentrant {
        require(planId < 4, "invalid plan");
        require(amount > 0, "zero amount");

        Plan memory p = plans[planId];
        // BUSD is 18 decimals, minStakeUSD is in cents * 1e14
        require(amount >= p.minStakeUSD * 1e14, "below minimum");

        // Transfer BUSD from user to this contract
        (bool ok,) = busd.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), amount)
        );
        require(ok, "BUSD transfer failed");

        _createStake(planId, Token.BUSD, amount);
    }

    // ─────────────────────────────────────────────
    // INTERNAL — create stake record
    // ─────────────────────────────────────────────

    function _createStake(uint8 planId, Token token, uint256 amountUSD) internal {
        Plan memory p = plans[planId];
        uint256 stakeId = stakes[msg.sender].length;

        stakes[msg.sender].push(Stake({
            planId:    planId,
            token:     token,
            amountUSD: amountUSD,
            stakedAt:  block.timestamp,
            unlocksAt: block.timestamp + (p.lockDays * 1 days),
            claimed:   false,
            active:    true
        }));

        emit Staked(msg.sender, planId, amountUSD, token, stakeId);
    }

    // ─────────────────────────────────────────────
    // CLAIM REWARDS — after lock period
    // ─────────────────────────────────────────────

    /// @notice Claim WOLV rewards after lock period expires
    function claimRewards(uint256 stakeId) external notPaused nonReentrant {
        Stake storage s = stakes[msg.sender][stakeId];
        require(s.active, "not active");
        require(!s.claimed, "already claimed");
        require(block.timestamp >= s.unlocksAt, "still locked");

        s.claimed = true;
        s.active  = false;

        uint256 wolvReward = _calcReward(s);
        rewardPool.release(msg.sender, wolvReward);

        emit Claimed(msg.sender, stakeId, wolvReward);
    }

    // ─────────────────────────────────────────────
    // EARLY EXIT — penalty applies
    // ─────────────────────────────────────────────

    /// @notice Exit before lock period — fee deducted from principal
    function earlyExit(uint256 stakeId) external nonReentrant {
        Stake storage s = stakes[msg.sender][stakeId];
        require(s.active, "not active");
        require(!s.claimed, "already claimed");
        require(block.timestamp < s.unlocksAt, "use claimRewards");

        s.active  = false;
        s.claimed = true;

        Plan memory p = plans[s.planId];
        uint256 fee = (s.amountUSD * p.exitFeeBps) / 10_000;
        uint256 returnAmt = s.amountUSD - fee;

        // Return principal minus fee
        if (s.token == Token.BNB) {
            uint256 bnbReturn = (returnAmt * 1e18) / bnbPriceUSD;
            (bool sent,) = msg.sender.call{value: bnbReturn}("");
            require(sent, "BNB return failed");
        } else {
            (bool ok,) = busd.call(
                abi.encodeWithSignature("transfer(address,uint256)", msg.sender, returnAmt)
            );
            require(ok, "BUSD return failed");
        }

        emit EarlyExit(msg.sender, stakeId, p.exitFeeBps);
    }

    // ─────────────────────────────────────────────
    // REWARD CALCULATION
    // ─────────────────────────────────────────────

    /// @notice Calculate WOLV reward — 1 WOLV = $1, APY applied pro-rata
    function _calcReward(Stake memory s) internal view returns (uint256) {
        Plan memory p = plans[s.planId];
        // Pro-rata reward for exact lock duration
        // reward = principal * APY * days / 365 / 10000
        uint256 reward = (s.amountUSD * p.apyBps * p.lockDays) / (365 * 10_000);
        return reward; // WOLV has 18 decimals, amountUSD has 18 decimals → 1:1
    }

    // ─────────────────────────────────────────────
    // VIEW FUNCTIONS
    // ─────────────────────────────────────────────

    function getStake(address user, uint256 stakeId) external view returns (Stake memory) {
        return stakes[user][stakeId];
    }

    function getStakeCount(address user) external view returns (uint256) {
        return stakes[user].length;
    }

    function pendingReward(address user, uint256 stakeId) external view returns (uint256) {
        return _calcReward(stakes[user][stakeId]);
    }

    function timeUntilUnlock(address user, uint256 stakeId) external view returns (uint256) {
        Stake memory s = stakes[user][stakeId];
        if (block.timestamp >= s.unlocksAt) return 0;
        return s.unlocksAt - block.timestamp;
    }

    // ─────────────────────────────────────────────
    // ADMIN — multisig only
    // ─────────────────────────────────────────────

    function updateBnbPrice(uint256 newPrice) external onlyMultisig {
        bnbPriceUSD = newPrice;
        emit BnbPriceUpdated(newPrice);
    }

    function setPaused(bool _paused) external onlyMultisig {
        paused = _paused;
    }

    // Allow contract to receive BNB
    receive() external payable {}
}