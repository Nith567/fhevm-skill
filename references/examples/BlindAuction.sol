// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FHE, euint64, eaddress, ebool, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

contract BlindAuction is SepoliaConfig {
    address public immutable beneficiary;
    uint256 public immutable endTime;

    euint64  private _highestBid;
    eaddress private _highestBidder;

    bool    public revealed;
    uint64  public winningBid;
    address public winner;
    uint256 private _pendingBidId;
    uint256 private _pendingAddrId;

    event NewBid(address indexed bidder);
    event Revealed(address winner, uint64 amount);

    constructor(uint256 biddingSeconds) {
        beneficiary = msg.sender;
        endTime = block.timestamp + biddingSeconds;
        _highestBid = FHE.asEuint64(0);
        _highestBidder = FHE.asEaddress(address(0));
        FHE.allowThis(_highestBid);
        FHE.allowThis(_highestBidder);
    }

    function bid(externalEuint64 encBid, bytes calldata proof) external {
        require(block.timestamp < endTime, "auction over");

        euint64  amt    = FHE.fromExternal(encBid, proof);
        eaddress sender = FHE.asEaddress(msg.sender);

        ebool higher = FHE.gt(amt, _highestBid);
        _highestBid    = FHE.select(higher, amt,    _highestBid);
        _highestBidder = FHE.select(higher, sender, _highestBidder);

        FHE.allowThis(_highestBid);
        FHE.allowThis(_highestBidder);

        emit NewBid(msg.sender);
    }

    function requestReveal() external {
        require(block.timestamp >= endTime, "still bidding");
        require(!revealed, "already revealed");

        bytes32[] memory cts = new bytes32[](2);
        cts[0] = FHE.toBytes32(_highestBid);
        cts[1] = FHE.toBytes32(_highestBidder);
        uint256 id = FHE.requestDecryption(cts, this.onReveal.selector);
        _pendingBidId = id;
        _pendingAddrId = id;
    }

    function onReveal(
        uint256 requestId,
        uint64 amount,
        address bidder,
        bytes[] memory signatures
    ) external {
        FHE.checkSignatures(requestId, signatures);
        require(requestId == _pendingBidId, "stale");
        require(!revealed, "already revealed");

        revealed = true;
        winningBid = amount;
        winner = bidder;
        emit Revealed(bidder, amount);
    }

    function myBidHandle() external view returns (euint64, eaddress) {
        return (_highestBid, _highestBidder);
    }
}
