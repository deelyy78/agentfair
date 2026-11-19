// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AgentFair} from "../contracts/AgentFair.sol";
import {MockAgentID} from "../contracts/mocks/MockAgentID.sol";

/// @dev Minimal cheatcode interface (avoids a forge-std dependency).
interface Vm {
    function prank(address sender) external;
    function warp(uint256 newTimestamp) external;
    function expectRevert(bytes4 revertData) external;
}

contract AgentFairTest {
    Vm internal constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    MockAgentID internal mock;
    AgentFair internal fair;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCA401); // no Agent ID
    address internal dave = address(0xDA9E);

    function setUp() public {
        vm.warp(1_700_000_000); // realistic timestamp so day-index math works
        mock = new MockAgentID();
        fair = new AgentFair(address(mock));
        mock.mint(alice);
        mock.mint(bob);
        mock.mint(dave);
    }

    // ---------------------------------------------------------------
    // helpers
    // ---------------------------------------------------------------

    function assertEq(uint256 a, uint256 b, string memory what) internal pure {
        require(a == b, what);
    }

    function assertTrue(bool c, string memory what) internal pure {
        require(c, what);
    }

    function pointsOf(address who) internal view returns (uint256 points) {
        (, , , , points, ) = fair.agents(who);
    }

    function numberOf(address who) internal view returns (uint256 number) {
        (, , , , , number) = fair.agents(who);
    }

    function registerAs(address who) internal {
        vm.prank(who);
        fair.register();
    }

    // ---------------------------------------------------------------
    // registration
    // ---------------------------------------------------------------

    function testRegisterNonHolderReverts() public {
        vm.expectRevert(AgentFair.NoAgentID.selector);
        vm.prank(carol);
        fair.register();
    }

    function testRegisterHolder() public {
        registerAs(alice);
        assertEq(fair.totalAgents(), 1, "totalAgents");
        assertEq(numberOf(alice), 1, "agent number");
        assertEq(pointsOf(alice), 50, "welcome points");
        assertTrue(fair.isAgentHolder(alice), "isAgentHolder");
    }

    function testDoubleRegisterReverts() public {
        registerAs(alice);
        vm.expectRevert(AgentFair.AlreadyRegistered.selector);
        vm.prank(alice);
        fair.register();
    }

    // ---------------------------------------------------------------
    // check-in
    // ---------------------------------------------------------------

    function testCheckInUnregisteredReverts() public {
        vm.expectRevert(AgentFair.NotRegistered.selector);
        vm.prank(bob); // holds an Agent ID but never registered
        fair.checkIn();
    }

    function testCheckInStreaks() public {
        registerAs(alice);
        vm.prank(alice);
        fair.checkIn();
        assertEq(pointsOf(alice), 60, "points after first check-in");

        // same UTC day again -> revert
        vm.expectRevert(AgentFair.AlreadyCheckedInToday.selector);
        vm.prank(alice);
        fair.checkIn();

        // next day -> streak 2, +12 points (10 + 2 streak bonus)
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(alice);
        fair.checkIn();
        (, , uint32 streak, , , ) = fair.agents(alice);
        assertEq(streak, 2, "streak day 2");
        assertEq(pointsOf(alice), 72, "points day 2");

        // skip 3 days -> streak resets to 1
        vm.warp(block.timestamp + 3 days);
        vm.prank(alice);
        fair.checkIn();
        (, , uint32 streak2, , , ) = fair.agents(alice);
        assertEq(streak2, 1, "streak reset");
        assertEq(fair.totalCheckIns(), 3, "totalCheckIns");
    }

    // ---------------------------------------------------------------
    // drops + claims
    // ---------------------------------------------------------------

    function testCreateDropValidation() public {
        registerAs(alice);
        vm.expectRevert(AgentFair.EmptyTitle.selector);
        vm.prank(alice);
        fair.createDrop("", "uri", 10, 7 days);

        vm.expectRevert(AgentFair.InvalidSlots.selector);
        vm.prank(alice);
        fair.createDrop("T", "uri", 0, 7 days);

        vm.expectRevert(AgentFair.InvalidDuration.selector);
        vm.prank(alice);
        fair.createDrop("T", "uri", 10, 30 minutes);
    }

    function testClaimFlowOnePerAgentID() public {
        registerAs(alice);
        registerAs(bob);
        registerAs(dave);

        vm.prank(alice);
        uint256 dropId = fair.createDrop("Genesis Drop", "https://example.com/drop", 2, 7 days);
        assertEq(dropId, 0, "drop id");
        assertEq(fair.dropCount(), 1, "dropCount");

        // bob claims -> +20 points
        vm.prank(bob);
        fair.claim(dropId);
        assertTrue(fair.hasClaimed(dropId, bob), "bob claimed");
        assertEq(pointsOf(bob), 70, "bob points after claim");

        // bob cannot claim twice
        vm.expectRevert(AgentFair.AlreadyClaimed.selector);
        vm.prank(bob);
        fair.claim(dropId);

        // carol has no Agent ID -> cannot claim at all
        vm.expectRevert(AgentFair.NoAgentID.selector);
        vm.prank(carol);
        fair.claim(dropId);

        // alice takes the last slot
        vm.prank(alice);
        fair.claim(dropId);
        (, , , , , uint32 slots, uint32 claimed, ) = fair.getDrop(dropId);
        assertEq(slots, 2, "slots");
        assertEq(claimed, 2, "claimed full");

        // dave is too late -> full
        vm.expectRevert(AgentFair.DropFull.selector);
        vm.prank(dave);
        fair.claim(dropId);

        assertEq(fair.totalClaims(), 2, "totalClaims");
    }

    function testClaimAfterEndReverts() public {
        registerAs(alice);
        registerAs(bob);
        vm.prank(alice);
        uint256 dropId = fair.createDrop("Short Drop", "uri", 5, 1 hours);
        vm.warp(block.timestamp + 2 hours);
        vm.expectRevert(AgentFair.DropEnded.selector);
        vm.prank(bob);
        fair.claim(dropId);
    }

    function testCancelOnlyCreatorAndBlocksClaims() public {
        registerAs(alice);
        registerAs(bob);
        vm.prank(alice);
        uint256 dropId = fair.createDrop("Cancellable", "uri", 5, 7 days);

        vm.expectRevert(AgentFair.NotCreator.selector);
        vm.prank(bob);
        fair.cancelDrop(dropId);

        vm.prank(alice);
        fair.cancelDrop(dropId);

        vm.expectRevert(AgentFair.DropCancelled_.selector);
        vm.prank(bob);
        fair.claim(dropId);
    }
}
