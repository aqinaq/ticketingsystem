// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface ITicketToken {
    function mint(address to, uint256 amount) external;
}

contract EventCrowdfunding is ReentrancyGuard {
    struct EventCampaign {
        string title;
        uint256 goalWei;
        uint256 deadline;     // unix timestamp
        uint256 totalRaised;  // in wei
        address creator;
        bool finalized;
        bool goalReached;     // snapshot at finalize time
        bool fundsClaimed;    // prevent double-withdraw
    }

    ITicketToken public immutable ticketToken;
    uint256 public nextEventId;

    mapping(uint256 => EventCampaign) public eventsById;
    mapping(uint256 => mapping(address => uint256)) public contributions; // eventId -> user -> wei contributed

    event EventCreated(
        uint256 indexed eventId,
        address indexed creator,
        string title,
        uint256 goalWei,
        uint256 deadline
    );

    event Contributed(
        uint256 indexed eventId,
        address indexed contributor,
        uint256 amountWei,
        uint256 ticketsMinted
    );

    event Finalized(uint256 indexed eventId, uint256 totalRaised, bool goalReached);
    event FundsClaimed(uint256 indexed eventId, address indexed creator, uint256 amountWei);
    event Refunded(uint256 indexed eventId, address indexed contributor, uint256 amountWei);

    constructor(address ticketTokenAddress) {
        require(ticketTokenAddress != address(0), "Token address is zero");
        ticketToken = ITicketToken(ticketTokenAddress);
    }

    modifier eventExists(uint256 eventId) {
        require(eventId < nextEventId, "Event does not exist");
        _;
    }

    function createEvent(
        string calldata title,
        uint256 goalWei,
        uint256 durationSeconds
    ) external returns (uint256 eventId) {
        require(bytes(title).length > 0, "Title empty");
        require(goalWei > 0, "Goal must be > 0");
        require(durationSeconds > 0, "Duration must be > 0");

        eventId = nextEventId;
        nextEventId++;

        uint256 deadline = block.timestamp + durationSeconds;

        eventsById[eventId] = EventCampaign({
            title: title,
            goalWei: goalWei,
            deadline: deadline,
            totalRaised: 0,
            creator: msg.sender,
            finalized: false,
            goalReached: false,
            fundsClaimed: false
        });

        emit EventCreated(eventId, msg.sender, title, goalWei, deadline);
    }

    /*
     Contribute test ETH to active event
     mint ticket tokens proportional to contribution
     1 wei contributed -> 1 smallest unit of token minted
     */
    function contribute(uint256 eventId) external payable eventExists(eventId) {
        EventCampaign storage evn = eventsById[eventId];

        require(!evn.finalized, "Event finalized");
        require(block.timestamp < evn.deadline, "Event ended");
        require(msg.value > 0, "No ETH sent");

        contributions[eventId][msg.sender] += msg.value;
        evn.totalRaised += msg.value;

        uint256 ticketsToMint = msg.value;
        ticketToken.mint(msg.sender, ticketsToMint);

        emit Contributed(eventId, msg.sender, msg.value, ticketsToMint);
    }

    // Finalizes after deadline, locks the event and snapshots goalReached
     
    function finalize(uint256 eventId) external eventExists(eventId) {
        EventCampaign storage evn = eventsById[eventId];

        require(!evn.finalized, "Already finalized");
        require(block.timestamp >= evn.deadline, "Too early");

        evn.finalized = true;
        evn.goalReached = evn.totalRaised >= evn.goalWei;

        emit Finalized(eventId, evn.totalRaised, evn.goalReached);
    }

    // Creator withdraws raised ETH if goal was reached
    function claimFunds(uint256 eventId) external nonReentrant eventExists(eventId) {
        EventCampaign storage evn = eventsById[eventId];

        require(evn.finalized, "Not finalized");
        require(evn.goalReached, "Goal not reached");
        require(msg.sender == evn.creator, "Not creator");
        require(!evn.fundsClaimed, "Already claimed");

        evn.fundsClaimed = true;

        uint256 amount = evn.totalRaised;
        (bool ok, ) = payable(evn.creator).call{value: amount}("");
        require(ok, "ETH transfer failed");

        emit FundsClaimed(eventId, evn.creator, amount);
    }

    // Contributor refunds their contribution if goal was NOT reached

    function refund(uint256 eventId) external nonReentrant eventExists(eventId) {
        EventCampaign storage evn = eventsById[eventId];

        require(evn.finalized, "Not finalized");
        require(!evn.goalReached, "Goal reached");
        uint256 amount = contributions[eventId][msg.sender];
        require(amount > 0, "Nothing to refund");

        contributions[eventId][msg.sender] = 0;

        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        require(ok, "ETH transfer failed");

        emit Refunded(eventId, msg.sender, amount);
    }

    function getEvent(uint256 eventId)
        external
        view
        eventExists(eventId)
        returns (
            string memory title,
            uint256 goalWei,
            uint256 deadline,
            uint256 totalRaised,
            address creator,
            bool finalized,
            bool goalReached,
            bool fundsClaimed
        )
    {
        EventCampaign storage evn = eventsById[eventId];
        return (
            evn.title,
            evn.goalWei,
            evn.deadline,
            evn.totalRaised,
            evn.creator,
            evn.finalized,
            evn.goalReached,
            evn.fundsClaimed
        );
    }

    function getContribution(uint256 eventId, address account)
        external
        view
        eventExists(eventId)
        returns (uint256)
    {
        return contributions[eventId][account];
    }
}
