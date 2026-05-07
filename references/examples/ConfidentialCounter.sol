// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FHE, euint32, externalEuint32} from "@fhevm/solidity/lib/FHE.sol";
import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

contract ConfidentialCounter is SepoliaConfig {
    euint32 private _count;

    function set(externalEuint32 enc, bytes calldata proof) external {
        _count = FHE.fromExternal(enc, proof);
        FHE.allowThis(_count);
        FHE.allow(_count, msg.sender);
    }

    function increment(externalEuint32 enc, bytes calldata proof) external {
        euint32 delta = FHE.fromExternal(enc, proof);
        _count = FHE.add(_count, delta);
        FHE.allowThis(_count);
        FHE.allow(_count, msg.sender);
    }

    function decrement(externalEuint32 enc, bytes calldata proof) external {
        euint32 delta = FHE.fromExternal(enc, proof);
        _count = FHE.sub(_count, delta);
        FHE.allowThis(_count);
        FHE.allow(_count, msg.sender);
    }

    function getCount() external view returns (euint32) {
        return _count;
    }
}
