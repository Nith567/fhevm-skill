// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FHE, euint8, euint16, euint32, ebool, externalEuint8, externalEuint16, externalEuint32}
    from "@fhevm/solidity/lib/FHE.sol";
import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

contract EncryptedIdentity is SepoliaConfig {
    struct Identity {
        euint8  age;
        euint16 countryCode;
        euint32 reputationScore;
        bool    registered;
        uint256 createdAt;
    }

    mapping(address => Identity) private _identities;
    mapping(address => mapping(address => uint256)) public verifierAccessUntil;

    event IdentityRegistered(address indexed user);
    event AccessGranted(address indexed user, address indexed verifier, uint256 until);
    event ProofRequested(address indexed user, address indexed verifier);

    function register(
        externalEuint8 encAge,
        externalEuint16 encCountry,
        externalEuint32 encReputation,
        bytes calldata proof
    ) external {
        require(!_identities[msg.sender].registered, "already registered");

        Identity storage id = _identities[msg.sender];
        id.age             = FHE.fromExternal(encAge, proof);
        id.countryCode     = FHE.fromExternal(encCountry, proof);
        id.reputationScore = FHE.fromExternal(encReputation, proof);
        id.registered = true;
        id.createdAt = block.timestamp;

        FHE.allowThis(id.age);
        FHE.allowThis(id.countryCode);
        FHE.allowThis(id.reputationScore);
        FHE.allow(id.age, msg.sender);
        FHE.allow(id.countryCode, msg.sender);
        FHE.allow(id.reputationScore, msg.sender);

        emit IdentityRegistered(msg.sender);
    }

    function grantAccess(address verifier, uint256 duration) external {
        require(_identities[msg.sender].registered, "not registered");
        uint256 until = block.timestamp + duration;
        verifierAccessUntil[msg.sender][verifier] = until;

        Identity storage id = _identities[msg.sender];
        FHE.allow(id.age, verifier);
        FHE.allow(id.countryCode, verifier);
        FHE.allow(id.reputationScore, verifier);

        emit AccessGranted(msg.sender, verifier, until);
    }

    function proveAgeAbove(address user, uint8 threshold)
        external returns (ebool)
    {
        require(verifierAccessUntil[user][msg.sender] >= block.timestamp, "no access");
        Identity storage id = _identities[user];
        require(id.registered, "not registered");

        ebool result = FHE.gt(id.age, FHE.asEuint8(threshold));
        FHE.allowThis(result);
        FHE.allow(result, msg.sender);

        emit ProofRequested(user, msg.sender);
        return result;
    }

    function proveReputationAbove(address user, uint32 threshold)
        external returns (ebool)
    {
        require(verifierAccessUntil[user][msg.sender] >= block.timestamp, "no access");
        Identity storage id = _identities[user];
        require(id.registered, "not registered");

        ebool result = FHE.ge(id.reputationScore, FHE.asEuint32(threshold));
        FHE.allowThis(result);
        FHE.allow(result, msg.sender);

        emit ProofRequested(user, msg.sender);
        return result;
    }

    function proveCountryEquals(address user, uint16 expectedCountry)
        external returns (ebool)
    {
        require(verifierAccessUntil[user][msg.sender] >= block.timestamp, "no access");
        Identity storage id = _identities[user];
        require(id.registered, "not registered");

        ebool result = FHE.eq(id.countryCode, FHE.asEuint16(expectedCountry));
        FHE.allowThis(result);
        FHE.allow(result, msg.sender);

        emit ProofRequested(user, msg.sender);
        return result;
    }

    function getMyIdentity()
        external view returns (euint8 age, euint16 country, euint32 reputation)
    {
        Identity storage id = _identities[msg.sender];
        require(id.registered, "not registered");
        return (id.age, id.countryCode, id.reputationScore);
    }
}
