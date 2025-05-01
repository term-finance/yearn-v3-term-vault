// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

struct StrategyParams {
    uint256 activation;
    uint256 last_report;
    uint256 current_debt;
    uint256 max_debt;
}

interface IStrategy {
    function report() external;
}

interface IVault {
    function process_report(address strategy) external;
    function update_debt(
        address strategy,
        uint256 targetAmount,
        uint256 maxLoss
    ) external;
    function totalIdle() external returns (uint256);
    function strategies(
        address strategy
    ) external view returns (StrategyParams memory);
}

interface ICommonReportTrigger {
    function defaultStrategyReportTrigger(
        address _strategy
    ) external view returns (bool, bytes memory);
    function defaultVaultReportTrigger(
        address _vault,
        address _strategy
    ) external view returns (bool, bytes memory);
}

contract TermVaultsKeeper is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    address public constant COMMON_REPORT_TRIGGER_ADDRESS =
        0xA045D4dAeA28BA7Bfe234c96eAa03daFae85A147;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address devops,
        address initialKeeper
    ) public initializer {
        __AccessControl_init();
        _setupRole(DEFAULT_ADMIN_ROLE, devops);
        _setupRole(KEEPER_ROLE, initialKeeper);
    }

    function reports(
        address[] calldata strategies,
        address vault,
        address[] calldata vaultStrategies
    ) external onlyRole(KEEPER_ROLE) {
        _callStrategyReports(strategies);
        _processReports(vault, vaultStrategies);
    }

    function _callStrategyReports(address[] calldata strategies) internal {
        ICommonReportTrigger commonReportTrigger = ICommonReportTrigger(
            COMMON_REPORT_TRIGGER_ADDRESS
        );
        for (uint256 i = 0; i < strategies.length; i++) {
            (bool shouldReport, ) = commonReportTrigger
                .defaultStrategyReportTrigger(strategies[i]);
            if (shouldReport) {
                IStrategy(strategies[i]).report();
            }
        }
    }

    function _processReports(
        address vault,
        address[] calldata strategies
    ) internal {
        ICommonReportTrigger commonReportTrigger = ICommonReportTrigger(
            COMMON_REPORT_TRIGGER_ADDRESS
        );
        for (uint256 i = 0; i < strategies.length; i++) {
            (bool shouldReport, ) = commonReportTrigger
                .defaultVaultReportTrigger(vault, strategies[i]);
            if (shouldReport) {
                IVault(vault).process_report(strategies[i]);
            }
        }
    }

    function reportsNoTriggerCheck(
        address[] calldata strategies,
        address vault,
        address[] calldata vaultStrategies
    ) external onlyRole(KEEPER_ROLE) {
        _callStrategyReportsNoTriggerCheck(strategies);
        _processReportsNoTriggerCheck(vault, vaultStrategies);
    }

    function _callStrategyReportsNoTriggerCheck(
        address[] calldata strategies
    ) internal {
        for (uint256 i = 0; i < strategies.length; i++) {
            IStrategy(strategies[i]).report();
        }
    }

    function _processReportsNoTriggerCheck(
        address vault,
        address[] calldata strategies
    ) internal {
        for (uint256 i = 0; i < strategies.length; i++) {
            IVault(vault).process_report(strategies[i]);
        }
    }

    function rebalanceVault(
        address vault,
        address[] calldata withdrawStrategies,
        uint256[] calldata withdrawTargetAmounts,
        address[] calldata depositStrategies,
        uint256[] calldata depositTargetAmounts
    ) external onlyRole(KEEPER_ROLE) {
        require(vault != address(0), "0 address vault");
        if (withdrawStrategies.length > 0) {
            _withdraw(vault, withdrawStrategies, withdrawTargetAmounts);
        }
        if (depositStrategies.length > 0) {
            _deposit(vault, depositStrategies, depositTargetAmounts);
        }
    }

    function _withdraw(
        address vault,
        address[] calldata withdrawStrategies,
        uint256[] calldata withdrawTargetAmounts
    ) internal {
        for (uint256 i = 0; i < withdrawStrategies.length; i++) {
            IVault(vault).update_debt(
                withdrawStrategies[i],
                withdrawTargetAmounts[i],
                10000
            );
        }
    }

    function _deposit(
        address vault,
        address[] calldata depositStrategies,
        uint256[] calldata depositTargetAmounts
    ) internal {
        IVault vaultContract = IVault(vault);
        for (uint256 i = 0; i < depositStrategies.length - 1; i++) {
            vaultContract.update_debt(
                depositStrategies[i],
                depositTargetAmounts[i],
                10000
            );
        }
        StrategyParams memory strategyParams = vaultContract.strategies(
            depositStrategies[depositStrategies.length - 1]
        );
        uint256 newDebtTarget = strategyParams.current_debt +
            vaultContract.totalIdle();
        vaultContract.update_debt(
            depositStrategies[depositStrategies.length - 1],
            newDebtTarget,
            10000
        );
    }

    function _authorizeUpgrade(
        address
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
