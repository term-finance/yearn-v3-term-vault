// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {MetaVaultAllocationHelper} from "../helper/MetaVaultAllocationHelper.sol";
import {MockMetaVault} from "./mocks/MockMetaVault.sol";

/**
 * @title MetaVaultAllocationHelperTest
 * @notice Unit tests for MetaVaultAllocationHelper — storing allocation targets,
 *         reading them back, and the stale-strategy rescale path.
 */
contract MetaVaultAllocationHelperTest is Test {
    MetaVaultAllocationHelper public helper;
    MockMetaVault public vault;

    address public allocator = address(0xA11);
    address public notAllocator = address(0xBAD);

    address public s1 = address(0x51);
    address public s2 = address(0x52);
    address public s3 = address(0x53);
    address public s4 = address(0x54);

    event AllocationsUpdated(
        address indexed metavault,
        address indexed caller,
        address[] strategies,
        uint256[] bpsTargets,
        uint256 timestamp
    );

    function setUp() public {
        helper = new MetaVaultAllocationHelper(allocator);
        vault = new MockMetaVault(address(0xA55E7));

        vault.activateStrategy(s1);
        vault.activateStrategy(s2);
        vault.activateStrategy(s3);
        vault.activateStrategy(s4);
    }

    // ─────────────────────────────────────────────────────────
    //  Set / get — happy path
    // ─────────────────────────────────────────────────────────

    function test_SetAndGetAllocations() public {
        _set(_addrs(s1, s2, s3), _bps(5000, 3000, 2000));

        assertEq(helper.strategyCount(address(vault)), 3, "count");
        assertEq(helper.getAllocation(address(vault), s1), 5000, "s1 bps");
        assertEq(helper.getAllocation(address(vault), s2), 3000, "s2 bps");
        assertEq(helper.getAllocation(address(vault), s3), 2000, "s3 bps");

        (address[] memory strats, uint256[] memory bps) = helper.getAllocations(
            address(vault)
        );
        assertEq(strats.length, 3, "list length");
        assertEq(bps.length, 3, "bps length");

        // Insertion order is preserved
        assertEq(strats[0], s1);
        assertEq(strats[1], s2);
        assertEq(strats[2], s3);
        assertEq(bps[0], 5000);
        assertEq(bps[1], 3000);
        assertEq(bps[2], 2000);
        assertEq(bps[0] + bps[1] + bps[2], 10_000, "sums to 10000");
    }

    function test_GetAllocation_UnknownStrategyReturnsZero() public {
        _set(_addrs(s1, s2, s3), _bps(5000, 3000, 2000));
        assertEq(helper.getAllocation(address(vault), address(0xDEAD)), 0);
    }

    function test_GetActiveAllocations_NoStaleReturnsStoredSet() public {
        _set(_addrs(s1, s2, s3), _bps(5000, 3000, 2000));

        (address[] memory strats, uint256[] memory bps, bool hasStale) = helper
            .getActiveAllocations(address(vault));

        assertFalse(hasStale, "no stale entries");
        assertEq(strats.length, 3);
        assertEq(strats[0], s1);
        assertEq(strats[1], s2);
        assertEq(strats[2], s3);
        assertEq(bps[0], 5000);
        assertEq(bps[1], 3000);
        assertEq(bps[2], 2000);
        assertEq(bps[0] + bps[1] + bps[2], 10_000);
    }

    /// @dev A 0 bps target is legal and must survive the read path untouched
    ///      when nothing is stale.
    function test_GetActiveAllocations_ZeroBpsEntryIsPreservedWhenNoStale()
        public
    {
        _set(_addrs(s1, s2, s3), _bps(10_000, 0, 0));

        (address[] memory strats, uint256[] memory bps, bool hasStale) = helper
            .getActiveAllocations(address(vault));

        assertFalse(hasStale);
        assertEq(strats.length, 3);
        assertEq(bps[0], 10_000);
        assertEq(bps[1], 0);
        assertEq(bps[2], 0);
    }

    function test_SetAllocations_EmitsEvent() public {
        address[] memory strats = _addrs(s1, s2, s3);
        uint256[] memory bps = _bps(5000, 3000, 2000);

        vm.expectEmit(true, true, false, true);
        emit AllocationsUpdated(
            address(vault),
            allocator,
            strats,
            bps,
            block.timestamp
        );

        vm.prank(allocator);
        helper.setAllocations(address(vault), strats, bps);
    }

    // ─────────────────────────────────────────────────────────
    //  Replacement semantics
    // ─────────────────────────────────────────────────────────

    /// @dev Full replace must clear dropped entries and update carried-over ones
    ///      in place — a carried-over strategy must NOT be treated as a duplicate.
    function test_SetAllocations_ReplacesPreviousSet() public {
        _set(_addrs(s1, s2, s3), _bps(5000, 3000, 2000));

        address[] memory next = new address[](2);
        next[0] = s3;
        next[1] = s4;
        uint256[] memory nextBps = new uint256[](2);
        nextBps[0] = 6000;
        nextBps[1] = 4000;
        _set(next, nextBps);

        assertEq(helper.strategyCount(address(vault)), 2, "count shrank");

        // Dropped entries fully cleared
        assertEq(helper.getAllocation(address(vault), s1), 0, "s1 cleared");
        assertEq(helper.getAllocation(address(vault), s2), 0, "s2 cleared");

        // Carried-over entry updated, not duplicated
        assertEq(helper.getAllocation(address(vault), s3), 6000, "s3 updated");
        assertEq(helper.getAllocation(address(vault), s4), 4000, "s4 added");

        (address[] memory strats, ) = helper.getAllocations(address(vault));
        assertEq(strats.length, 2);
        assertEq(strats[0], s3);
        assertEq(strats[1], s4);
    }

    function test_SetAllocations_IsPerVaultIsolated() public {
        MockMetaVault vault2 = new MockMetaVault(address(0xA55E7));
        vault2.activateStrategy(s1);
        vault2.activateStrategy(s2);

        _set(_addrs(s1, s2, s3), _bps(5000, 3000, 2000));

        address[] memory strats2 = new address[](2);
        strats2[0] = s1;
        strats2[1] = s2;
        uint256[] memory bps2 = new uint256[](2);
        bps2[0] = 1000;
        bps2[1] = 9000;
        vm.prank(allocator);
        helper.setAllocations(address(vault2), strats2, bps2);

        assertEq(helper.strategyCount(address(vault)), 3);
        assertEq(helper.strategyCount(address(vault2)), 2);
        assertEq(helper.getAllocation(address(vault), s1), 5000);
        assertEq(helper.getAllocation(address(vault2), s1), 1000);
    }

    // ─────────────────────────────────────────────────────────
    //  Stale filtering and rescale
    // ─────────────────────────────────────────────────────────

    function test_GetActiveAllocations_RescalesProportionallyOnStale() public {
        _set(_addrs(s1, s2, s3), _bps(5000, 3000, 2000));

        vault.deactivateStrategy(s1);

        (address[] memory strats, uint256[] memory bps, bool hasStale) = helper
            .getActiveAllocations(address(vault));

        assertTrue(hasStale, "stale flagged");
        assertEq(strats.length, 2, "stale entry dropped");
        assertEq(strats[0], s2);
        assertEq(strats[1], s3);

        // 3000:2000 rescaled against activeSum 5000 => 6000:4000
        assertEq(bps[0], 6000);
        assertEq(bps[1], 4000);
        assertEq(bps[0] + bps[1], 10_000, "rescale sums to 10000");
    }

    /// @dev Rounding dust must land on the last strategy so the total is exact.
    function test_GetActiveAllocations_RoundingDustGoesToLastStrategy() public {
        address[] memory strats4 = new address[](4);
        strats4[0] = s1;
        strats4[1] = s2;
        strats4[2] = s3;
        strats4[3] = s4;
        uint256[] memory bps4 = new uint256[](4);
        bps4[0] = 1000;
        bps4[1] = 2000;
        bps4[2] = 3000;
        bps4[3] = 4000;
        _set(strats4, bps4);

        vault.deactivateStrategy(s4);

        (address[] memory strats, uint256[] memory bps, bool hasStale) = helper
            .getActiveAllocations(address(vault));

        assertTrue(hasStale);
        assertEq(strats.length, 3);

        // activeSum 6000: floor(1000*1e4/6000)=1666, floor(2000*1e4/6000)=3333,
        // last absorbs the remainder => 5001 (exact share would be 5000)
        assertEq(bps[0], 1666);
        assertEq(bps[1], 3333);
        assertEq(bps[2], 5001, "last strategy absorbs dust");
        assertEq(bps[0] + bps[1] + bps[2], 10_000, "still exactly 10000");
    }

    function test_GetActiveAllocations_AllStaleReturnsEmpty() public {
        _set(_addrs(s1, s2, s3), _bps(5000, 3000, 2000));

        vault.deactivateStrategy(s1);
        vault.deactivateStrategy(s2);
        vault.deactivateStrategy(s3);

        (address[] memory strats, uint256[] memory bps, bool hasStale) = helper
            .getActiveAllocations(address(vault));

        assertTrue(hasStale);
        assertEq(strats.length, 0, "empty, not reverting");
        assertEq(bps.length, 0);
    }

    function test_GetActiveAllocations_UnknownVaultReturnsEmpty() public view {
        (address[] memory strats, , bool hasStale) = helper
            .getActiveAllocations(address(0xF00D));
        assertEq(strats.length, 0);
        assertFalse(hasStale);
    }

    function test_GetStaleStrategies() public {
        _set(_addrs(s1, s2, s3), _bps(5000, 3000, 2000));
        assertEq(
            helper.getStaleStrategies(address(vault)).length,
            0,
            "none stale yet"
        );

        vault.deactivateStrategy(s2);

        address[] memory stale = helper.getStaleStrategies(address(vault));
        assertEq(stale.length, 1);
        assertEq(stale[0], s2);
    }

    // ─────────────────────────────────────────────────────────
    //  Zero-active-weight guard
    // ─────────────────────────────────────────────────────────

    /// @dev Regression: activeSum == 0 with 2+ survivors used to divide by zero.
    function test_RevertWhen_ZeroActiveWeightWithMultipleSurvivors() public {
        _set(_addrs(s1, s2, s3), _bps(10_000, 0, 0));

        vault.deactivateStrategy(s1);

        vm.expectRevert("no active allocation weight");
        helper.getActiveAllocations(address(vault));
    }

    /// @dev Regression: a single zero-bps survivor used to be silently reported
    ///      at 10_000 bps via the dust fallback.
    function test_RevertWhen_ZeroActiveWeightWithSingleSurvivor() public {
        address[] memory strats = new address[](2);
        strats[0] = s1;
        strats[1] = s2;
        uint256[] memory bps = new uint256[](2);
        bps[0] = 10_000;
        bps[1] = 0;
        _set(strats, bps);

        vault.deactivateStrategy(s1);

        vm.expectRevert("no active allocation weight");
        helper.getActiveAllocations(address(vault));
    }

    /// @dev The guard must not fire while any active strategy still carries weight.
    function test_GetActiveAllocations_GuardDoesNotOverfire() public {
        _set(_addrs(s1, s2, s3), _bps(0, 4000, 6000));

        vault.deactivateStrategy(s1);

        (address[] memory strats, uint256[] memory bps, ) = helper
            .getActiveAllocations(address(vault));
        assertEq(strats.length, 2);
        assertEq(bps[0] + bps[1], 10_000);
    }

    // ─────────────────────────────────────────────────────────
    //  Duplicate rejection
    // ─────────────────────────────────────────────────────────

    /// @dev Regression: duplicates used to pass and report a total above 10_000.
    function test_RevertWhen_DuplicateStrategyNonAdjacent() public {
        vm.prank(allocator);
        vm.expectRevert("duplicate strategy");
        helper.setAllocations(
            address(vault),
            _addrs(s1, s2, s1),
            _bps(2000, 3000, 5000)
        );
    }

    function test_RevertWhen_DuplicateStrategyAdjacent() public {
        vm.prank(allocator);
        vm.expectRevert("duplicate strategy");
        helper.setAllocations(
            address(vault),
            _addrs(s1, s1, s2),
            _bps(2000, 3000, 5000)
        );
    }

    // ─────────────────────────────────────────────────────────
    //  Access control and input validation
    // ─────────────────────────────────────────────────────────

    function test_RevertWhen_CallerNotAllocator() public {
        vm.prank(notAllocator);
        vm.expectRevert("not allocator");
        helper.setAllocations(
            address(vault),
            _addrs(s1, s2, s3),
            _bps(5000, 3000, 2000)
        );
    }

    function test_RevertWhen_SumNotTenThousand() public {
        vm.prank(allocator);
        vm.expectRevert("must sum to 10000 bps");
        helper.setAllocations(
            address(vault),
            _addrs(s1, s2, s3),
            _bps(5000, 3000, 1000)
        );
    }

    function test_RevertWhen_LengthMismatch() public {
        uint256[] memory bps = new uint256[](2);
        bps[0] = 5000;
        bps[1] = 5000;

        vm.prank(allocator);
        vm.expectRevert("length mismatch");
        helper.setAllocations(address(vault), _addrs(s1, s2, s3), bps);
    }

    function test_RevertWhen_Empty() public {
        vm.prank(allocator);
        vm.expectRevert("empty");
        helper.setAllocations(
            address(vault),
            new address[](0),
            new uint256[](0)
        );
    }

    function test_RevertWhen_SingleEntryExceedsTenThousand() public {
        address[] memory strats = new address[](2);
        strats[0] = s1;
        strats[1] = s2;
        uint256[] memory bps = new uint256[](2);
        bps[0] = 10_001;
        bps[1] = 0;

        vm.prank(allocator);
        vm.expectRevert("bps overflow");
        helper.setAllocations(address(vault), strats, bps);
    }

    function test_RevertWhen_StrategyNotActiveInVault() public {
        vault.deactivateStrategy(s2);

        vm.prank(allocator);
        vm.expectRevert("strategy not active in vault");
        helper.setAllocations(
            address(vault),
            _addrs(s1, s2, s3),
            _bps(5000, 3000, 2000)
        );
    }

    /// @dev A failed setAllocations must leave the prior set untouched.
    function test_FailedSetAllocations_LeavesPriorStateIntact() public {
        _set(_addrs(s1, s2, s3), _bps(5000, 3000, 2000));

        vm.prank(allocator);
        vm.expectRevert("duplicate strategy");
        helper.setAllocations(
            address(vault),
            _addrs(s4, s4, s1),
            _bps(2000, 3000, 5000)
        );

        assertEq(helper.strategyCount(address(vault)), 3, "prior set intact");
        assertEq(helper.getAllocation(address(vault), s1), 5000);
        assertEq(helper.getAllocation(address(vault), s2), 3000);
        assertEq(helper.getAllocation(address(vault), s3), 2000);
        assertEq(helper.getAllocation(address(vault), s4), 0);
    }

    function test_ConstructorRevertsOnZeroAllocator() public {
        vm.expectRevert("zero address");
        new MetaVaultAllocationHelper(address(0));
    }

    function test_AllocatorIsSet() public view {
        assertEq(helper.allocator(), allocator);
    }

    // ─────────────────────────────────────────────────────────
    //  Helpers
    // ─────────────────────────────────────────────────────────

    function _set(address[] memory strats, uint256[] memory bps) internal {
        vm.prank(allocator);
        helper.setAllocations(address(vault), strats, bps);
    }

    function _addrs(
        address a,
        address b,
        address c
    ) internal pure returns (address[] memory arr) {
        arr = new address[](3);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
    }

    function _bps(
        uint256 a,
        uint256 b,
        uint256 c
    ) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](3);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
    }
}
