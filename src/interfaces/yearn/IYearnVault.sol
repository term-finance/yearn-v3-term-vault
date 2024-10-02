// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

interface IYearnVault {
    function set_accountant(address) external;
    function set_auto_allocate(bool) external;
    function set_use_default_queue(bool) external;
    function set_default_queue(address[] calldata queue) external;
    function set_role(address account, uint256 role) external;
    function update_max_debt_for_strategy(address strategy, uint256 maxDebt) external;
    function add_strategy(address strategy, bool addToQueue) external;
}