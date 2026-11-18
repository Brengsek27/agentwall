// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice Test-only stub of the Agent ID ERC-721 contract.
/// @dev AgentWall only ever calls `balanceOf(address)`, so the stub only
///      needs to model balances. `mint` here is a test convenience and does
///      NOT exist on the real Agent ID contract (which is issued solely by
///      SPACE ID / Binance Wallet and is non-transferable).
contract MockAgentID {
    mapping(address => uint256) private _balances;

    function mint(address to) external {
        _balances[to] += 1;
    }

    function balanceOf(address owner) external view returns (uint256) {
        return _balances[owner];
    }
}
