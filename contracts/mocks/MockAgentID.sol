// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Test double for the SPACE ID Agent ID registry.
/// @dev Local + testnet testing ONLY. On BNB Chain mainnet, AgentFair is
///      deployed against the real registry at
///      0x60b9262456de011f7d15a54cdd8c48baaa8b022f. This mock only implements
///      the balanceOf surface AgentFair relies on, plus a test mint.
contract MockAgentID {
    mapping(address => uint256) private _balances;

    function mint(address to) external {
        _balances[to] = 1;
    }

    function balanceOf(address owner) external view returns (uint256) {
        return _balances[owner];
    }
}
