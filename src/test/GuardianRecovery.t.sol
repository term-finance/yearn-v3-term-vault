// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup, IStrategyInterface} from "./utils/Setup.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

interface IGovernorHandoff {
    function setPendingGovernor(address newGovernor) external;
    function acceptGovernor() external;
}

contract GuardianRecoveryTest is Setup {
    bytes32 internal constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    address internal constant ATTACKER = address(0xBAD);
    address internal constant RESCUE = address(0x9E5);

    function setUp() public virtual override {
        super.setUp();
    }

    function test_guardianHoldsAdminRole() public {
        assertTrue(
            IAccessControl(address(strategy)).hasRole(DEFAULT_ADMIN_ROLE, adminWallet)
        );
        assertTrue(
            IAccessControl(address(strategy)).hasRole(GOVERNOR_ROLE, governor)
        );
    }

    /// Governor handoff is one-way: only the sitting governor can nominate, and only the
    /// nominee can accept. Once a hostile address holds GOVERNOR_ROLE there is no path back
    /// without an admin bearer — this is what left the compromised strategies unrecoverable.
    function test_guardianCanReplaceCompromisedGovernor() public {
        vm.prank(governor);
        IGovernorHandoff(address(strategy)).setPendingGovernor(ATTACKER);
        vm.prank(ATTACKER);
        IGovernorHandoff(address(strategy)).acceptGovernor();

        assertTrue(IAccessControl(address(strategy)).hasRole(GOVERNOR_ROLE, ATTACKER));
        assertFalse(IAccessControl(address(strategy)).hasRole(GOVERNOR_ROLE, governor));

        vm.startPrank(adminWallet);
        IAccessControl(address(strategy)).revokeRole(GOVERNOR_ROLE, ATTACKER);
        IAccessControl(address(strategy)).grantRole(GOVERNOR_ROLE, RESCUE);
        vm.stopPrank();

        assertFalse(IAccessControl(address(strategy)).hasRole(GOVERNOR_ROLE, ATTACKER));
        assertTrue(IAccessControl(address(strategy)).hasRole(GOVERNOR_ROLE, RESCUE));
    }

    function test_nonGuardianCannotReassignGovernor() public {
        vm.prank(ATTACKER);
        vm.expectRevert();
        IAccessControl(address(strategy)).grantRole(GOVERNOR_ROLE, ATTACKER);
    }

    /// A captured governor must not be able to strip the guardian and re-create the
    /// unrecoverable state.
    function test_governorCannotRevokeGuardian() public {
        vm.prank(governor);
        vm.expectRevert();
        IAccessControl(address(strategy)).revokeRole(DEFAULT_ADMIN_ROLE, adminWallet);
    }
}
