// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FHE, euint64, eaddress, ebool, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

contract SealedBidAuction is SepoliaConfig {
    address public immutable beneficiary;
    address public immutable nftContract;
    uint256 public immutable tokenId;
    uint256 public immutable endTime;
    uint256 public immutable minBid;

    mapping(address => euint64) private _bids;
    mapping(address => uint256) public deposits;
    address[] public bidders;
    mapping(address => bool) private _hasBid;

    euint64  private _highestBid;
    eaddress private _highestBidder;

    bool    public revealed;
    uint64  public winningBidPlain;
    address public winnerPlain;
    uint256 private _pendingId;

    event BidPlaced(address indexed bidder);
    event AuctionRevealed(address winner, uint64 amount);
    event RefundClaimed(address indexed bidder, uint256 amount);

    constructor(
        address _nftContract,
        uint256 _tokenId,
        uint256 _duration,
        uint256 _minBid
    ) {
        beneficiary = msg.sender;
        nftContract = _nftContract;
        tokenId = _tokenId;
        endTime = block.timestamp + _duration;
        minBid = _minBid;

        _highestBid = FHE.asEuint64(0);
        _highestBidder = FHE.asEaddress(address(0));
        FHE.allowThis(_highestBid);
        FHE.allowThis(_highestBidder);
    }

    function placeBid(
        externalEuint64 encBid,
        bytes calldata proof
    ) external payable {
        require(block.timestamp < endTime, "auction over");
        require(msg.value >= minBid, "deposit < minBid");

        euint64 bid = FHE.fromExternal(encBid, proof);
        eaddress bidder = FHE.asEaddress(msg.sender);

        if (!_hasBid[msg.sender]) {
            bidders.push(msg.sender);
            _hasBid[msg.sender] = true;
        }
        _bids[msg.sender] = bid;
        deposits[msg.sender] += msg.value;

        FHE.allowThis(_bids[msg.sender]);
        FHE.allow(_bids[msg.sender], msg.sender);

        ebool higher = FHE.gt(bid, _highestBid);
        _highestBid = FHE.select(higher, bid, _highestBid);
        _highestBidder = FHE.select(higher, bidder, _highestBidder);

        FHE.allowThis(_highestBid);
        FHE.allowThis(_highestBidder);

        emit BidPlaced(msg.sender);
    }

    function requestReveal() external {
        require(block.timestamp >= endTime, "still bidding");
        require(!revealed, "already revealed");
        require(_pendingId == 0, "request pending");

        bytes32[] memory cts = new bytes32[](2);
        cts[0] = FHE.toBytes32(_highestBid);
        cts[1] = FHE.toBytes32(_highestBidder);
        _pendingId = FHE.requestDecryption(cts, this.onReveal.selector);
    }

    function onReveal(
        uint256 requestId,
        uint64 amount,
        address winner,
        bytes[] memory signatures
    ) external {
        FHE.checkSignatures(requestId, signatures);
        require(requestId == _pendingId, "stale");
        require(!revealed, "already revealed");

        revealed = true;
        winningBidPlain = amount;
        winnerPlain = winner;
        _pendingId = 0;

        emit AuctionRevealed(winner, amount);
    }

    function claimRefund() external {
        require(revealed, "not revealed");
        require(msg.sender != winnerPlain, "winner pays");
        uint256 amount = deposits[msg.sender];
        require(amount > 0, "nothing to refund");
        deposits[msg.sender] = 0;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "refund failed");
        emit RefundClaimed(msg.sender, amount);
    }

    function settleWinner() external {
        require(revealed, "not revealed");
        require(msg.sender == winnerPlain, "only winner");
        require(deposits[winnerPlain] >= winningBidPlain, "insufficient deposit");

        uint256 surplus = deposits[winnerPlain] - winningBidPlain;
        deposits[winnerPlain] = 0;

        (bool ok1, ) = beneficiary.call{value: winningBidPlain}("");
        require(ok1, "pay beneficiary failed");
        if (surplus > 0) {
            (bool ok2, ) = winnerPlain.call{value: surplus}("");
            require(ok2, "refund surplus failed");
        }
    }

    function myBid() external view returns (euint64) {
        return _bids[msg.sender];
    }
}
