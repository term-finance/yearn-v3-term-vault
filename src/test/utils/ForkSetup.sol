// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ExtendedTest } from "./ExtendedTest.sol";
import { ITermController } from "../../interfaces/term/ITermController.sol";
import { TermDiscountRateAdapter } from "../../TermDiscountRateAdapter.sol";
import { TermVaultEventEmitter } from "../../TermVaultEventEmitter.sol";
import { IStrategyInterface } from "../../interfaces/IStrategyInterface.sol";
import { Strategy, ERC20 } from "../../Strategy.sol";
import { IYearnVaultFactory} from "../../interfaces/yearn/IYearnVaultFactory.sol";
import { IYearnVault } from "../../interfaces/yearn/IYearnVault.sol";
import { IYearnAccountantFactory} from "../../interfaces/yearn/IYearnAccountantFactory.sol";

contract ForkSetup is ExtendedTest {

    TermVaultEventEmitter internal termVaultEventEmitterImpl;
    TermVaultEventEmitter internal termVaultEventEmitter;
    TermDiscountRateAdapter internal discountRateAdapter;
    ITermController internal termController;
    address internal asset;
    address internal oracleWallet;
    address internal adminWallet;
    address internal devopsWallet;
    address internal management;
    IERC4626 internal yearnVault;
    IStrategyInterface internal strategy;
    IYearnVaultFactory internal vaultFactory;
    IYearnAccountantFactory internal accountantFactory;
    address internal accountant;
    IYearnVault internal multiStratVault;

    function setUp() public virtual {
        // change these
        oracleWallet = 0x3DEE03a09FE9c792c95Ec32C0668F67DC2C1aa11;
        adminWallet = 0x3DEE03a09FE9c792c95Ec32C0668F67DC2C1aa11;
        devopsWallet = 0x3DEE03a09FE9c792c95Ec32C0668F67DC2C1aa11;
        management = 0x3DEE03a09FE9c792c95Ec32C0668F67DC2C1aa11;

        // USDC
        asset = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        termController = ITermController(0x21FC7B250CCAeECDb2abb38e04617D1f24D98772);
        discountRateAdapter = new TermDiscountRateAdapter(address(termController), oracleWallet);

        termVaultEventEmitterImpl = new TermVaultEventEmitter();
        termVaultEventEmitter = TermVaultEventEmitter(address(new ERC1967Proxy(address(termVaultEventEmitterImpl), "")));

        // Yearn USDC vaults
        yearnVault = IERC4626(0xBe53A109B494E5c9f97b9Cd39Fe969BE68BF6204);

        termVaultEventEmitter.initialize(adminWallet, devopsWallet);

        strategy = IStrategyInterface(
            address(
                new Strategy(
                    address(asset), 
                    "Tokenized Strategy", 
                    address(yearnVault), 
                    address(discountRateAdapter),
                    address(termVaultEventEmitter)
                )
            )
        );

        vm.prank(adminWallet);
        termVaultEventEmitter.pairVaultContract(address(strategy));

        // set keeper
        strategy.setKeeper(devopsWallet);
        // set treasury
        strategy.setPerformanceFeeRecipient(management);
        // set management of the strategy
        strategy.setPendingManagement(management);

        vm.prank(management);
        strategy.acceptManagement();

        vm.prank(management);
        strategy.setTermController(address(termController));

        vaultFactory = IYearnVaultFactory(0x5577EdcB8A856582297CdBbB07055E6a6E38eb5f);

        multiStratVault = IYearnVault(vaultFactory.deploy_new_vault(
            address(asset), 
            "Term USDC Vault", 
            "TermUSDCVault", 
            adminWallet, 
            604800
        ));

        accountantFactory = IYearnAccountantFactory(0xF728f839796a399ACc2823c1e5591F05a31c32d1);

        accountant = accountantFactory.newAccountant(
            management, 
            management, 
            50, 
            0, 
            0, 
            10000, 
            20000, 
            1
        );
        // Enable all roles
        vm.prank(management);
        multiStratVault.set_role(management, 16383);

        vm.prank(management);
        multiStratVault.set_accountant(accountant);

        vm.prank(management);
        multiStratVault.set_auto_allocate(true);

        vm.prank(management);
        multiStratVault.set_use_default_queue(true);

        vm.prank(management);
        multiStratVault.add_strategy(address(strategy), false);

        address[] memory queue = new address[](1);

        queue[0] = address(strategy);

        vm.prank(management);
        multiStratVault.set_default_queue(queue);

        vm.prank(management);
        multiStratVault.update_max_debt_for_strategy(address(strategy), type(uint256).max);
    }
}
