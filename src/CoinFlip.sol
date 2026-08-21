// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title CoinFlipBet
/// @notice A simple two-player coin flip betting contract for learning purposes.
/// @dev WARNING: The randomness used here (block data) is NOT secure.
///      A miner/validator can see the flip outcome before including the
///      transaction and could manipulate it. Fine for friends betting small
///      amounts for fun / learning. Do NOT use this pattern for anything
///      involving real money at scale — use Chainlink VRF or similar for
///      production-grade randomness.
contract CoinFlip {
    enum Choice {
        None,
        Heads,
        Tails
    }
    enum Status {
        Open,
        Resolved,
        Cancelled
    }

    struct Bet {
        address payable creator;
        address payable challenger;
        uint256 amount;
        Choice creatorChoice;
        Status status;
        address winner;
    }

    uint256 public betCounter;
    mapping(uint256 => Bet) public bets;

    event BetCreated(uint256 indexed betId, address indexed creator, uint256 amount, Choice choice);
    event BetJoined(uint256 indexed betId, address indexed challenger);
    event BetResolved(uint256 indexed betId, address indexed winner, bool wasHeads);
    event BetCancelled(uint256 indexed betId);

    /// @notice Create a new bet by choosing heads or tails and sending ETH.
    function createBet(Choice _choice) external payable returns (uint256) {
        require(msg.value > 0, "Must bet more than 0");
        require(_choice == Choice.Heads || _choice == Choice.Tails, "Invalid choice");

        uint256 betId = betCounter++;
        bets[betId] = Bet({
            creator: payable(msg.sender),
            challenger: payable(address(0)),
            amount: msg.value,
            creatorChoice: _choice,
            status: Status.Open,
            winner: address(0)
        });

        emit BetCreated(betId, msg.sender, msg.value, _choice);
        return betId;
    }

    /// @notice Join an open bet by matching the amount. This triggers the flip.
    function joinBet(uint256 _betId) external payable {
        Bet storage bet = bets[_betId];

        require(bet.status == Status.Open, "Bet is not open");
        require(msg.sender != bet.creator, "Cannot bet against yourself");
        require(msg.value == bet.amount, "Must match the bet amount");

        bet.challenger = payable(msg.sender);
        emit BetJoined(_betId, msg.sender);

        _resolveBet(_betId);
    }

    /// @notice Cancel a bet you created, if nobody has joined yet, and reclaim your ETH.
    function cancelBet(uint256 _betId) external {
        Bet storage bet = bets[_betId];

        require(bet.status == Status.Open, "Bet is not open");
        require(msg.sender == bet.creator, "Only creator can cancel");

        bet.status = Status.Cancelled;
        emit BetCancelled(_betId);

        (bool success,) = bet.creator.call{value: bet.amount}("");
        require(success, "Refund transfer failed");
    }

    /// @dev Internal: performs the "flip" and pays out the winner.
    /// Pseudo-randomness only — see contract-level warning above.
    function _resolveBet(uint256 _betId) internal {
        Bet storage bet = bets[_betId];

        bool isHeads = uint256(
                    keccak256(
                        abi.encodePacked(
                            blockhash(block.number - 1), block.timestamp, bet.creator, bet.challenger, _betId
                        )
                    )
                ) % 2 == 0;

        Choice result = isHeads ? Choice.Heads : Choice.Tails;
        address payable winner = (result == bet.creatorChoice) ? bet.creator : bet.challenger;

        bet.status = Status.Resolved;
        bet.winner = winner;

        emit BetResolved(_betId, winner, isHeads);

        (bool success,) = winner.call{value: bet.amount * 2}("");
        require(success, "Payout transfer failed");
    }

    /// @notice Helper to read a bet's full details.
    function getBet(uint256 _betId)
        external
        view
        returns (
            address creator,
            address challenger,
            uint256 amount,
            Choice creatorChoice,
            Status status,
            address winner
        )
    {
        Bet storage bet = bets[_betId];
        return (bet.creator, bet.challenger, bet.amount, bet.creatorChoice, bet.status, bet.winner);
    }
}
