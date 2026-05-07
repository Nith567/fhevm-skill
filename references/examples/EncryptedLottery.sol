// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FHE, euint8, eaddress, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

contract EncryptedLottery is SepoliaConfig {
    uint256 public immutable ticketPrice;
    uint256 public immutable maxTickets;
    uint256 public ticketsSold;
    uint256 public roundEndTime;

    eaddress private _winnerEnc;
    address  public  winner;
    bool     public  drawn;
    uint256  private _pendingId;

    mapping(uint256 => address) public ticketHolders;

    event TicketBought(address indexed buyer, uint256 ticketId);
    event WinnerDrawn(address winner, uint256 prize);

    constructor(uint256 _ticketPrice, uint256 _maxTickets, uint256 _duration) {
        ticketPrice = _ticketPrice;
        maxTickets  = _maxTickets;
        roundEndTime = block.timestamp + _duration;
    }

    function buyTicket() external payable {
        require(msg.value == ticketPrice, "wrong price");
        require(ticketsSold < maxTickets, "sold out");
        require(block.timestamp < roundEndTime, "round closed");

        ticketHolders[ticketsSold] = msg.sender;
        ticketsSold++;
        emit TicketBought(msg.sender, ticketsSold - 1);
    }

    function drawWinner() external {
        require(!drawn, "already drawn");
        require(block.timestamp >= roundEndTime || ticketsSold == maxTickets, "too early");
        require(_pendingId == 0, "request pending");
        require(ticketsSold > 0, "no tickets");

        euint8 winningIdx;
        if (ticketsSold <= 256) {
            winningIdx = FHE.randEuint8(uint8(ticketsSold));
        } else {
            winningIdx = FHE.randEuint8();
        }

        eaddress winnerHandle = FHE.asEaddress(ticketHolders[0]);
        for (uint256 i = 1; i < ticketsSold && i < 256; i++) {
            ebool isWinner = FHE.eq(winningIdx, FHE.asEuint8(uint8(i)));
            winnerHandle = FHE.select(
                isWinner,
                FHE.asEaddress(ticketHolders[i]),
                winnerHandle
            );
        }

        _winnerEnc = winnerHandle;
        FHE.allowThis(_winnerEnc);

        bytes32[] memory cts = new bytes32[](1);
        cts[0] = FHE.toBytes32(_winnerEnc);
        _pendingId = FHE.requestDecryption(cts, this.onWinnerDrawn.selector);
    }

    function onWinnerDrawn(
        uint256 requestId,
        address w,
        bytes[] memory signatures
    ) external {
        FHE.checkSignatures(requestId, signatures);
        require(requestId == _pendingId, "stale");
        require(!drawn, "already drawn");

        drawn = true;
        winner = w;
        _pendingId = 0;

        uint256 prize = address(this).balance;
        (bool ok, ) = w.call{value: prize}("");
        require(ok, "transfer failed");

        emit WinnerDrawn(w, prize);
    }
}
