pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import "src/interfaces/term/ITermDiscountRateAdapter.sol";

import "src/test/kontrol/Constants.sol";

contract TermDiscountRateAdapter is ITermDiscountRateAdapter, Test, KontrolCheats {
    mapping(address => uint256) _repoRedemptionHaircut;
    mapping(address => uint256) _discountRate;

    function initializeSymbolicFor(address repoToken) public {
        _repoRedemptionHaircut[repoToken] = freshUInt256();
        vm.assume(_repoRedemptionHaircut[repoToken] <= 1e18);

        _discountRate[repoToken] = freshUInt256();
        vm.assume(0 < _discountRate[repoToken]);
        vm.assume(_discountRate[repoToken] < ETH_UPPER_BOUND);
    }

    function repoRedemptionHaircut(address repoToken) external view returns (uint256) {
        return _repoRedemptionHaircut[repoToken];
    }

    function getDiscountRate(address repoToken) external view returns (uint256) {
        return _discountRate[repoToken];
    }

    function TERM_CONTROLLER() external view returns (ITermController) {
        return ITermController(kevm.freshAddress());
    }
}
