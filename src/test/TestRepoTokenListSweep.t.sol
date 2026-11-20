pragma solidity ^0.8.18;

import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockTermRepoToken} from "./mocks/MockTermRepoToken.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {Setup, ERC20} from "./utils/Setup.sol";
import {Strategy} from "../Strategy.sol";

/// @notice A matured token whose redemption fails, followed by tokens that are
/// removed, must not unlink the rest of the list (same bug as spoke RTL-01).
contract TestRepoTokenListSweep is Setup {
    uint256 internal constant AMOUNT = 100e18;

    MockUSDC internal mockUSDC;
    ERC20Mock internal mockCollateral;
    Strategy internal termStrategy;
    address internal seller = vm.addr(0x5E11);

    function setUp() public override {
        mockUSDC = new MockUSDC();
        mockCollateral = new ERC20Mock();

        _setUp(ERC20(address(mockUSDC)));

        termStrategy = Strategy(address(strategy));

        vm.startPrank(governor);
        termStrategy.setCollateralTokenParams(address(mockCollateral), 0.5e18);
        termStrategy.setTimeToMaturityThreshold(365 days);
        termStrategy.setRepoTokenConcentrationLimit(1e18);
        termStrategy.setRequiredReserveRatio(0);
        termStrategy.setDiscountRateMarkup(0);
        vm.stopPrank();

        mockUSDC.mint(address(strategy), 10_000e6);
    }

    /// @dev K = redemption reverts, R = redeems, Z = already redeemed externally.
    function testSweepRR() public {
        _assertPatternRetained("RR");
    }

    function testSweepKR() public {
        _assertPatternRetained("KR");
    }

    function testSweepKRR() public {
        _assertPatternRetained("KRR");
    }

    function testSweepKRK() public {
        _assertPatternRetained("KRK");
    }

    function testSweepKRRR() public {
        _assertPatternRetained("KRRR");
    }

    function testSweepKZZ() public {
        _assertPatternRetained("KZZ");
    }

    function testSweepKRZ() public {
        _assertPatternRetained("KRZ");
    }

    function testSweepKRKRR() public {
        _assertPatternRetained("KRKRR");
    }

    function testSweepRKRR() public {
        _assertPatternRetained("RKRR");
    }

    function testSweepKKRR() public {
        _assertPatternRetained("KKRR");
    }

    function testSweepRRKRRKRR() public {
        _assertPatternRetained("RRKRRKRR");
    }

    function testSweepKKKK() public {
        _assertPatternRetained("KKKK");
    }

    function testSweepZKZZRZ() public {
        _assertPatternRetained("ZKZZRZ");
    }

    function _assertPatternRetained(string memory pattern) internal {
        uint256 start = block.timestamp;
        bytes memory steps = bytes(pattern);
        MockTermRepoToken[] memory tokens = new MockTermRepoToken[](
            steps.length
        );
        bool[] memory keep = new bool[](steps.length);

        for (uint256 i; i < steps.length; i++) {
            tokens[i] = _newToken(i, (i + 1) * 1 days);
            _sell(tokens[i]);
            if (steps[i] == "K") {
                tokens[i].mockServicer().setRedemptionFailure(true);
                keep[i] = true;
            }
        }

        MockTermRepoToken tail = _newToken(steps.length, 300 days);
        _sell(tail);

        vm.warp(start + steps.length * 1 days + 1);

        for (uint256 i; i < steps.length; i++) {
            if (steps[i] == "Z") {
                tokens[i].mockServicer().redeemTermRepoTokens(
                    address(strategy),
                    AMOUNT
                );
            }
        }

        termStrategy.auctionClosed();
        _assertHoldings(pattern, tokens, keep, tail);

        // A second sweep must leave the list unchanged.
        termStrategy.auctionClosed();
        _assertHoldings(pattern, tokens, keep, tail);
    }

    function _assertHoldings(
        string memory pattern,
        MockTermRepoToken[] memory tokens,
        bool[] memory keep,
        MockTermRepoToken tail
    ) internal view {
        uint256 expectedCount = 1;
        for (uint256 i; i < keep.length; i++) {
            if (keep[i]) expectedCount++;
        }

        address[] memory holdings = termStrategy.repoTokenHoldings();
        assertEq(holdings.length, expectedCount, pattern);

        uint256 cursor;
        for (uint256 i; i < tokens.length; i++) {
            if (keep[i]) {
                assertEq(holdings[cursor], address(tokens[i]), pattern);
                assertEq(
                    tokens[i].balanceOf(address(strategy)),
                    AMOUNT,
                    pattern
                );
                cursor++;
            } else {
                assertEq(tokens[i].balanceOf(address(strategy)), 0, pattern);
            }
        }

        assertEq(holdings[cursor], address(tail), pattern);
        assertEq(tail.balanceOf(address(strategy)), AMOUNT, pattern);
    }

    function _newToken(
        uint256 index,
        uint256 maturity
    ) internal returns (MockTermRepoToken) {
        return
            new MockTermRepoToken(
                keccak256(abi.encode("sweep", index)),
                address(mockUSDC),
                address(mockCollateral),
                1e18,
                block.timestamp + maturity
            );
    }

    function _sell(MockTermRepoToken token) internal {
        termController.setOracleRate(token.termRepoId(), 0.05e18);
        token.mint(seller, AMOUNT);
        vm.startPrank(seller);
        token.approve(address(strategy), AMOUNT);
        termStrategy.sellRepoToken(address(token), AMOUNT);
        vm.stopPrank();
    }
}
