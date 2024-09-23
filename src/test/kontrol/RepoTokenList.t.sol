pragma solidity 0.8.23;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import "src/RepoTokenList.sol";

import "src/test/kontrol/Constants.sol";
import "src/test/kontrol/RepoToken.sol";
import "src/test/kontrol/TermDiscountRateAdapter.sol";

contract RepoTokenListTest is Test, KontrolCheats {
    using RepoTokenList for RepoTokenListData;

    RepoTokenListData _listData;

    function _initializeListEmpty() internal {
        _listData.head = RepoTokenList.NULL_NODE;
    }

    function testGetCumulativeDataEmpty(
        address repoToken,
        uint256 repoTokenAmount,
        uint256 purchaseTokenPrecision
    ) external {
        _initializeListEmpty();

        TermDiscountRateAdapter discountRateAdapter =
            new TermDiscountRateAdapter();

        (
            uint256 cumulativeWeightedTimeToMaturity,
            uint256 cumulativeRepoTokenAmount,
            bool found
        ) = _listData.getCumulativeRepoTokenData(
            ITermDiscountRateAdapter(address(discountRateAdapter)),
            repoToken,
            repoTokenAmount,
            purchaseTokenPrecision
        );

        assert(cumulativeWeightedTimeToMaturity == 0);
        assert(cumulativeRepoTokenAmount == 0);
        assert(found == false);
    }

    function testGetPresentValueEmpty(
        uint256 purchaseTokenPrecision
    ) external {
        _initializeListEmpty();

        TermDiscountRateAdapter discountRateAdapter =
            new TermDiscountRateAdapter();

        uint256 totalPresentValue = _listData.getPresentValue(
            ITermDiscountRateAdapter(address(discountRateAdapter)),
            purchaseTokenPrecision
        );

        assert(totalPresentValue == 0);
    }

    function _getNext(RepoTokenListData storage listData, address current) private view returns (address) {
        return listData.nodes[current].next;
    }

    function _initializeRepoTokenList(
        TermDiscountRateAdapter discountRateAdapter
    ) internal {
        address previous = RepoTokenList.NULL_NODE;
        address current = _listData.head;

        while (current != RepoTokenList.NULL_NODE) {
            RepoToken repoToken = new RepoToken();
            repoToken.initializeSymbolic();

            address newCurrent = address(repoToken);

            if (previous == RepoTokenList.NULL_NODE) {
                _listData.head = newCurrent;
            } else {
                _listData.nodes[previous].next = newCurrent;
            }

            discountRateAdapter.initializeSymbolicFor(newCurrent);
            _listData.discountRates[newCurrent] =
                discountRateAdapter.getDiscountRate(newCurrent);

            previous = newCurrent;
            current = _getNext(_listData, newCurrent);
        }
    }

    // Calculates the cumulative data assuming that no tokens have matured
    function _cumulativeRepoTokenDataNotMatured(
        ITermDiscountRateAdapter discountRateAdapter,
        uint256 purchaseTokenPrecision
    ) internal view returns (
        uint256 cumulativeWeightedTimeToMaturity,
        uint256 cumulativeRepoTokenAmount
    ) {
        address current = _listData.head;

        while (current != RepoTokenList.NULL_NODE) {
            (uint256 currentMaturity, , ,) = ITermRepoToken(current).config();
            assert(currentMaturity > block.timestamp);
            uint256 repoTokenBalance = ITermRepoToken(current).balanceOf(address(this));
            uint256 repoRedemptionHaircut = discountRateAdapter.repoRedemptionHaircut(current);
            uint256 timeToMaturity = currentMaturity - block.timestamp;

            uint256 repoTokenAmountInBaseAssetPrecision =
                RepoTokenUtils.getNormalizedRepoTokenAmount(
                    current,
                    repoTokenBalance,
                    purchaseTokenPrecision,
                    repoRedemptionHaircut
                );

            uint256 weightedTimeToMaturity =
                timeToMaturity * repoTokenAmountInBaseAssetPrecision;

            cumulativeWeightedTimeToMaturity += weightedTimeToMaturity;
            cumulativeRepoTokenAmount += repoTokenAmountInBaseAssetPrecision;

            current = _getNext(_listData, current);
        }
    }

    function testGetCumulativeDataSymbolic(
        address repoToken,
        uint256 repoTokenAmount,
        uint256 purchaseTokenPrecision
    ) external {
        TermDiscountRateAdapter discountRateAdapter =
            new TermDiscountRateAdapter();

        kevm.symbolicStorage(address(this));
        kevm.symbolicStorage(address(discountRateAdapter));
        _initializeRepoTokenList(discountRateAdapter);

        vm.assume(repoTokenAmount < ETH_UPPER_BOUND);
        vm.assume(purchaseTokenPrecision <= 18);

        (
            uint256 cumulativeWeightedTimeToMaturity,
            uint256 cumulativeRepoTokenAmount,
            bool found
        ) = _listData.getCumulativeRepoTokenData(
            discountRateAdapter,
            repoToken,
            repoTokenAmount,
            purchaseTokenPrecision
        );

        if (!found) {
            // Simplified calculation in the case no tokens have matured
            (
                uint256 cumulativeWeightedTimeToMaturityNotMatured,
                uint256 cumulativeRepoTokenAmountNotMatured
            ) = _cumulativeRepoTokenDataNotMatured(
                discountRateAdapter,
                purchaseTokenPrecision
            );

            assertEq(
                cumulativeWeightedTimeToMaturity,
                cumulativeWeightedTimeToMaturityNotMatured
            );

            assertEq(
                cumulativeRepoTokenAmount,
                cumulativeRepoTokenAmountNotMatured
            );
        }
    }

    // Calculates the total present value assuming that no tokens have matured
    function _totalPresentValueNotMatured(
        ITermDiscountRateAdapter discountRateAdapter,
        uint256 purchaseTokenPrecision
    ) internal view returns (uint256) {
        address current = _listData.head;
        uint256 totalPresentValue = 0;

        while (current != RepoTokenList.NULL_NODE) {
            (uint256 currentMaturity, , ,) = ITermRepoToken(current).config();
            assert(currentMaturity > block.timestamp);
            uint256 repoTokenBalance = ITermRepoToken(current).balanceOf(address(this));
            uint256 repoRedemptionHaircut = discountRateAdapter.repoRedemptionHaircut(current);
            uint256 discountRate = discountRateAdapter.getDiscountRate(current);
            uint256 timeToMaturity = currentMaturity - block.timestamp;

            uint256 repoTokenAmountInBaseAssetPrecision =
                RepoTokenUtils.getNormalizedRepoTokenAmount(
                    current,
                    repoTokenBalance,
                    purchaseTokenPrecision,
                    repoRedemptionHaircut
                );

            uint256 presentValue =
                repoTokenAmountInBaseAssetPrecision /
                (1 + discountRate * timeToMaturity / (360 days * 1e18));

            totalPresentValue += presentValue;

            current = _getNext(_listData, current);
        }

        return totalPresentValue;
    }

    function testGetPresentValueSymbolic(
        uint256 purchaseTokenPrecision
    ) external {
        TermDiscountRateAdapter discountRateAdapter =
            new TermDiscountRateAdapter();

        kevm.symbolicStorage(address(this));
        kevm.symbolicStorage(address(discountRateAdapter));
        _initializeRepoTokenList(discountRateAdapter);

        vm.assume(0 < purchaseTokenPrecision);
        vm.assume(purchaseTokenPrecision <= 18);

        uint256 totalPresentValue = _listData.getPresentValue(
            discountRateAdapter,
            purchaseTokenPrecision
        );

        // Simplified calculation in the case no tokens have matured
        uint256 totalPresentValueNotMatured = _totalPresentValueNotMatured(
            discountRateAdapter,
            purchaseTokenPrecision
        );

        assert(totalPresentValue == totalPresentValueNotMatured);
    }
}
