// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

/// @notice Minimal Yearn v3 metavault stand-in exposing only what
///         MetaVaultAllocationHelper reads: strategies() and asset().
///         activation is flippable so tests can simulate the vault revoking a
///         strategy after allocations were already stored in the helper.
contract MockMetaVault {
    struct StrategyParams {
        uint256 activation;
        uint256 last_report;
        uint256 current_debt;
        uint256 max_debt;
    }

    address public asset;

    mapping(address => StrategyParams) internal _strategies;

    constructor(address asset_) {
        asset = asset_;
    }

    function strategies(
        address strategy
    ) external view returns (StrategyParams memory) {
        return _strategies[strategy];
    }

    /// @notice Mark a strategy active in the vault (activation != 0)
    function activateStrategy(address strategy) external {
        _strategies[strategy].activation = 1;
        _strategies[strategy].last_report = 1;
        _strategies[strategy].max_debt = type(uint256).max;
    }

    /// @notice Revoke a strategy the way the vault would (activation == 0)
    function deactivateStrategy(address strategy) external {
        _strategies[strategy].activation = 0;
    }
}
