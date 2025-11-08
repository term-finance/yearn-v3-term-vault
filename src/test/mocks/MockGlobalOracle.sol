// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

/**
 * @title MockGlobalOracle
 * @dev Mock Global Oracle for testing purposes that implements IAprOracleGlobal interface
 */
contract MockGlobalOracle {
    mapping(address => uint256) public mockAprs;
    uint256 public defaultApr = 500; // 5% default APR

    function getWeightedAverageApr(
        address _vault,
        int256 /* _delta */
    ) external view returns (uint256) {
        uint256 apr = mockAprs[_vault];
        return apr == 0 ? defaultApr : apr;
    }

    function getStrategyApr(
        address _strategy,
        int256 /* _debtChange */
    ) external view returns (uint256 apr) {
        apr = mockAprs[_strategy];
        return apr == 0 ? defaultApr : apr;
    }

    function setMockApr(address _vault, uint256 _apr) external {
        mockAprs[_vault] = _apr;
    }

    function setDefaultApr(uint256 _apr) external {
        defaultApr = _apr;
    }
}
