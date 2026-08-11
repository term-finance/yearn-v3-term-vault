// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

interface IVault {
    struct StrategyParams {
        uint256 activation;
        uint256 last_report;
        uint256 current_debt;
        uint256 max_debt;
    }
    function strategies(address strategy) external view returns (StrategyParams memory);
    function asset() external view returns (address);
}

/// @title  MetaVaultAllocationHelper
/// @notice Stores target allocations (basis points) per strategy per Yearn v3 metavault.
///         Supports multiple vaults. Intended to be read by an off-chain rebalance service.
///
///         - setAllocations validates each strategy is active in the vault (activation != 0)
///         - getActiveAllocations filters stale strategies at read time and rescales
///           remaining active strategies proportionally so the result always sums to 10_000
///         - getStaleStrategies surfaces forgotten entries so the service can alert
contract MetaVaultAllocationHelper {

    // ─────────────────────────────────────────────────────────
    //  Access
    // ─────────────────────────────────────────────────────────

    address public immutable allocator;

    modifier onlyAllocator() {
        require(msg.sender == allocator, "not allocator");
        _;
    }

    // ─────────────────────────────────────────────────────────
    //  Storage
    // ─────────────────────────────────────────────────────────

    /// metavault → strategy → allocation bps (10_000 = 100%)
    mapping(address => mapping(address => uint256)) private _allocBps;

    /// metavault → ordered strategy list for enumeration
    mapping(address => address[]) private _strategyList;

    // ─────────────────────────────────────────────────────────
    //  Events
    // ─────────────────────────────────────────────────────────

    event AllocationsUpdated(
        address indexed metavault,
        address indexed caller,
        address[] strategies,
        uint256[] bpsTargets,
        uint256 timestamp
    );

    // ─────────────────────────────────────────────────────────
    //  Constructor
    // ─────────────────────────────────────────────────────────

    constructor(address _allocator) {
        require(_allocator != address(0), "zero address");
        allocator = _allocator;
    }

    // ─────────────────────────────────────────────────────────
    //  Read — stored state
    // ─────────────────────────────────────────────────────────

    /// @notice Stored target bps for a single strategy in a metavault
    function getAllocation(address metavault, address strategy)
        external view returns (uint256 bps)
    {
        return _allocBps[metavault][strategy];
    }

    /// @notice All stored strategies and bps targets for a metavault (unfiltered)
    function getAllocations(address metavault)
        external view
        returns (address[] memory strategies, uint256[] memory bpsTargets)
    {
        strategies = _strategyList[metavault];
        bpsTargets = new uint256[](strategies.length);
        for (uint256 i; i < strategies.length; ++i) {
            bpsTargets[i] = _allocBps[metavault][strategies[i]];
        }
    }

    /// @notice Number of strategies stored for a metavault
    function strategyCount(address metavault) external view returns (uint256) {
        return _strategyList[metavault].length;
    }

    /// @notice Live vault params for a strategy directly from the vault
    function getStrategyParams(address metavault, address strategy)
        external view
        returns (IVault.StrategyParams memory)
    {
        return IVault(metavault).strategies(strategy);
    }

    // ─────────────────────────────────────────────────────────
    //  Read — live-filtered (use these in the rebalance service)
    // ─────────────────────────────────────────────────────────

    /// @notice Returns only strategies currently active in the vault (activation != 0).
    ///         If stale entries exist they are dropped and the remaining active strategies
    ///         are rescaled proportionally so bpsTargets sums to exactly 10_000.
    ///         Rounding dust is assigned to the last strategy.
    ///         hasStale signals that a setAllocations cleanup call is needed.
    ///         Reverts if stale entries exist and every remaining active strategy has a
    ///         0 bps target — no valid allocation can be derived, so the allocator must
    ///         submit a fresh setAllocations call.
    function getActiveAllocations(address metavault)
        external view
        returns (
            address[] memory strategies,
            uint256[] memory bpsTargets,
            bool hasStale
        )
    {
        address[] storage stored = _strategyList[metavault];
        uint256 len = stored.length;

        address[] memory tmpStrats = new address[](len);
        uint256[] memory tmpBps    = new uint256[](len);
        uint256 count;
        uint256 activeSum;

        for (uint256 i; i < len; ++i) {
            address s = stored[i];
            if (IVault(metavault).strategies(s).activation != 0) {
                tmpStrats[count] = s;
                tmpBps[count]    = _allocBps[metavault][s];
                activeSum       += _allocBps[metavault][s];
                ++count;
            } else {
                hasStale = true;
            }
        }

        strategies = new address[](count);
        bpsTargets = new uint256[](count);

        if (count == 0) return (strategies, bpsTargets, hasStale);

        // No stale entries — already sums to 10_000, no rescaling needed
        if (!hasStale) {
            for (uint256 i; i < count; ++i) {
                strategies[i] = tmpStrats[i];
                bpsTargets[i] = tmpBps[i];
            }
            return (strategies, bpsTargets, hasStale);
        }

        // Every active strategy has a 0 bps target: the allocator's intent was
        // invalidated by the vault-side deactivation and there is no meaningful
        // allocation to return. Fail closed rather than inventing weights — a
        // 0 bps target may be a deliberate wind-down, so redistributing into
        // those strategies would move liquidity the allocator never asked for.
        // getStaleStrategies() still works, so monitoring/alerting is unaffected.
        require(activeSum > 0, "no active allocation weight");

        // Rescale active strategies proportionally to sum to 10_000.
        // Rounding dust is assigned to the last strategy.
        uint256 allocated;
        for (uint256 i; i < count; ++i) {
            strategies[i] = tmpStrats[i];
            if (i < count - 1) {
                bpsTargets[i] = tmpBps[i] * 10_000 / activeSum;
                allocated += bpsTargets[i];
            } else {
                bpsTargets[i] = 10_000 - allocated;
            }
        }
    }

    /// @notice Returns any stored strategies no longer active in the vault.
    ///         Use for monitoring and alerting — does not modify state.
    function getStaleStrategies(address metavault)
        external view
        returns (address[] memory stale)
    {
        address[] storage stored = _strategyList[metavault];
        uint256 len = stored.length;

        address[] memory tmp = new address[](len);
        uint256 count;

        for (uint256 i; i < len; ++i) {
            if (IVault(metavault).strategies(stored[i]).activation == 0) {
                tmp[count++] = stored[i];
            }
        }

        stale = new address[](count);
        for (uint256 i; i < count; ++i) stale[i] = tmp[i];
    }

    // ─────────────────────────────────────────────────────────
    //  Write
    // ─────────────────────────────────────────────────────────

    /// @notice Replace the full allocation set for a metavault.
    ///         - Clears all previously stored strategies for this vault
    ///         - Validates each strategy is active in the vault (activation != 0)
    ///         - bpsTargets must sum to exactly 10_000
    ///         Caller must be the allocator.
    function setAllocations(
        address metavault,
        address[] calldata strategies,
        uint256[] calldata bpsTargets
    ) external onlyAllocator {
        require(strategies.length == bpsTargets.length, "length mismatch");
        require(strategies.length > 0, "empty");

        // Validate bps sum before any writes
        uint256 total;
        for (uint256 i; i < bpsTargets.length; ++i) {
            require(bpsTargets[i] <= 10_000, "bps overflow");
            total += bpsTargets[i];
        }
        require(total == 10_000, "must sum to 10000 bps");

        // Validate all strategies are active, and reject duplicates, before any
        // writes. A duplicate would push the same address into _strategyList twice
        // while _allocBps kept only the last write, so the read helpers would report
        // a bps total above 10_000 with hasStale == false — no signal to the caller.
        // The O(n^2) comparison is negligible next to the cold STATICCALL per
        // strategy in this same loop.
        for (uint256 i; i < strategies.length; ++i) {
            require(
                IVault(metavault).strategies(strategies[i]).activation != 0,
                "strategy not active in vault"
            );
            for (uint256 j; j < i; ++j) {
                require(strategies[j] != strategies[i], "duplicate strategy");
            }
        }

        // Clear existing stored state for this metavault
        address[] storage existing = _strategyList[metavault];
        for (uint256 i; i < existing.length; ++i) {
            delete _allocBps[metavault][existing[i]];
        }
        delete _strategyList[metavault];

        // Write new set
        for (uint256 i; i < strategies.length; ++i) {
            address strategy = strategies[i];
            _strategyList[metavault].push(strategy);
            _allocBps[metavault][strategy] = bpsTargets[i];
        }

        emit AllocationsUpdated(
            metavault,
            msg.sender,
            strategies,
            bpsTargets,
            block.timestamp
        );
    }
}