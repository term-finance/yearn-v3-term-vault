pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import "src/interfaces/term/ITermAuctionOfferLocker.sol";

import "src/test/kontrol/Constants.sol";

contract TermAuctionOfferLocker is ITermAuctionOfferLocker, Test, KontrolCheats {
    mapping(bytes32 => TermAuctionOffer) _lockedOffers;

    function termRepoId() external view returns (bytes32) {
        return bytes32(freshUInt256());
    }

    function termAuctionId() external view returns (bytes32) {
        return bytes32(freshUInt256());
    }

    function auctionStartTime() external view returns (uint256) {
        return freshUInt256();
    }

    function auctionEndTime() external view returns (uint256) {
        return freshUInt256();
    }

    function revealTime() external view returns (uint256) {
        return freshUInt256();
    }

    function purchaseToken() external view returns (address) {
        return kevm.freshAddress();
    }

    function termRepoServicer() external view returns (address) {
        return kevm.freshAddress();
    }

    function lockedOffer(bytes32 id) external view returns (TermAuctionOffer memory) {
        TermAuctionOffer memory offer = _lockedOffers[id];

        vm.assume(offer.offerPriceRevealed < ETH_UPPER_BOUND);
        vm.assume(offer.amount < ETH_UPPER_BOUND);

        /*
        offer.id = bytes32(freshUInt256());
        offer.offeror = kevm.freshAddress();
        offer.offerPriceHash = bytes32(freshUInt256());
        offer.offerPriceRevealed = freshUInt256();
        vm.assume(offer.offerPriceRevealed < ETH_UPPER_BOUND);
        offer.amount = freshUInt256();
        vm.assume(offer.amount < ETH_UPPER_BOUND);
        offer.purchaseToken = kevm.freshAddress();
        offer.isRevealed = kevm.freshBool() > 0;
        */

        return offer;
    }

    function lockOffers(
        TermAuctionOfferSubmission[] calldata offerSubmissions
    ) external returns (bytes32[] memory) {
        kevm.symbolicStorage(address(this));

        uint256 length = freshUInt256();
        bytes32[] memory offers = new bytes32[](length);

        for (uint256 i = 0; i < length; ++i) {
            offers[i] = bytes32(freshUInt256());
        }

        return offers;
    }

    function unlockOffers(bytes32[] calldata offerIds) external {
        kevm.symbolicStorage(address(this));
    }
}
