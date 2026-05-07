// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC7984} from "@openzeppelin/confidential-contracts/token/ERC7984/ERC7984.sol";
import {ERC7984ERC20Wrapper}
    from "@openzeppelin/confidential-contracts/token/ERC7984/extensions/ERC7984ERC20Wrapper.sol";
import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ConfidentialUSD is ERC7984, SepoliaConfig {
    address public immutable minter;

    constructor()
        ERC7984("Confidential USD", "cUSD", "https://example.com/cusd.json")
    {
        minter = msg.sender;
    }

    function mint(address to, uint64 amount) external {
        require(msg.sender == minter, "only minter");
        _mint(to, amount);
    }
}

contract ConfidentialUSDC is ERC7984ERC20Wrapper, SepoliaConfig {
    constructor(IERC20 underlying)
        ERC7984ERC20Wrapper(underlying)
        ERC7984("Confidential USDC", "cUSDC", "")
    {}
}
