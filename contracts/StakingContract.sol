// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRewardPool {
    function release(address to, uint256 amount) external;
    function poolBalance() external view returns (uint256);
}

/// @title StakingContract — Users stake BNB or BUSD, earn WOLV rewards
/// @notice Plans mirror WolvCapital.com investment tiers
/// @custom:website https://wolvcapital.com
contract StakingContract is ReentrancyGuard {

    // ─────────────────────────────────────────────
    // PLAN DEFINITIONS
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
        uint256 amountToken;   // CRITICAL FIX: exact BNB or BUSD deposited
        uint256 amountUSD;     // USD value at time of stake for reward math
        uint256 stakedAt;
        uint256 unlocksAt;
        bool    claimed;
        bool    active;
    }

    mapping(address => Stake[]) public stakes;

    // ─────────────────────────────────────────────
    // STATE
    // ─────────────────────────────────────────────

    address public immutable multisig;
    address public immutable busd;
    IRewardPool public immutable rewardPool;

    uint256 public bnbPriceUSD; // 18 decimals e.g. 600e18 = $600
    bool public paused;

    // ─────────────────────────────────────────────
    // EVENTS
    // ─────────────────────────────────────────────

    event Staked(address indexed user, uint8 planId, uint256 amountUSD, Token token, uint256 stakeId);
    event Claimed(address indexed user, uint256 stakeId, uint256 wolvAmount, uint256 principalReturned);
    event EarlyExit(address indexed user, uint256 stakeId, uint256 feeBps);
    event BnbPriceUpdated(uint256 newPrice);

    // ─────────────────────────────────────────────
    // CONSTRUCTOR
    // ─────────────────────────────────────────────

    constructor(
        address _multisig,
        address _busd,
        address _rewardPool,
        uint256 _bnbPriceUSD 
    ) {
        require(_multisig    != address(0), "invalid multisig");
        require(_busd        != address(0), "invalid busd");
        require(_rewardPool  != address(0), "invalid pool");

        multisig    = _multisig;
        busd        = _busd;
        rewardPool  = IRewardPool(_rewardPool);
        bnbPriceUSD = _bnbPriceUSD;

        plans[0] = Plan("Pioneer",   10_000, 90,  800,  200);
        plans[1] = Plan("Vanguard",  100_000, 150, 1200, 250);
        plans[2] = Plan("Horizon",   500_000, 180, 1800, 300);
        plans[3] = Plan("SummitVIP", 1_500_000, 365, 2500, 350);
    }

    modifier onlyMultisig() {
        require(msg.sender == multisig, "not multisig");
        _;
    }

    modifier notPaused() {
        require(!paused, "paused");
        _;
    }

    // ─────────────────────────────────────────────
    // STAKE
    // ─────────────────────────────────────────────

    function stakeBNB(uint8 planId) external payable notPaused nonReentrant {
        require(planId < 4, "invalid plan");
        require(msg.value > 0, "zero amount");

        uint256 usdValue = (msg.value * bnbPriceUSD) / 1e18;
        require(usdValue >= plans[planId].minStakeUSD * 1e14, "below minimum");

        _createStake(planId, Token.BNB, msg.value, usdValue);
    }

    function stakeBUSD(uint8 planId, uint256 amount) external notPaused nonReentrant {
        require(planId < 4, "invalid plan");
        require(amount > 0, "zero amount");
        require(amount >= plans[planId].minStakeUSD * 1e14, "below minimum");

        IERC20(busd).transferFrom(msg.sender, address(this), amount);
        _createStake(planId, Token.BUSD, amount, amount);
    }

    function _createStake(uint8 planId, Token token, uint256 amountToken, uint256 amountUSD) internal {
        Plan memory p = plans[planId];
        uint256 stakeId = stakes[msg.sender].length;

        stakes[msg.sender].push(Stake({
            planId:      planId,
            token:       token,
            amountToken: amountToken,
            amountUSD:   amountUSD,
            stakedAt:    block.timestamp,
            unlocksAt:   block.timestamp + (p.lockDays * 1 days),
            claimed:     false,
            active:      true
        }));

        emit Staked(msg.sender, planId, amountUSD, token, stakeId);
    }

    // ─────────────────────────────────────────────
    // CLAIM & EXIT (CRITICAL FIXES APPLIED)
    // ─────────────────────────────────────────────

    function claimRewards(uint256 stakeId) external notPaused nonReentrant {
        Stake storage s = stakes[msg.sender][stakeId];
        require(s.active, "not active");
        require(!s.claimed, "already claimed");
        require(block.timestamp >= s.unlocksAt, "still locked");

        s.claimed = true;
        s.active  = false;

        // 1. Send WOLV Reward
        uint256 wolvReward = _calcReward(s);
        rewardPool.release(msg.sender, wolvReward);

        // 2. RETURN PRINCIPAL (Fix applied)
        if (s.token == Token.BNB) {
            (bool sent,) = msg.sender.call{value: s.amountToken}("");
            require(sent, "BNB return failed");
        } else {
            require(IERC20(busd).transfer(msg.sender, s.amountToken), "BUSD return failed");
        }

        emit Claimed(msg.sender, stakeId, wolvReward, s.amountToken);
    }

    function earlyExit(uint256 stakeId) external nonReentrant {
        Stake storage s = stakes[msg.sender][stakeId];
        require(s.active, "not active");
        require(!s.claimed, "already claimed");
        require(block.timestamp < s.unlocksAt, "use claimRewards");

        s.active  = false;
        s.claimed = true;

        Plan memory p = plans[s.planId];
        
        // Fee deducted from original exact token amount, avoiding oracle drain
        uint256 feeToken = (s.amountToken * p.exitFeeBps) / 10_000;
        uint256 returnToken = s.amountToken - feeToken;

        if (s.token == Token.BNB) {
            (bool sent,) = msg.sender.call{value: returnToken}("");
            require(sent, "BNB return failed");
        } else {
            require(IERC20(busd).transfer(msg.sender, returnToken), "BUSD return failed");
        }

        emit EarlyExit(msg.sender, stakeId, p.exitFeeBps);
    }

    // ─────────────────────────────────────────────
    // REWARD CALCULATION
    // ─────────────────────────────────────────────

    function _calcReward(Stake memory s) internal view returns (uint256) {
        Plan memory p = plans[s.planId];
        return (s.amountUSD * p.apyBps * p.lockDays) / (365 * 10_000);
    }

    // ─────────────────────────────────────────────
    // ADMIN FUNCTIONS (FEES & SWEEP)
    // ─────────────────────────────────────────────

    function updateBnbPrice(uint256 newPrice) external onlyMultisig {
        bnbPriceUSD = newPrice;
        emit BnbPriceUpdated(newPrice);
    }

    function setPaused(bool _paused) external onlyMultisig {
        paused = _paused;
    }

    // Sweep collected early exit fees to treasury
    function sweepFees() external onlyMultisig {
        uint256 bnbBalance = address(this).balance;
        if (bnbBalance > 0) {
            (bool sent,) = multisig.call{value: bnbBalance}("");
            require(sent, "Sweep BNB failed");
        }
        
        uint256 busdBalance = IERC20(busd).balanceOf(address(this));
        if (busdBalance > 0) {
            IERC20(busd).transfer(multisig, busdBalance);
        }
    }

    receive() external payable {}
}