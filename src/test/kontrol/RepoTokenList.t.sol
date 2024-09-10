pragma solidity 0.8.23;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import "src/RepoTokenList.sol";

uint256 constant ETH_UPPER_BOUND = 2 ** 95;
uint256 constant TIME_UPPER_BOUND = 2 ** 35;

contract RepoToken is /*ITermRepoToken,*/ Test, KontrolCheats {
    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    function balanceOf(address account) public /*view*/ virtual returns (uint256) {
        uint256 value = freshUInt256();
        vm.assume(value < ETH_UPPER_BOUND);
        return value;
    }

    function redemptionValue() external /*view*/ returns (uint256) {
        uint256 value = freshUInt256();
        vm.assume(value < ETH_UPPER_BOUND);
        return value;
    }

    function config() external /*view*/ returns (
        uint256 redemptionTimestamp,
        address purchaseToken,
        address termRepoServicer,
        address termRepoCollateralManager
    ) {
        redemptionTimestamp = freshUInt256();
        vm.assume(redemptionTimestamp < TIME_UPPER_BOUND);
        purchaseToken = kevm.freshAddress();
        termRepoServicer = kevm.freshAddress();
        termRepoCollateralManager = kevm.freshAddress();
    }

    function termRepoId() external /*view*/ returns (bytes32) {
        return bytes32(freshUInt256());
    }
}

contract TermDiscountRateAdapter is /*ITermDiscountRateAdapter,*/ Test, KontrolCheats {
    function repoRedemptionHaircut(address) external /*view*/ returns (uint256) {
        uint256 value = freshUInt256();
        vm.assume(value <= 1e18);
        return value;
    }

    function getDiscountRate(address repoToken) external /*view*/ returns (uint256) {
        uint256 value = freshUInt256();
        vm.assume(0 < value);
        vm.assume(value < ETH_UPPER_BOUND);
        return value;
    }
}

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
        uint256 purchaseTokenPrecision,
        address repoTokenToMatch
    ) external {
        _initializeListEmpty();

        TermDiscountRateAdapter discountRateAdapter =
            new TermDiscountRateAdapter();

        uint256 totalPresentValue = _listData.getPresentValue(
            ITermDiscountRateAdapter(address(discountRateAdapter)),
            purchaseTokenPrecision,
            repoTokenToMatch
        );

        assert(totalPresentValue == 0);
    }

    function _getNext(RepoTokenListData storage listData, address current) private view returns (address) {
        return listData.nodes[current].next;
    }

    function _initializeRepoTokenList() internal {
        address previous = RepoTokenList.NULL_NODE;
        address current = _listData.head;

        while (current != RepoTokenList.NULL_NODE) {
            RepoToken repoToken = new RepoToken();
            address newCurrent = address(repoToken);

            if (previous == RepoTokenList.NULL_NODE) {
                _listData.head = newCurrent;
            } else {
                _listData.nodes[previous].next = newCurrent;
            }

            uint256 discountRate = freshUInt256();
            vm.assume(0 < discountRate);
            vm.assume(discountRate < ETH_UPPER_BOUND);
            _listData.discountRates[newCurrent] = discountRate;

            previous = newCurrent;
            current = _getNext(_listData, newCurrent);
        }
    }

    function testGetCumulativeDataSymbolic(
        address repoToken,
        uint256 repoTokenAmount,
        uint256 purchaseTokenPrecision
    ) external {
        kevm.symbolicStorage(address(this));
        _initializeRepoTokenList();

        TermDiscountRateAdapter discountRateAdapter =
            new TermDiscountRateAdapter();

        vm.assume(repoTokenAmount < ETH_UPPER_BOUND);
        vm.assume(purchaseTokenPrecision <= 18);

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
    }

    function testGetPresentValueSymbolic(
        uint256 purchaseTokenPrecision,
        address repoTokenToMatch
    ) external {
        kevm.symbolicStorage(address(this));
        _initializeRepoTokenList();

        TermDiscountRateAdapter discountRateAdapter =
            new TermDiscountRateAdapter();

        vm.assume(0 < purchaseTokenPrecision);
        vm.assume(purchaseTokenPrecision <= 18);

        uint256 totalPresentValue = _listData.getPresentValue(
            ITermDiscountRateAdapter(address(discountRateAdapter)),
            purchaseTokenPrecision,
            repoTokenToMatch
        );
    }
}
