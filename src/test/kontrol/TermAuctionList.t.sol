pragma solidity 0.8.23;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import "src/RepoTokenList.sol";
import "src/TermAuctionList.sol";

import "src/test/kontrol/Constants.sol";
import "src/test/kontrol/RepoToken.sol";
import "src/test/kontrol/TermAuction.sol";
import "src/test/kontrol/TermAuctionOfferLocker.sol";
import "src/test/kontrol/TermDiscountRateAdapter.sol";

contract TermAuctionListTest is Test, KontrolCheats {
    using TermAuctionList for TermAuctionListData;

    RepoTokenListData _repoTokenListData;
    TermAuctionListData _listData;

    function _initializeListEmpty() internal {
        _listData.head = TermAuctionList.NULL_NODE;
    }

    function testGetCumulativeDataEmpty(
        address repoToken,
        uint256 newOfferAmount,
        uint256 purchaseTokenPrecision
    ) external {
        kevm.symbolicStorage(address(this));
        _initializeListEmpty();

        TermDiscountRateAdapter discountRateAdapter =
            new TermDiscountRateAdapter();

        (
            uint256 cumulativeWeightedTimeToMaturity,
            uint256 cumulativeOfferAmount,
            bool found
        ) = _listData.getCumulativeOfferData(
            _repoTokenListData,
            ITermDiscountRateAdapter(address(discountRateAdapter)),
            repoToken,
            newOfferAmount,
            purchaseTokenPrecision
        );

        assert(cumulativeWeightedTimeToMaturity == 0);
        assert(cumulativeOfferAmount == 0);
        assert(found == false);
    }

    function testGetPresentValueEmpty(
        uint256 purchaseTokenPrecision,
        address repoTokenToMatch
    ) external {
        kevm.symbolicStorage(address(this));
        _initializeListEmpty();

        TermDiscountRateAdapter discountRateAdapter =
            new TermDiscountRateAdapter();

        uint256 totalPresentValue = _listData.getPresentValue(
            _repoTokenListData,
            ITermDiscountRateAdapter(address(discountRateAdapter)),
            purchaseTokenPrecision,
            repoTokenToMatch
        );

        assert(totalPresentValue == 0);
    }

    function _getNext(TermAuctionListData storage listData, bytes32 current) private view returns (bytes32) {
        return listData.nodes[current].next;
    }

    function _getOfferStorageSlot(bytes32 offerId) internal view returns (uint256) {
        uint256 listDataStorageSlot;

        assembly {
            listDataStorageSlot := _listData.slot
        }

        uint256 offersMappingStorageSlot = listDataStorageSlot + 2;

        return uint256(keccak256(abi.encode(offerId, offersMappingStorageSlot)));
    }

    function _storeUInt256(uint256 storageSlot, uint256 value) internal {
        vm.store(address(this), bytes32(storageSlot), bytes32((value)));
    }

    function _storeAddress(uint256 storageSlot, address value) internal {
        vm.store(address(this), bytes32(storageSlot), bytes32(uint256(uint160(value))));
    }

    function _initializeTermAuctionList(
        TermDiscountRateAdapter discountRateAdapter
    ) internal {
        bytes32 previous = TermAuctionList.NULL_NODE;
        uint256 count = 0;

        while (kevm.freshBool() != 0) {
            RepoToken repoToken = new RepoToken();
            repoToken.initializeSymbolic();

            TermAuction termAuction = new TermAuction();
            kevm.symbolicStorage(address(termAuction));
            uint256 auctionCompleted = freshUInt256();
            vm.assume(auctionCompleted < 2);
            vm.store(address(termAuction), bytes32(uint256(27)), bytes32(auctionCompleted));

            TermAuctionOfferLocker offerLocker = new TermAuctionOfferLocker();
            kevm.symbolicStorage(address(offerLocker));

            uint256 offerAmount = freshUInt256();
            vm.assume(0 < offerAmount);

            bytes32 current = keccak256(abi.encodePacked(count, address(this), address(offerLocker)));
            ++count;

            if (previous == TermAuctionList.NULL_NODE) {
                _listData.head = current;
            } else {
                _listData.nodes[previous].next = current;
            }

            // Necessary to overwrite entire storage slot, makes expressions simpler
            uint256 offerStorageSlot = _getOfferStorageSlot(current);
            _storeAddress(offerStorageSlot, address(repoToken));
            _storeUInt256(offerStorageSlot + 1, offerAmount);
            _storeAddress(offerStorageSlot + 2, address(termAuction));
            _storeAddress(offerStorageSlot + 3, address(offerLocker));

            bool offerAmountIsZero = offerLocker.lockedOffer(current).amount == 0;
            bool auctionIsCompleted = termAuction.auctionCompleted();
            vm.assume(offerAmountIsZero == auctionIsCompleted);

            discountRateAdapter.initializeSymbolicFor(address(repoToken));

            previous = current;
        }

        if (previous == TermAuctionList.NULL_NODE) {
            _listData.head = TermAuctionList.NULL_NODE;
        } else {
            _listData.nodes[previous].next = TermAuctionList.NULL_NODE;
        }
    }

    /*
    function _initializeTermAuctionList() internal {
        bytes32 previous = TermAuctionList.NULL_NODE;
        bytes32 current = _listData.head;
        uint256 count = 0;

        while (current != TermAuctionList.NULL_NODE) {
            bytes32 newCurrent = bytes32(freshUInt256());
            vm.assume(newCurrent != bytes32(0));

            if (previous == TermAuctionList.NULL_NODE) {
                _listData.head = newCurrent;
            } else {
                _listData.nodes[previous].next = newCurrent;
            }

            bytes32 offerId = _listData.head;

            for (uint256 i = 0; i < count; ++i) {
                vm.assume(newCurrent != offerId);
                offerId = _getNext(_listData, offerId);
            }

            ++count;

            address repoToken = address(new RepoToken());
            uint256 offerAmount = freshUInt256();
            address termAuction = address(new TermAuction());
            address offerLocker = address(new TermAuctionOfferLocker());

            uint256 offerStorageSlot = _getOfferStorageSlot(newCurrent);
            _storeAddress(offerStorageSlot, repoToken);
            _storeUInt256(offerStorageSlot + 1, offerAmount);
            _storeAddress(offerStorageSlot + 2, termAuction);
            _storeAddress(offerStorageSlot + 3, offerLocker);

            previous = newCurrent;
            current = _getNext(_listData, newCurrent);
        }
    }
    */

    function testGetCumulativeDataSymbolic(
        address repoToken,
        uint256 newOfferAmount,
        uint256 purchaseTokenPrecision
    ) external {
        TermDiscountRateAdapter discountRateAdapter =
            new TermDiscountRateAdapter();

        kevm.symbolicStorage(address(this));
        kevm.symbolicStorage(address(discountRateAdapter));
        _initializeTermAuctionList(discountRateAdapter);

        vm.assume(newOfferAmount < ETH_UPPER_BOUND);
        vm.assume(purchaseTokenPrecision <= 18);

        (
            uint256 cumulativeWeightedTimeToMaturity,
            uint256 cumulativeOfferAmount,
            bool found
        ) = _listData.getCumulativeOfferData(
            _repoTokenListData,
            ITermDiscountRateAdapter(address(discountRateAdapter)),
            repoToken,
            newOfferAmount,
            purchaseTokenPrecision
        );
    }

    function testGetPresentValueSymbolic(
        uint256 purchaseTokenPrecision,
        address repoTokenToMatch
    ) external {
        TermDiscountRateAdapter discountRateAdapter =
            new TermDiscountRateAdapter();

        kevm.symbolicStorage(address(this));
        kevm.symbolicStorage(address(discountRateAdapter));
        _initializeTermAuctionList(discountRateAdapter);

        vm.assume(0 < purchaseTokenPrecision);
        vm.assume(purchaseTokenPrecision <= 18);

        uint256 totalPresentValue = _listData.getPresentValue(
            _repoTokenListData,
            ITermDiscountRateAdapter(address(discountRateAdapter)),
            purchaseTokenPrecision,
            repoTokenToMatch
        );
    }
}
