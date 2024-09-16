pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import "src/interfaces/term/ITermRepoToken.sol";

import "src/test/kontrol/Constants.sol";

contract RepoToken is ITermRepoToken, Test, KontrolCheats {
    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    function balanceOf(address account) public view virtual returns (uint256) {
        uint256 value = freshUInt256();
        vm.assume(value < ETH_UPPER_BOUND);
        return value;
    }

    function redemptionValue() external view returns (uint256) {
        uint256 value = freshUInt256();
        vm.assume(value < ETH_UPPER_BOUND);
        return value;
    }

    function config() external view returns (
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

    function termRepoId() external view returns (bytes32) {
        return bytes32(freshUInt256());
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return freshUInt256();
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        kevm.symbolicStorage(address(this));
        return kevm.freshBool() > 0;
    }

    function totalSupply() external view returns (uint256) {
        return freshUInt256();
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        kevm.symbolicStorage(address(this));
        return kevm.freshBool() > 0;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        kevm.symbolicStorage(address(this));
        return kevm.freshBool() > 0;
    }
}
