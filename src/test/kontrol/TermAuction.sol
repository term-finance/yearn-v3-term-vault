pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import "src/interfaces/term/ITermAuction.sol";

import "src/test/kontrol/Constants.sol";

contract TermAuction is ITermAuction, Test, KontrolCheats {
	bool _auctionCompleted;

    function termAuctionOfferLocker() external view returns (address) {
        return kevm.freshAddress();
    }
    
    function termRepoId() external view returns (bytes32) {
        return bytes32(freshUInt256());
    }

    function auctionEndTime() external view returns (uint256) {
        return freshUInt256();
    }

    function auctionCompleted() external view returns (bool) {
        return _auctionCompleted;
    }

    function auctionCancelledForWithdrawal() external view returns (bool) {
        return kevm.freshBool() > 0;
    }
}
