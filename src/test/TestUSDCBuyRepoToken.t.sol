pragma solidity ^0.8.18;

import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockTermRepoToken} from "./mocks/MockTermRepoToken.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";
import {RepoTokenList} from "../RepoTokenList.sol";
import {TwoWayStrategy} from "../TwoWayStrategy.sol";

contract TestUSDCBuyRepoToken is Setup {
    MockUSDC internal mockUSDC;
    ERC20Mock internal mockCollateral;
    MockTermRepoToken internal repoToken1Week;
    TwoWayStrategy internal termStrategy;

    address internal seller = vm.addr(0x11111);
    address internal buyer = vm.addr(0x22222);

    function constructStrategy(
        address asset_,
        address mockYearnVault_,
        address discountRateAdapter_,
        address termVaultEventEmitter_,
        address governor_,
        address termController_
    ) internal override returns (IStrategyInterface) {
        TwoWayStrategy.StrategyParams memory params = TwoWayStrategy.StrategyParams(
            asset_,
            mockYearnVault_,
            discountRateAdapter_,
            termVaultEventEmitter_,
            governor_,
            termController_,
            0.1e18,
            45 days,
            0.2e18,
            0.005e18,
            0.005e18
        );
        TwoWayStrategy strat = new TwoWayStrategy("Tokenized Strategy", "tS", params);
        return IStrategyInterface(address(strat));
    }

    function setUp() public override {
        mockUSDC = new MockUSDC();
        mockCollateral = new ERC20Mock();

        _setUp(ERC20(address(mockUSDC)));

        repoToken1Week = new MockTermRepoToken(
            bytes32("test repo token 1"),
            address(mockUSDC),
            address(mockCollateral),
            1e18,
            block.timestamp + 1 weeks
        );

        termStrategy = TwoWayStrategy(address(strategy));

        vm.startPrank(governor);
        termStrategy.setCollateralTokenParams(address(mockCollateral), 0.5e18);
        termStrategy.setTimeToMaturityThreshold(10 weeks);
        termStrategy.setRepoTokenConcentrationLimit(1e18);
        termStrategy.setRequiredReserveRatio(0);
        termStrategy.setDiscountRateMarkup(0);
        termStrategy.setDiscountRateBuyMarkup(0);
        vm.stopPrank();
    }

    function _seedInventory(uint256 repoTokenAmount) private {
        mockUSDC.mint(address(strategy), 100e6);

        repoToken1Week.mint(seller, repoTokenAmount);
        vm.prank(seller);
        repoToken1Week.approve(address(strategy), type(uint256).max);

        termController.setOracleRate(repoToken1Week.termRepoId(), 0.05e18);

        vm.prank(seller);
        termStrategy.sellRepoToken(address(repoToken1Week), repoTokenAmount);
    }

    function testBuyRepoTokenReversesSell() public {
        uint256 repoTokenAmount = 1e18;
        _seedInventory(repoTokenAmount);

        uint256 expectedCost = termStrategy.calculateRepoTokenPresentValue(
            address(repoToken1Week),
            0.05e18,
            repoTokenAmount
        );

        mockUSDC.mint(buyer, expectedCost);
        vm.startPrank(buyer);
        mockUSDC.approve(address(strategy), type(uint256).max);
        termStrategy.buyRepoToken(address(repoToken1Week), repoTokenAmount);
        vm.stopPrank();

        assertEq(repoToken1Week.balanceOf(buyer), repoTokenAmount);
        assertEq(repoToken1Week.balanceOf(address(strategy)), 0);
        assertEq(mockUSDC.balanceOf(buyer), 0);
        assertEq(termStrategy.getRepoTokenHoldingValue(address(repoToken1Week)), 0);
    }

    function testBuyRepoTokenSubtractsBuyMarkup() public {
        uint256 repoTokenAmount = 1e18;
        uint256 buyMarkup = 0.01e18;

        vm.prank(governor);
        termStrategy.setDiscountRateBuyMarkup(buyMarkup);

        _seedInventory(repoTokenAmount);

        uint256 costWithoutMarkup = termStrategy.calculateRepoTokenPresentValue(
            address(repoToken1Week),
            0.05e18,
            repoTokenAmount
        );
        uint256 expectedCost = termStrategy.calculateRepoTokenPresentValue(
            address(repoToken1Week),
            0.05e18 - buyMarkup,
            repoTokenAmount
        );
        assertGt(expectedCost, costWithoutMarkup);

        mockUSDC.mint(buyer, expectedCost);
        vm.startPrank(buyer);
        mockUSDC.approve(address(strategy), type(uint256).max);
        termStrategy.buyRepoToken(address(repoToken1Week), repoTokenAmount);
        vm.stopPrank();

        assertEq(mockUSDC.balanceOf(buyer), 0);
        assertEq(repoToken1Week.balanceOf(buyer), repoTokenAmount);
    }

    function testBuyAndSellMarkupsAreIndependent() public {
        uint256 repoTokenAmount = 1e18;
        uint256 sellMarkup = 0.01e18;
        uint256 buyMarkup = 0.02e18;

        vm.startPrank(governor);
        termStrategy.setDiscountRateMarkup(sellMarkup);
        termStrategy.setDiscountRateBuyMarkup(buyMarkup);
        vm.stopPrank();

        _seedInventory(repoTokenAmount);

        uint256 sellerProceeds = mockUSDC.balanceOf(seller);
        uint256 expectedSell = termStrategy.calculateRepoTokenPresentValue(
            address(repoToken1Week),
            0.05e18 + sellMarkup,
            repoTokenAmount
        );
        assertEq(sellerProceeds, expectedSell);

        uint256 expectedBuy = termStrategy.calculateRepoTokenPresentValue(
            address(repoToken1Week),
            0.05e18 - buyMarkup,
            repoTokenAmount
        );
        assertGt(expectedBuy, sellerProceeds);

        mockUSDC.mint(buyer, expectedBuy);
        vm.startPrank(buyer);
        mockUSDC.approve(address(strategy), type(uint256).max);
        termStrategy.buyRepoToken(address(repoToken1Week), repoTokenAmount);
        vm.stopPrank();

        assertEq(mockUSDC.balanceOf(buyer), 0);
        assertEq(repoToken1Week.balanceOf(buyer), repoTokenAmount);
    }

    function testBuyRepoTokenFloorsQuotedRateAtZero() public {
        uint256 repoTokenAmount = 1e18;

        vm.prank(governor);
        termStrategy.setDiscountRateBuyMarkup(0.10e18);

        _seedInventory(repoTokenAmount);

        // oracle rate is 0.05e18, buy markup 0.10e18 => quoted rate floors to 0 (par)
        uint256 expectedCost = termStrategy.calculateRepoTokenPresentValue(
            address(repoToken1Week),
            0,
            repoTokenAmount
        );

        mockUSDC.mint(buyer, expectedCost);
        vm.startPrank(buyer);
        mockUSDC.approve(address(strategy), type(uint256).max);
        termStrategy.buyRepoToken(address(repoToken1Week), repoTokenAmount);
        vm.stopPrank();

        assertEq(mockUSDC.balanceOf(buyer), 0);
        assertEq(repoToken1Week.balanceOf(buyer), repoTokenAmount);
    }

    function testBuyInsufficientRepoTokenBalance() public {
        mockUSDC.mint(address(strategy), 100e6);
        mockUSDC.mint(buyer, 100e6);
        termController.setOracleRate(repoToken1Week.termRepoId(), 0.05e18);

        vm.startPrank(buyer);
        mockUSDC.approve(address(strategy), type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                TwoWayStrategy.InsufficientRepoTokenBalance.selector,
                0,
                1e18
            )
        );
        termStrategy.buyRepoToken(address(repoToken1Week), 1e18);
        vm.stopPrank();
    }

    function testBuyInvalidRepoToken() public {
        uint256 repoTokenAmount = 1e18;
        _seedInventory(repoTokenAmount);

        termController.markNotTermDeployed(address(repoToken1Week));

        mockUSDC.mint(buyer, 100e6);
        vm.startPrank(buyer);
        mockUSDC.approve(address(strategy), type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                RepoTokenList.InvalidRepoToken.selector,
                address(repoToken1Week)
            )
        );
        termStrategy.buyRepoToken(address(repoToken1Week), repoTokenAmount);
        vm.stopPrank();
    }

    function testBuyZeroAmountReverts() public {
        vm.expectRevert();
        vm.prank(buyer);
        termStrategy.buyRepoToken(address(repoToken1Week), 0);
    }

    function testSetDiscountRateBuyMarkup() public {
        vm.expectRevert();
        termStrategy.setDiscountRateBuyMarkup(12345);

        vm.prank(governor);
        termStrategy.setDiscountRateBuyMarkup(12345);
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint256 discountRateBuyMarkup,

        ) = termStrategy.strategyState();
        assertEq(discountRateBuyMarkup, 12345);
    }
}
