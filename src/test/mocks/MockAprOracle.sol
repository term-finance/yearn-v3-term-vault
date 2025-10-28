// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {AprOracleBase} from "@periphery/AprOracle/AprOracleBase.sol";

/**
 * @title MockAprOracle
 * @dev Mock APR Oracle for testing purposes
 */
contract MockAprOracle is AprOracleBase {
    uint256 public mockApr;

    constructor(
        string memory _name,
        address _governance
    ) AprOracleBase(_name, _governance) {
        mockApr = 1000; // 10% APR (in basis points)
    }

    function aprAfterDebtChange(
        address /* _strategy */,
        int256 /* _delta */
    ) external view override returns (uint256) {
        return mockApr;
    }

    function setMockApr(uint256 _apr) external {
        mockApr = _apr;
    }
}
