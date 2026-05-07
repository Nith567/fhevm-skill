// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FHE, euint64, ebool, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

contract EncryptedERC20 is SepoliaConfig {
    string public name;
    string public symbol;
    uint8  public constant decimals = 6;
    address public immutable owner;

    mapping(address => euint64) private _balances;
    mapping(address => mapping(address => euint64)) private _allowances;

    event Transfer(address indexed from, address indexed to);
    event Approval(address indexed owner, address indexed spender);
    event Mint(address indexed to);
    event Burn(address indexed from);

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    function mint(address to, uint64 amount) external onlyOwner {
        euint64 enc = FHE.asEuint64(amount);
        _balances[to] = FHE.add(_balances[to], enc);
        FHE.allowThis(_balances[to]);
        FHE.allow(_balances[to], to);
        emit Mint(to);
    }

    function balanceOf(address account) external view returns (euint64) {
        return _balances[account];
    }

    function allowance(address holder, address spender)
        external view returns (euint64)
    {
        return _allowances[holder][spender];
    }

    function approve(
        address spender,
        externalEuint64 encAmount,
        bytes calldata proof
    ) external {
        euint64 amount = FHE.fromExternal(encAmount, proof);
        _allowances[msg.sender][spender] = amount;
        FHE.allowThis(_allowances[msg.sender][spender]);
        FHE.allow(_allowances[msg.sender][spender], msg.sender);
        FHE.allow(_allowances[msg.sender][spender], spender);
        emit Approval(msg.sender, spender);
    }

    function transfer(
        address to,
        externalEuint64 encAmount,
        bytes calldata proof
    ) external {
        euint64 amount = FHE.fromExternal(encAmount, proof);
        _transfer(msg.sender, to, amount);
    }

    function transferFrom(
        address from,
        address to,
        externalEuint64 encAmount,
        bytes calldata proof
    ) external {
        euint64 amount = FHE.fromExternal(encAmount, proof);
        euint64 currentAllowance = _allowances[from][msg.sender];

        ebool sufficient = FHE.ge(currentAllowance, amount);
        euint64 actual = FHE.select(sufficient, amount, FHE.asEuint64(0));

        _allowances[from][msg.sender] = FHE.sub(currentAllowance, actual);
        FHE.allowThis(_allowances[from][msg.sender]);
        FHE.allow(_allowances[from][msg.sender], from);
        FHE.allow(_allowances[from][msg.sender], msg.sender);

        _transfer(from, to, actual);
    }

    function _transfer(address from, address to, euint64 amount) internal {
        euint64 fromBal = _balances[from];
        ebool   canPay  = FHE.ge(fromBal, amount);
        euint64 actual  = FHE.select(canPay, amount, FHE.asEuint64(0));

        _balances[from] = FHE.sub(fromBal, actual);
        _balances[to]   = FHE.add(_balances[to], actual);

        FHE.allowThis(_balances[from]);
        FHE.allow(_balances[from], from);
        FHE.allowThis(_balances[to]);
        FHE.allow(_balances[to], to);

        emit Transfer(from, to);
    }
}
