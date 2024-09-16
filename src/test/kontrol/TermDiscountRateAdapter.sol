pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import "src/interfaces/term/ITermDiscountRateAdapter.sol";

import "src/test/kontrol/Constants.sol";

contract TermDiscountRateAdapter is ITermDiscountRateAdapter, Test, KontrolCheats {
    function repoRedemptionHaircut(address) external view returns (uint256) {
        uint256 value = freshUInt256();
        vm.assume(value <= 1e18);
        return value;
    }

    function getDiscountRate(address repoToken) external view returns (uint256) {
        uint256 value = freshUInt256();
        vm.assume(0 < value);
        vm.assume(value < ETH_UPPER_BOUND);
        return value;
    }

    function TERM_CONTROLLER() external view returns (ITermController) {
        return ITermController(kevm.freshAddress());
    }
}
