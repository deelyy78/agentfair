// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AgentFair} from "../contracts/AgentFair.sol";

/// @dev Minimal cheatcode interface (avoids a forge-std dependency).
interface VmFork {
    function prank(address sender) external;
    function expectRevert(bytes4 revertData) external;
}

/// @notice Fork test against the REAL SPACE ID Agent ID registry on BNB Chain.
/// @dev Run: forge test --match-contract AgentFairForkTest --fork-url https://bsc.publicnode.com
///      BAW holds Agent ID "deelee.ai" (balanceOf == 1, verified on-chain
///      2026-11-19); EXT holds none (balanceOf == 0) and is the control.
contract AgentFairForkTest {
    VmFork internal constant vm = VmFork(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    address internal constant REGISTRY = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;
    address internal constant BAW = 0x9d3A4B1f0DE62089832DB9F755f2033B14C58e37; // deelee.ai holder
    address internal constant EXT = 0x75c1E73Eb5DBd97e66093D9dffc8CA77EAE2cb70; // no Agent ID

    AgentFair internal fair;

    function setUp() public {
        fair = new AgentFair(REGISTRY);
    }

    function testForkRealRegistryGating() public {
        require(fair.isAgentHolder(BAW), "BAW should hold an Agent ID");
        require(!fair.isAgentHolder(EXT), "EXT should NOT hold an Agent ID");

        // Non-holder is rejected by the real registry check.
        vm.expectRevert(AgentFair.NoAgentID.selector);
        vm.prank(EXT);
        fair.register();

        // Real holder completes the full loop on fork state.
        vm.prank(BAW);
        fair.register();

        vm.prank(BAW);
        fair.checkIn();

        vm.prank(BAW);
        uint256 dropId = fair.createDrop("Fork Genesis Drop", "fork-test", 10, 7 days);

        vm.prank(BAW);
        fair.claim(dropId);

        require(fair.hasClaimed(dropId, BAW), "BAW claim recorded");
        require(fair.totalAgents() == 1, "one agent");
        require(fair.totalClaims() == 1, "one claim");
    }
}
