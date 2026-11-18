// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentWall} from "../contracts/AgentWall.sol";
import {MockAgentID} from "./MockAgentID.sol";

contract AgentWallTest is Test {
    MockAgentID internal agentId;
    AgentWall internal wall;

    address internal alice = makeAddr("alice"); // Agent ID holder
    address internal bob = makeAddr("bob"); // Agent ID holder
    address internal carol = makeAddr("carol"); // NOT a holder

    function setUp() public {
        agentId = new MockAgentID();
        wall = new AgentWall(address(agentId));
        agentId.mint(alice);
        agentId.mint(bob);
        // carol deliberately gets no Agent ID.
        vm.warp(1_800_000_000); // a realistic, day-aligned-ish start time
    }

    // ---------------------------------------------------------------
    // The gate
    // ---------------------------------------------------------------

    function test_HolderCanCheckInAndPost() public {
        vm.prank(alice);
        wall.checkIn("alice.ai", "Hello from the agent side!");

        assertEq(wall.totalPosts(), 1);
        assertEq(wall.uniqueAgents(), 1);

        (address author, string memory name, string memory message, uint256 ts) = wall.getPost(0);
        assertEq(author, alice);
        assertEq(name, "alice.ai");
        assertEq(message, "Hello from the agent side!");
        assertEq(ts, block.timestamp);

        (uint256 total, uint256 streak, uint256 lastDay, bool exists) = wall.getAgentStats(alice);
        assertEq(total, 1);
        assertEq(streak, 1);
        assertEq(lastDay, block.timestamp / 1 days);
        assertTrue(exists);
    }

    function test_NonHolderIsRejected() public {
        assertFalse(wall.isAgentIDHolder(carol));
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(AgentWall.NotAgentIDHolder.selector, carol));
        wall.checkIn("carol.ai", "let me in");
        assertEq(wall.totalPosts(), 0);
        assertEq(wall.uniqueAgents(), 0);
    }

    function test_HolderFlagMatchesBalance() public view {
        assertTrue(wall.isAgentIDHolder(alice));
        assertTrue(wall.isAgentIDHolder(bob));
        assertFalse(wall.isAgentIDHolder(carol));
    }

    // ---------------------------------------------------------------
    // Length caps
    // ---------------------------------------------------------------

    function test_MessageLengthCapEnforced() public {
        string memory exactly140 = _repeat("a", 140);
        vm.prank(alice);
        wall.checkIn("alice.ai", exactly140); // at the cap: allowed
        assertEq(wall.totalPosts(), 1);

        string memory one141 = _repeat("a", 141);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AgentWall.MessageTooLong.selector, 141));
        wall.checkIn("alice.ai", one141);
    }

    function test_NameLengthCapEnforced() public {
        string memory name65 = _repeat("n", 65);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AgentWall.NameTooLong.selector, 65));
        wall.checkIn(name65, "hi");
    }

    function test_EmptyNameAndMessageRejected() public {
        vm.startPrank(alice);
        vm.expectRevert(AgentWall.EmptyName.selector);
        wall.checkIn("", "hi");
        vm.expectRevert(AgentWall.EmptyMessage.selector);
        wall.checkIn("alice.ai", "");
        vm.stopPrank();
    }

    // ---------------------------------------------------------------
    // Reading the wall
    // ---------------------------------------------------------------

    function test_GetWallReturnsAllPosts() public {
        vm.prank(alice);
        wall.checkIn("alice.ai", "first");
        vm.prank(bob);
        wall.checkIn("bob.ai", "second");
        vm.prank(alice);
        wall.checkIn("alice.ai", "third");

        AgentWall.Post[] memory page = wall.getWall(0, 50);
        assertEq(page.length, 3);
        assertEq(page[0].author, alice);
        assertEq(page[0].message, "first");
        assertEq(page[1].author, bob);
        assertEq(page[1].message, "second");
        assertEq(page[2].author, alice);
        assertEq(page[2].message, "third");
    }

    function test_GetWallPagination() public {
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(alice);
            wall.checkIn("alice.ai", "post");
        }
        AgentWall.Post[] memory firstTwo = wall.getWall(0, 2);
        assertEq(firstTwo.length, 2);
        AgentWall.Post[] memory lastOne = wall.getWall(2, 2);
        assertEq(lastOne.length, 1);
        AgentWall.Post[] memory beyond = wall.getWall(3, 2);
        assertEq(beyond.length, 0);

        vm.expectRevert(abi.encodeWithSelector(AgentWall.PageTooLarge.selector, 51));
        wall.getWall(0, 51);
    }

    // ---------------------------------------------------------------
    // Stats, streaks, unique agents
    // ---------------------------------------------------------------

    function test_UniqueAgentsCountsEachHolderOnce() public {
        vm.startPrank(alice);
        wall.checkIn("alice.ai", "one");
        wall.checkIn("alice.ai", "two");
        vm.stopPrank();
        assertEq(wall.uniqueAgents(), 1);

        vm.prank(bob);
        wall.checkIn("bob.ai", "me too");
        assertEq(wall.uniqueAgents(), 2);

        (uint256 total,,,) = wall.getAgentStats(alice);
        assertEq(total, 2);
    }

    function test_StreaksAcrossDays() public {
        vm.prank(alice);
        wall.checkIn("alice.ai", "day zero");
        (, uint256 streak,,) = wall.getAgentStats(alice);
        assertEq(streak, 1);

        // Same day again: total grows, streak does not.
        vm.prank(alice);
        wall.checkIn("alice.ai", "still day zero");
        (uint256 total, uint256 streak2,,) = wall.getAgentStats(alice);
        assertEq(total, 2);
        assertEq(streak2, 1);

        // Next day: streak extends.
        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        wall.checkIn("alice.ai", "day one");
        (, uint256 streak3,,) = wall.getAgentStats(alice);
        assertEq(streak3, 2);

        // Skip two days: streak resets to 1.
        vm.warp(block.timestamp + 3 days);
        vm.prank(alice);
        wall.checkIn("alice.ai", "day four");
        (, uint256 streak4,,) = wall.getAgentStats(alice);
        assertEq(streak4, 1);
    }

    // ---------------------------------------------------------------
    // Events & no-funds guarantee
    // ---------------------------------------------------------------

    function test_CheckInEmitsEvents() public {
        vm.expectEmit(true, true, false, true);
        emit AgentWall.FirstCheckIn(alice);
        vm.expectEmit(true, true, false, true);
        emit AgentWall.CheckedIn(alice, 0, "alice.ai", "gm", block.timestamp);
        vm.prank(alice);
        wall.checkIn("alice.ai", "gm");
    }

    function test_PlainBNBTransferRejected() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(wall).call{value: 0.1 ether}("");
        assertFalse(ok);
        assertEq(address(wall).balance, 0);
    }

    function test_ConstructorRejectsZeroAddress() public {
        vm.expectRevert(bytes("AgentWall: zero Agent ID address"));
        new AgentWall(address(0));
    }

    // ---------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------

    function _repeat(string memory s, uint256 times) internal pure returns (string memory) {
        bytes memory out = new bytes(bytes(s).length * times);
        for (uint256 i = 0; i < times; i++) {
            for (uint256 j = 0; j < bytes(s).length; j++) {
                out[i * bytes(s).length + j] = bytes(s)[j];
            }
        }
        return string(out);
    }
}
