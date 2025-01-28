// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "@yearn-vaults/interfaces/IVault.sol";
import "@yearn-vaults/interfaces/IVaultFactory.sol";
import "vault-periphery/contracts/accountants/Accountant.sol";
import "vault-periphery/contracts/accountants/AccountantFactory.sol";
import "@tokenized-strategy/interfaces/ITokenizedStrategy.sol";
import "../src/Strategy.sol";
import "../src/TermVaultEventEmitter.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TestDeploy is Script {
    // Vault-related state variables
    IVault public vault;
    Accountant public accountant;
    address public deployer;
    address public vaultGovernanceFactory;

    // Strategy-related state variables
    address[] public deployedStrategies;
    TermVaultEventEmitter public eventEmitter;

    function run() external {
        _setupInitialVariables();
        _deployVaultInfrastructure();
        _deployStrategies();
        _addStrategiesToVault();
        vm.stopBroadcast();
    }

    function _setupInitialVariables() internal {
        uint256 deployerPK = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPK);
        vm.startBroadcast(deployerPK);
        vaultGovernanceFactory = vm.envAddress("VAULT_GOVERNANCE_FACTORY");
    }

    function _deployVaultInfrastructure() internal {
        _deployVault();
        _deployAccountant();
        _configureVault();
        _configureAccountant();
    }

    function _deployVault() internal {
        address vaultFactoryAddress = vm.envAddress("VAULT_FACTORY");
        address asset = vm.envAddress("ASSET_ADDRESS");
        string memory name = vm.envString("VAULT_NAME");
        string memory symbol = vm.envString("VAULT_SYMBOL");
        uint256 profitMaxUnlockTime = vm.envUint("PROFIT_MAX_UNLOCK_TIME");

        IVaultFactory vaultFactory = IVaultFactory(vaultFactoryAddress);
        address vaultAddress = vaultFactory.deploy_new_vault(
            asset,
            name,
            symbol,
            deployer,
            profitMaxUnlockTime
        );
        vault = IVault(vaultAddress);
        console.log("Deployed vault contract to", address(vault));
    }

    function _deployAccountant() internal {
        address accountantFactoryAddress = vm.envAddress("ACCOUNTANT_FACTORY");
        AccountantFactory accountantFactory = AccountantFactory(accountantFactoryAddress);
        address accountantAddress = accountantFactory.newAccountant();
        accountant = Accountant(accountantAddress);
        console.log("Deployed accountant contract to", address(accountant));
    }

    function _configureVault() internal {
        address keeper = vm.envAddress("KEEPER_ADDRESS");
        address strategyAdder = vm.envAddress("STRATEGY_ADDER");
        uint256 depositLimit = vm.envOr("DEPOSIT_LIMIT", uint256(0));

        vault.set_role(deployer, 16383);
        vault.set_role(keeper, 112);
        vault.set_accountant(address(accountant));
        vault.set_deposit_limit(depositLimit);
        vault.set_use_default_queue(true);
        vault.set_role(strategyAdder, 193);
    }

    function _configureAccountant() internal {
        uint16 defaultPerformance = uint16(vm.envOr("DEFAULT_PERFORMANCE", uint256(0)));
        uint16 defaultMaxFee = uint16(vm.envOr("DEFAULT_MAX_FEE", uint256(0)));
        uint16 defaultMaxGain = uint16(vm.envOr("DEFAULT_MAX_GAIN", uint256(0)));
        uint16 defaultMaxLoss = uint16(vm.envOr("DEFAULT_MAX_LOSS", uint256(0)));
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");

        accountant.updateDefaultConfig(
            0,
            defaultPerformance,
            0,
            defaultMaxFee,
            defaultMaxGain,
            defaultMaxLoss
        );

        accountant.addVault(address(vault));
        accountant.setFutureFeeManager(vaultGovernanceFactory);
        accountant.setFeeRecipient(feeRecipient);
    }

    function _deployEventEmitter() internal {
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address devops = vm.envAddress("DEVOPS_ADDRESS");
        
        TermVaultEventEmitter eventEmitterImpl = new TermVaultEventEmitter();
        ERC1967Proxy eventEmitterProxy = new ERC1967Proxy(
            address(eventEmitterImpl),
            abi.encodeWithSelector(TermVaultEventEmitter.initialize.selector, admin, devops)
        );
        eventEmitter = TermVaultEventEmitter(address(eventEmitterProxy));
        console.log("Deployed event emitter to", address(eventEmitter));
    }

    function _deployStrategies() internal {
        if (address(eventEmitter) == address(0)) {
            _deployEventEmitter();
        }

        string[3] memory strategyNames = ["Strategy1", "Strategy2", "Strategy3"];
        
        for (uint256 i = 0; i < 3; i++) {
            Strategy strategy = _deployStrategy(strategyNames[i]);
            deployedStrategies.push(address(strategy));
            console.log("Deployed strategy", i + 1, "to", address(strategy));
        }
    }

    function _deployStrategy(string memory name) internal returns (Strategy) {
        address strategyManagement = vm.envAddress("STRATEGY_MANAGEMENT_ADDRESS");
        address keeper = vm.envAddress("KEEPER_ADDRESS");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");
        address governorRoleAddress = vm.envAddress("GOVERNOR_ROLE_ADDRESS");
        uint256 profitMaxUnlockTime = vm.envUint("PROFIT_MAX_UNLOCK_TIME");

        Strategy.StrategyParams memory params = _buildStrategyParams();

        Strategy strategy = new Strategy(
            name,
            "symbol",
            params
        );

        _configureStrategy(
            strategy,
            strategyManagement,
            keeper,
            feeRecipient,
            governorRoleAddress,
            profitMaxUnlockTime
        );

        return strategy;
    }

    function _buildStrategyParams() internal view returns (Strategy.StrategyParams memory) {
        address asset = vm.envAddress("ASSET_ADDRESS");
        address yearnVaultAddress = vm.envAddress("YEARN_VAULT_ADDRESS");
        address discountRateAdapterAddress = vm.envAddress("DISCOUNT_RATE_ADAPTER_ADDRESS");
        address termController = vm.envAddress("TERM_CONTROLLER_ADDRESS");
        uint256 discountRateMarkup = vm.envUint("DISCOUNT_RATE_MARKUP");
        uint256 timeToMaturityThreshold = vm.envUint("TIME_TO_MATURITY_THRESHOLD");
        uint256 repoTokenConcentrationLimit = vm.envUint("REPOTOKEN_CONCENTRATION_LIMIT");
        uint256 newRequiredReserveRatio = vm.envUint("NEW_REQUIRED_RESERVE_RATIO");

        return Strategy.StrategyParams(
            asset,
            yearnVaultAddress,
            discountRateAdapterAddress,
            address(eventEmitter),
            deployer,
            termController,
            repoTokenConcentrationLimit,
            timeToMaturityThreshold,
            newRequiredReserveRatio,
            discountRateMarkup
        );
    }

    function _configureStrategy(
        Strategy strategy,
        address strategyManagement,
        address keeper,
        address feeRecipient,
        address governorRoleAddress,
        uint256 profitMaxUnlockTime
    ) internal {
        ITokenizedStrategy(address(strategy)).setProfitMaxUnlockTime(profitMaxUnlockTime);
        ITokenizedStrategy(address(strategy)).setPendingManagement(strategyManagement);
        ITokenizedStrategy(address(strategy)).setKeeper(keeper);
        ITokenizedStrategy(address(strategy)).setPerformanceFeeRecipient(feeRecipient);
        strategy.setPendingGovernor(governorRoleAddress);
        
        eventEmitter.pairVaultContract(address(strategy));

        // Configure collateral tokens if needed
        string memory collateralTokensStr = vm.envString("COLLATERAL_TOKEN_ADDRESSES");
        string memory ratiosStr = vm.envString("MIN_COLLATERAL_RATIOS");
        
        if (bytes(collateralTokensStr).length > 0) {
            address[] memory collateralTokens = stringToAddressArray(collateralTokensStr);
            uint256[] memory minCollateralRatios = stringToUintArray(ratiosStr);
            
            for (uint256 i = 0; i < collateralTokens.length; i++) {
                strategy.setCollateralTokenParams(collateralTokens[i], minCollateralRatios[i]);
            }
        }
    }

    function _addStrategiesToVault() internal {
        for (uint256 i = 0; i < deployedStrategies.length; i++) {
            vault.add_strategy(deployedStrategies[i]);
            console.log("Added strategy", i + 1, "to vault");
        }
    }

    // Helper functions for parsing strings to arrays (from DeployStrategy.sol)
    function stringToAddressArray(string memory _input) public pure returns (address[] memory) {
        if (bytes(_input).length == 0) return new address[](0);
        string[] memory parts = splitString(_input, ",");
        address[] memory addressArray = new address[](parts.length);
        for (uint256 i = 0; i < parts.length; i++) {
            addressArray[i] = parseAddress(parts[i]);
        }
        return addressArray;
    }

    function stringToUintArray(string memory _input) public pure returns (uint256[] memory) {
        if (bytes(_input).length == 0) return new uint256[](0);
        string[] memory parts = splitString(_input, ",");
        uint256[] memory uintArray = new uint256[](parts.length);
        for (uint256 i = 0; i < parts.length; i++) {
            uintArray[i] = parseUint(parts[i]);
        }
        return uintArray;
    }

    function splitString(string memory _str, string memory _delimiter) internal pure returns (string[] memory) {
        bytes memory strBytes = bytes(_str);
        bytes memory delimiterBytes = bytes(_delimiter);
        uint256 partsCount = 1;
        
        for (uint256 i = 0; i < strBytes.length - 1; i++) {
            if (strBytes[i] == delimiterBytes[0]) {
                partsCount++;
            }
        }
        
        string[] memory parts = new string[](partsCount);
        uint256 partIndex = 0;
        bytes memory part;
        
        for (uint256 i = 0; i < strBytes.length; i++) {
            if (strBytes[i] == delimiterBytes[0]) {
                parts[partIndex] = string(part);
                part = "";
                partIndex++;
            } else {
                part = abi.encodePacked(part, strBytes[i]);
            }
        }
        
        parts[partIndex] = string(part);
        return parts;
    }

    function parseAddress(string memory _str) internal pure returns (address) {
        bytes memory tmp = bytes(_str);
        require(tmp.length == 42, "Invalid address length");
        
        uint160 addr = 0;
        for (uint256 i = 2; i < 42; i++) {
            uint160 b = uint160(uint8(tmp[i]));
            if (b >= 48 && b <= 57) {
                addr = addr * 16 + (b - 48);
            } else if (b >= 65 && b <= 70) {
                addr = addr * 16 + (b - 55);
            } else if (b >= 97 && b <= 102) {
                addr = addr * 16 + (b - 87);
            } else {
                revert("Invalid address character");
            }
        }
        return address(addr);
    }

    function parseUint(string memory _str) internal pure returns (uint256) {
        bytes memory strBytes = bytes(_str);
        uint256 result = 0;
        for (uint256 i = 0; i < strBytes.length; i++) {
            uint8 digit = uint8(strBytes[i]) - 48;
            require(digit >= 0 && digit <= 9, "Invalid character in string");
            result = result * 10 + digit;
        }
        return result;
    }
}