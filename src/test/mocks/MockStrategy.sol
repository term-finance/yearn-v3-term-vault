// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ITermDiscountRateAdapter} from "../../interfaces/term/ITermDiscountRateAdapter.sol";
import {ITermController} from "../../interfaces/term/ITermController.sol";

/**
 * @title MockStrategy
 * @dev Mock Strategy for testing TermStrategyAprOracle
 */
contract MockStrategy {
    struct StrategyState {
        address assetVault;
        address eventEmitter;
        address governorAddress;
        ITermController prevTermController;
        ITermController currTermController;
        ITermDiscountRateAdapter discountRateAdapter;
        uint256 timeToMaturityThreshold;
        uint256 requiredReserveRatio;
        uint256 discountRateMarkup;
        uint256 repoTokenConcentrationLimit;
    }

    StrategyState public strategyState;
    address[] private _repoTokenHoldings;
    mapping(address => uint256) private _repoTokenHoldingValues;
    uint256 public totalAssetValue;
    uint256 public totalLiquidBalance;

    constructor(address _assetVault, address _discountRateAdapter) {
        strategyState.assetVault = _assetVault;
        strategyState.discountRateAdapter = ITermDiscountRateAdapter(
            _discountRateAdapter
        );
    }

    function setRepoTokenHoldings(address[] memory _repoTokens) external {
        _repoTokenHoldings = _repoTokens;
    }

    function setRepoTokenHoldingValue(
        address _repoToken,
        uint256 _value
    ) external {
        _repoTokenHoldingValues[_repoToken] = _value;
    }

    function setTotalAssetValue(uint256 _value) external {
        totalAssetValue = _value;
    }

    function setTotalLiquidBalance(uint256 _value) external {
        totalLiquidBalance = _value;
    }

    function repoTokenHoldings() external view returns (address[] memory) {
        return _repoTokenHoldings;
    }

    function getRepoTokenHoldingValue(
        address _repoToken
    ) external view returns (uint256) {
        return _repoTokenHoldingValues[_repoToken];
    }
}
