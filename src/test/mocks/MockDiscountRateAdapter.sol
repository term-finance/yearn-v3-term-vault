// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

/**
 * @title MockDiscountRateAdapter
 * @dev Mock Discount Rate Adapter for testing
 */
contract MockDiscountRateAdapter {
    mapping(address => uint256) private discountRates;

    function setDiscountRate(address repoToken, uint256 rate) external {
        discountRates[repoToken] = rate;
    }

    function getDiscountRate(address repoToken) external view returns (uint256) {
        return discountRates[repoToken];
    }
}
