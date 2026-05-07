// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FHE, euint32, externalEuint8, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

contract ConfidentialVoting is SepoliaConfig {
    struct Proposal {
        string  description;
        uint256 endTime;
        euint32 yesCount;
        euint32 noCount;
        bool    finalized;
        uint32  yesPlain;
        uint32  noPlain;
        uint256 pendingId;
    }

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    uint256 public proposalCount;

    event ProposalCreated(uint256 indexed id, string description, uint256 endTime);
    event VoteCast(uint256 indexed id, address indexed voter);
    event ProposalFinalized(uint256 indexed id, uint32 yes, uint32 no);

    function createProposal(string calldata description, uint256 votingDuration)
        external returns (uint256 id)
    {
        id = ++proposalCount;
        Proposal storage p = proposals[id];
        p.description = description;
        p.endTime = block.timestamp + votingDuration;
        p.yesCount = FHE.asEuint32(0);
        p.noCount = FHE.asEuint32(0);
        FHE.allowThis(p.yesCount);
        FHE.allowThis(p.noCount);
        emit ProposalCreated(id, description, p.endTime);
    }

    function vote(
        uint256 id,
        externalEuint8 encChoice,
        bytes calldata proof
    ) external {
        Proposal storage p = proposals[id];
        require(block.timestamp < p.endTime, "voting closed");
        require(!hasVoted[id][msg.sender], "already voted");
        hasVoted[id][msg.sender] = true;

        ebool isYes = FHE.eq(
            FHE.fromExternal(encChoice, proof),
            FHE.asEuint8(1)
        );

        euint32 oneIfYes = FHE.select(isYes, FHE.asEuint32(1), FHE.asEuint32(0));
        euint32 oneIfNo  = FHE.select(isYes, FHE.asEuint32(0), FHE.asEuint32(1));

        p.yesCount = FHE.add(p.yesCount, oneIfYes);
        p.noCount  = FHE.add(p.noCount,  oneIfNo);

        FHE.allowThis(p.yesCount);
        FHE.allowThis(p.noCount);

        emit VoteCast(id, msg.sender);
    }

    function requestFinalization(uint256 id) external {
        Proposal storage p = proposals[id];
        require(block.timestamp >= p.endTime, "still voting");
        require(!p.finalized, "already finalized");
        require(p.pendingId == 0, "request pending");

        bytes32[] memory cts = new bytes32[](2);
        cts[0] = FHE.toBytes32(p.yesCount);
        cts[1] = FHE.toBytes32(p.noCount);
        p.pendingId = FHE.requestDecryption(cts, this.onFinalize.selector);
    }

    function onFinalize(
        uint256 requestId,
        uint32 yes,
        uint32 no,
        bytes[] memory signatures
    ) external {
        FHE.checkSignatures(requestId, signatures);

        uint256 id;
        for (uint256 i = 1; i <= proposalCount; i++) {
            if (proposals[i].pendingId == requestId) { id = i; break; }
        }
        require(id != 0, "unknown request");

        Proposal storage p = proposals[id];
        require(!p.finalized, "double finalize");

        p.finalized = true;
        p.yesPlain = yes;
        p.noPlain = no;
        p.pendingId = 0;
        emit ProposalFinalized(id, yes, no);
    }

    function getEncryptedTally(uint256 id)
        external view returns (euint32 yesCount, euint32 noCount)
    {
        return (proposals[id].yesCount, proposals[id].noCount);
    }
}
