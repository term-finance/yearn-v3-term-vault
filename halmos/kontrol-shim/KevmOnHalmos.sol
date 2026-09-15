// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12 <0.9.0;

/// @dev Halmos's symbolic-value cheatcodes (halmos-cheatcodes `SVM`).
interface SVM {
    function createUint(uint256 bitSize, string memory name) external pure returns (uint256);
    function createBool(string memory name) external pure returns (bool);
    function createAddress(string memory name) external pure returns (address);
    function createBytes(uint256 byteSize, string memory name) external pure returns (bytes memory);
    function enableSymbolicStorage(address target) external;
}

/// @title Kontrol's cheatcode surface, answered by Halmos
/// @notice The Kontrol suite calls `kevm.*` at the hevm cheatcode address. Halmos
///         owns that address and does not know Kontrol's selectors, so for Halmos the
///         suite compiles against a KontrolCheats whose `kevm` is this contract.
///         Every cheatcode the suite relies on maps onto an exact Halmos equivalent;
///         every other one reverts, so a test that needs it fails loudly instead of
///         proving something with a cheatcode silently ignored.
contract KevmOnHalmos {
    SVM internal constant svm = SVM(0xF3993A62377BCd56AE39D773740A5390411E8BC9);

    function symbolicStorage(address target) external {
        svm.enableSymbolicStorage(target);
    }

    function freshUInt(uint8 width) external view returns (uint256) {
        return svm.createUint(uint256(width) * 8, "kevm.freshUInt");
    }

    function freshBool() external view returns (uint256) {
        return svm.createBool("kevm.freshBool") ? 1 : 0;
    }

    function freshAddress() external view returns (address) {
        return svm.createAddress("kevm.freshAddress");
    }

    function freshBytes(uint256 size) external view returns (bytes memory) {
        return svm.createBytes(size, "kevm.freshBytes");
    }

    function expectRegularCall(address, bytes calldata) external pure { _unsupported("expectRegularCall"); }
    function expectRegularCall(address, uint256, bytes calldata) external pure { _unsupported("expectRegularCall"); }
    function expectStaticCall(address, bytes calldata) external pure { _unsupported("expectStaticCall"); }
    function expectDelegateCall(address, bytes calldata) external pure { _unsupported("expectDelegateCall"); }
    function expectNoCall() external pure { _unsupported("expectNoCall"); }
    function expectCreate(address, uint256, bytes calldata) external pure { _unsupported("expectCreate"); }
    function expectCreate2(address, uint256, bytes calldata) external pure { _unsupported("expectCreate2"); }
    function copyStorage(address, address) external pure { _unsupported("copyStorage"); }
    function mockFunction(address, address, bytes calldata) external pure { _unsupported("mockFunction"); }
    function allowCallsToAddress(address) external pure { _unsupported("allowCallsToAddress"); }
    function allowChangesToStorage(address, uint256) external pure { _unsupported("allowChangesToStorage"); }
    function infiniteGas() external pure { _unsupported("infiniteGas"); }
    function setGas(uint256) external pure { _unsupported("setGas"); }

    function _unsupported(string memory name) private pure {
        revert(string.concat("KevmOnHalmos: kevm.", name, " has no Halmos equivalent"));
    }
}
