// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Minimal Chainlink price feed interface
interface AggregatorV3Interface {
    function latestRoundData() external view returns (
        uint80 roundId, int256 answer, uint256 startedAt,
        uint256 updatedAt, uint80 answeredInRound
    );
    function decimals() external view returns (uint8);
}

interface IRewardPool {
    function release(address to, uint256 amount) external;
    function poolBalance() external view returns (uint256);
}

/// @title StakingContract — Users stake BNB or BUSD, earn WOLV rewards
/// @notice Plans mirror WolvCapital.com investment tiers. BNB price via Chainlink.
/// @custom:website https://wolvcapital.com
contract StakingContract is ReentrancyGuard {

    // ─────────────────────────────────────────────
    // CHAINLINK — BNB/USD on BSC Mainnet
    // ─────────────────────────────────────────────

    AggregatorV3Interface public immutable bnbFeed;
    // BSC Mainnet: 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE

    // ─────────────────────────────────────────────
    // PLAN DEFINITIONS
    // ─────────────────────────────────────────────

    struct Plan {
        string  name;
        uint256 minStakeUSD;  // 8 decimals to match Chainlink (e.g. 10000_00000000 = $100)
        uint256 lockDays;
        uint256 apyBps;       // basis points e.g. 800 = 8%
        uint256 exitFeeBps;   // basis points e.g. 200 = 2%
    }

    Plan[4] public plans;

    // ─────────────────────────────────────────────
    // STAKE RECORD
    // ─────────────────────────────────────────────

    enum Token { BNB, BUSD }

    struct Stake {
        uint8   planId;
        Token   token;
        uint256 amountUSD;   // 8 decimals (Chainlink units)
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
    bool public paused;

    // ─────────────────────────────────────────────
    // EVENTS
    // ─────────────────────────────────────────────

    event Staked(address indexed user, uint8 planId, uint256 amountUSD, Token token, uint256 stakeId);
    event Claimed(address indexed user, uint256 stakeId, uint256 wolvAmount);
    event EarlyExit(address indexed user, uint256 stakeId, uint256 feeBps);

    // ─────────────────────────────────────────────
    // CONSTRUCTOR
    // ─────────────────────────────────────────────

    constructor(
        address _multisig,
        address _busd,
        address _rewardPool,
        address _bnbFeed   // 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE
    ) {
        require(_multisig   != address(0), "invalid multisig");
        require(_busd       != address(0), "invalid busd");
        require(_rewardPool != address(0), "invalid pool");
        require(_bnbFeed    != address(0), "invalid feed");

        multisig   = _multisig;
        busd       = _busd;
        rewardPool = IRewardPool(_rewardPool);
        bnbFeed    = AggregatorV3Interface(_bnbFeed);

        // Pioneer    $100 min   90 days   8% APY   2.0% exit fee
        plans[0] = Plan("Pioneer",    100_0000_0000,  90,  800,  200);
        // Vanguard   $1000 min  150 days  12% APY  2.5% exit fee
        plans[1] = Plan("Vanguard",  1000_0000_0000, 150, 1200,  250);
        // Horizon    $5000 min  180 days  18% APY  3.0% exit fee
        plans[2] = Plan("Horizon",   5000_0000_0000, 180, 1800,  300);
        // Summit VIP $15000 min 365 days  25% APY  3.5% exit fee
        plans[3] = Plan("SummitVIP",15000_0000_0000, 365, 2500,  350);
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
    // CHAINLINK PRICE
    // ─────────────────────────────────────────────

    /// @notice Get BNB/USD price from Chainlink — 8 decimals
    function getBnbPrice() public view returns (uint256) {
        (, int256 price,, uint256 updatedAt,) = bnbFeed.latestRoundData();
        require(price > 0, "invalid price");
        require(block.timestamp - updatedAt < 1 hours, "stale price");
        return uint256(price); // 8 decimals
    }

    // ─────────────────────────────────────────────
    // STAKE BNB
    // ─────────────────────────────────────────────

    function stakeBNB(uint8 planId) external payable notPaused nonReentrant {
        require(planId < 4, "invalid plan");
        require(msg.value > 0, "zero amount");

        uint256 price    = getBnbPrice(); // 8 decimals
        // msg.value is 18 decimals, price is 8 decimals → result is 8 decimals
        uint256 usdValue = (msg.value * price) / 1e18;

        require(usdValue >= plans[planId].minStakeUSD, "below minimum");
        _createStake(planId, Token.BNB, usdValue);
    }

    // ─────────────────────────────────────────────
    // STAKE BUSD
    // ─────────────────────────────────────────────

    function stakeBUSD(uint8 planId, uint256 amount) external notPaused nonReentrant {
        require(planId < 4, "invalid plan");
        require(amount > 0, "zero amount");

        // BUSD is 18 decimals — convert to 8 decimals for consistent USD tracking
        uint256 usdValue = amount / 1e10;
        require(usdValue >= plans[planId].minStakeUSD, "below minimum");

        (bool ok,) = busd.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), amount)
        );
        require(ok, "BUSD transfer failed");

        _createStake(planId, Token.BUSD, usdValue);
    }

    // ─────────────────────────────────────────────
    // INTERNAL
    // ─────────────────────────────────────────────

    function _createStake(uint8 planId, Token token, uint256 amountUSD) internal {
        Plan memory p = plans[planId];
        stakes[msg.sender].push(Stake({
            planId:    planId,
            token:     token,
            amountUSD: amountUSD,
            stakedAt:  block.timestamp,
            unlocksAt: block.timestamp + (p.lockDays * 1 days),
            claimed:   false,
            active:    true
        }));
        emit Staked(msg.sender, planId, amountUSD, token, stakes[msg.sender].length - 1);
    }

    // ─────────────────────────────────────────────
    // CLAIM REWARDS
    // ─────────────────────────────────────────────

    function claimRewards(uint256 stakeId) external notPaused nonReentrant {
        Stake storage s = stakes[msg.sender][stakeId];
        require(s.active,                        "not active");
        require(!s.claimed,                      "already claimed");
        require(block.timestamp >= s.unlocksAt,  "still locked");

        s.claimed = true;
        s.active  = false;

        uint256 wolvReward = _calcReward(s);
        rewardPool.release(msg.sender, wolvReward);

        emit Claimed(msg.sender, stakeId, wolvReward);
    }

    // ─────────────────────────────────────────────
    // EARLY EXIT
    // ─────────────────────────────────────────────

    function earlyExit(uint256 stakeId) external nonReentrant {
        Stake storage s = stakes[msg.sender][stakeId];
        require(s.active,                       "not active");
        require(!s.claimed,                     "already claimed");
        require(block.timestamp < s.unlocksAt,  "use claimRewards");

        s.active  = false;
        s.claimed = true;

        Plan memory p   = plans[s.planId];
        uint256 fee     = (s.amountUSD * p.exitFeeBps) / 10_000;
        uint256 returnUSD = s.amountUSD - fee;

        if (s.token == Token.BNB) {
            uint256 price     = getBnbPrice();
            // returnUSD is 8 decimals, price is 8 decimals → BNB in 18 decimals
            uint256 bnbReturn = (returnUSD * 1e18) / price;
            (bool sent,) = msg.sender.call{value: bnbReturn}("");
            require(sent, "BNB return failed");
        } else {
            // convert back from 8 decimals to 18 decimals for BUSD
            uint256 busdReturn = returnUSD * 1e10;
            (bool ok,) = busd.call(
                abi.encodeWithSignature("transfer(address,uint256)", msg.sender, busdReturn)
            );
            require(ok, "BUSD return failed");
        }

        emit EarlyExit(msg.sender, stakeId, p.exitFeeBps);
    }

    // ─────────────────────────────────────────────
    // REWARD CALCULATION — 1 WOLV = $1
    // ─────────────────────────────────────────────

    /// @dev amountUSD is 8 decimals. WOLV is 18 decimals. Scale up by 1e10.
    function _calcReward(Stake memory s) internal view returns (uint256) {
        Plan memory p = plans[s.planId];
        // reward (8 dec) = principal * APY * lockDays / 365 / 10000
        uint256 rewardUSD = (s.amountUSD * p.apyBps * p.lockDays) / (365 * 10_000);
        // scale to 18 decimals for WOLV
        return rewardUSD * 1e10;
    }

    // ─────────────────────────────────────────────
    // VIEW
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
    // ADMIN
    // ─────────────────────────────────────────────

    function setPaused(bool _paused) external onlyMultisig {
        paused = _paused;
    }
    receive() external payable {}
}
