// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

interface IYearnAccountantFactory {
    function newAccountant(
        address feeManager,
        address feeRecipient,
        uint16 defaultManagement,
        uint16 defaultPerformance,
        uint16 defaultRefund,
        uint16 defaultMaxFee,
        uint16 defaultMaxGain,
        uint16 defaultMaxLoss
    ) external returns (address _newAccountant);
}
