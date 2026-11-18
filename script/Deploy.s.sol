// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {AgentWall} from "../contracts/AgentWall.sol";

/// @notice Deploys AgentWall against the official Agent ID contract.
/// @dev DO NOT RUN without Bree's explicit approval — deployment is a
///      separate, approved step (see SUBMISSION.md runbook).
///      Usage (after approval):
///        forge script script/Deploy.s.sol:Deploy \
///          --rpc-url bsc --broadcast --private-key $DEPLOYER_PRIVATE_KEY
///      The deployer needs only enough BNB for one contract creation
///      (~0.0001 BNB at typical BSC gas prices). The deployer keeps NO
///      privileges: AgentWall has no owner and no admin functions.
contract Deploy is Script {
    /// @dev Official Agent ID contract, BNB Chain mainnet (SPACE ID, "AI").
    address internal constant AGENT_ID_MAINNET = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;

    function run() external returns (AgentWall wall) {
        vm.startBroadcast();
        wall = new AgentWall(AGENT_ID_MAINNET);
        vm.stopBroadcast();
        return wall;
    }
}
