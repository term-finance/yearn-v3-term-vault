pragma solidity ^0.8.18;

// https://eth-mainnet.g.alchemy.com/v2/S2Yw6G1KKMcF3TUdGLZhHuQ2Biqe_Af9

import {ForkSetup} from "./utils/ForkSetup.sol";

contract TestUSDCFork is ForkSetup {
    address internal depositor;

    function setUp() public override {
        super.setUp();

        depositor = vm.addr(0x123456);
        vm.deal(depositor, 1e18);

        deal(address(asset), depositor, 1000000e6);
    }

    function testDeposit() public {
        vm.prank(depositor);        
        asset.approve(address(multiStratVault), type(uint256).max);

        vm.prank(depositor);
        multiStratVault.deposit(1000e6, depositor);

        assertEq(multiStratVault.balanceOf(depositor), 1000e6);
        assertEq(strategy.balanceOf(address(multiStratVault)), 1000e6);
    }

    function testSellRepoToken() public {
        
    }
}