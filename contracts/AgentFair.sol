// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal interface for the SPACE ID Agent ID registry (BNB Chain).
/// @dev Per the official Agent ID Hackathon docs, an address holds an Agent ID
///      iff balanceOf(address) > 0 on 0x60b9262456de011f7d15a54cdd8c48baaa8b022f.
///      Agent ID is an ERC-721 that is one-per-user and non-transferable.
interface IAgentID {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title AgentFair — fair drops gated by Agent ID
/// @notice One Agent ID = one fair claim. Agent ID holders register, check in
///         daily to build reputation, create fixed-slot Drops, and claim one
///         slot per Drop. Because an Agent ID is one-per-user and
///         non-transferable, one claim per address is one claim per person —
///         sybil-resistant fair distribution without KYC or spreadsheets.
/// @dev Safety by design:
///      - Holds NO funds: no payable functions, no token transfers, no approvals.
///      - NO owner, NO admin, NO pause, NO upgrade path. Immutable after deploy.
///      - The only privileged action is a Drop creator cancelling their own Drop.
///      - Points are a non-transferable reputation score with no monetary value.
contract AgentFair {
    /// @notice The official SPACE ID Agent ID registry this deployment checks.
    IAgentID public immutable agentID;

    // ------------------------------------------------------------------
    // Agents
    // ------------------------------------------------------------------

    struct Agent {
        uint64 registeredAt;   // unix time of registration
        uint64 lastCheckInDay; // last check-in day index (unix days)
        uint32 streak;         // consecutive-day check-in streak
        uint32 checkIns;       // total check-ins
        uint256 points;        // reputation score (no monetary value)
        uint256 number;        // sequential Agent Number (1-based)
    }

    mapping(address => Agent) public agents;
    uint256 public totalAgents;
    uint256 public totalCheckIns;

    // ------------------------------------------------------------------
    // Drops
    // ------------------------------------------------------------------

    struct Drop {
        address creator;
        string title;
        string uri;        // link/description of what claimants receive off-chain
        uint64 startTime;
        uint64 endTime;
        uint32 slots;
        uint32 claimed;
        bool cancelled;
    }

    Drop[] public drops;
    mapping(uint256 => mapping(address => bool)) public hasClaimed;
    uint256 public totalClaims;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------

    event AgentRegistered(address indexed agent, uint256 number);
    event CheckedIn(address indexed agent, uint32 streak, uint256 points);
    event DropCreated(uint256 indexed dropId, address indexed creator, string title, uint32 slots, uint64 endTime);
    event DropClaimed(uint256 indexed dropId, address indexed agent);
    event DropCancelled(uint256 indexed dropId);

    // ------------------------------------------------------------------
    // Errors
    // ------------------------------------------------------------------

    error NoAgentID();
    error NotRegistered();
    error AlreadyRegistered();
    error AlreadyCheckedInToday();
    error InvalidSlots();
    error InvalidDuration();
    error EmptyTitle();
    error DropNotFound();
    error DropCancelled_();
    error DropNotStarted();
    error DropEnded();
    error DropFull();
    error AlreadyClaimed();
    error NotCreator();

    constructor(address agentIDRegistry) {
        require(agentIDRegistry != address(0), "AgentFair: zero registry");
        agentID = IAgentID(agentIDRegistry);
    }

    // ------------------------------------------------------------------
    // Guards
    // ------------------------------------------------------------------

    /// @dev Agent ID ownership is re-checked on EVERY action, not just once.
    modifier onlyAgentHolder() {
        if (agentID.balanceOf(msg.sender) == 0) revert NoAgentID();
        _;
    }

    modifier onlyRegistered() {
        if (agents[msg.sender].number == 0) revert NotRegistered();
        _;
    }

    // ------------------------------------------------------------------
    // Core actions
    // ------------------------------------------------------------------

    /// @notice Register as an AgentFair agent. Agent ID holders only, once.
    function register() external onlyAgentHolder {
        if (agents[msg.sender].number != 0) revert AlreadyRegistered();
        uint256 number = ++totalAgents;
        Agent storage a = agents[msg.sender];
        a.registeredAt = uint64(block.timestamp);
        a.number = number;
        a.points = 50; // welcome reputation
        emit AgentRegistered(msg.sender, number);
    }

    /// @notice Daily check-in (one per UTC day) to build streak + reputation.
    function checkIn() external onlyAgentHolder onlyRegistered {
        Agent storage a = agents[msg.sender];
        uint64 today = uint64(block.timestamp / 1 days);
        if (a.lastCheckInDay == today) revert AlreadyCheckedInToday();
        if (a.lastCheckInDay == today - 1) {
            a.streak += 1;
        } else {
            a.streak = 1;
        }
        a.lastCheckInDay = today;
        a.checkIns += 1;
        a.points += 10 + (a.streak > 1 ? 2 : 0); // small streak bonus
        totalCheckIns += 1;
        emit CheckedIn(msg.sender, a.streak, a.points);
    }

    /// @notice Create a fair Drop with a fixed number of claim slots.
    /// @param title Short name of the drop (e.g. "XYZ NFT allowlist").
    /// @param uri Link/description of what a claim entitles the holder to.
    /// @param slots Number of claim slots (1..100000).
    /// @param durationSecs How long claiming stays open, from now.
    function createDrop(string calldata title, string calldata uri, uint32 slots, uint64 durationSecs)
        external
        onlyAgentHolder
        onlyRegistered
        returns (uint256 dropId)
    {
        if (bytes(title).length == 0) revert EmptyTitle();
        if (slots == 0 || slots > 100_000) revert InvalidSlots();
        if (durationSecs < 1 hours || durationSecs > 180 days) revert InvalidDuration();
        dropId = drops.length;
        uint64 start = uint64(block.timestamp);
        uint64 end = start + durationSecs;
        drops.push(Drop({
            creator: msg.sender,
            title: title,
            uri: uri,
            startTime: start,
            endTime: end,
            slots: slots,
            claimed: 0,
            cancelled: false
        }));
        agents[msg.sender].points += 30;
        emit DropCreated(dropId, msg.sender, title, slots, end);
    }

    /// @notice Cancel your own Drop. Already-recorded claims stay on-chain.
    function cancelDrop(uint256 dropId) external {
        if (dropId >= drops.length) revert DropNotFound();
        Drop storage d = drops[dropId];
        if (d.creator != msg.sender) revert NotCreator();
        d.cancelled = true;
        emit DropCancelled(dropId);
    }

    /// @notice Claim one slot in a Drop. One Agent ID = one claim, enforced
    ///         by one-claim-per-address plus Agent ID's one-per-user,
    ///         non-transferable nature.
    function claim(uint256 dropId) external onlyAgentHolder onlyRegistered {
        if (dropId >= drops.length) revert DropNotFound();
        Drop storage d = drops[dropId];
        if (d.cancelled) revert DropCancelled_();
        if (block.timestamp < d.startTime) revert DropNotStarted();
        if (block.timestamp > d.endTime) revert DropEnded();
        if (d.claimed >= d.slots) revert DropFull();
        if (hasClaimed[dropId][msg.sender]) revert AlreadyClaimed();
        hasClaimed[dropId][msg.sender] = true;
        d.claimed += 1;
        totalClaims += 1;
        agents[msg.sender].points += 20;
        emit DropClaimed(dropId, msg.sender);
    }

    // ------------------------------------------------------------------
    // Views (frontend convenience)
    // ------------------------------------------------------------------

    function dropCount() external view returns (uint256) {
        return drops.length;
    }

    function getDrop(uint256 dropId)
        external
        view
        returns (
            address creator,
            string memory title,
            string memory uri,
            uint64 startTime,
            uint64 endTime,
            uint32 slots,
            uint32 claimed,
            bool cancelled
        )
    {
        if (dropId >= drops.length) revert DropNotFound();
        Drop storage d = drops[dropId];
        return (d.creator, d.title, d.uri, d.startTime, d.endTime, d.slots, d.claimed, d.cancelled);
    }

    function isAgentHolder(address account) external view returns (bool) {
        return agentID.balanceOf(account) > 0;
    }
}
