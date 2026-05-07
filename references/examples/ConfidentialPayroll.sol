// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FHE, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

interface IERC7984 {
    function confidentialTransfer(
        address to,
        bytes32 encAmount,
        bytes calldata proof
    ) external returns (bytes32);
}

contract ConfidentialPayroll is SepoliaConfig {
    address public immutable admin;
    IERC7984 public immutable token;

    mapping(address => euint64) private _salaries;
    mapping(address => uint256) public lastPaid;
    address[] public employees;
    mapping(address => bool) public isEmployee;

    uint256 public payInterval;

    event EmployeeAdded(address indexed employee);
    event EmployeeRemoved(address indexed employee);
    event SalaryUpdated(address indexed employee);
    event PayrollRun(uint256 timestamp);

    constructor(IERC7984 _token, uint256 _payInterval) {
        admin = msg.sender;
        token = _token;
        payInterval = _payInterval;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "not admin");
        _;
    }

    function addEmployee(
        address employee,
        externalEuint64 encSalary,
        bytes calldata proof
    ) external onlyAdmin {
        require(!isEmployee[employee], "exists");
        euint64 sal = FHE.fromExternal(encSalary, proof);
        _salaries[employee] = sal;
        FHE.allowThis(_salaries[employee]);
        FHE.allow(_salaries[employee], employee);
        FHE.allow(_salaries[employee], admin);

        employees.push(employee);
        isEmployee[employee] = true;
        emit EmployeeAdded(employee);
    }

    function updateSalary(
        address employee,
        externalEuint64 encSalary,
        bytes calldata proof
    ) external onlyAdmin {
        require(isEmployee[employee], "no such employee");
        _salaries[employee] = FHE.fromExternal(encSalary, proof);
        FHE.allowThis(_salaries[employee]);
        FHE.allow(_salaries[employee], employee);
        FHE.allow(_salaries[employee], admin);
        emit SalaryUpdated(employee);
    }

    function removeEmployee(address employee) external onlyAdmin {
        require(isEmployee[employee], "no such employee");
        isEmployee[employee] = false;
        delete _salaries[employee];
        emit EmployeeRemoved(employee);
    }

    function runPayroll() external onlyAdmin {
        for (uint256 i = 0; i < employees.length; i++) {
            address e = employees[i];
            if (!isEmployee[e]) continue;
            if (block.timestamp < lastPaid[e] + payInterval) continue;

            FHE.allowTransient(_salaries[e], address(token));
            token.confidentialTransfer(
                e,
                FHE.toBytes32(_salaries[e]),
                ""
            );

            lastPaid[e] = block.timestamp;
        }
        emit PayrollRun(block.timestamp);
    }

    function mySalary() external view returns (euint64) {
        require(isEmployee[msg.sender], "not employee");
        return _salaries[msg.sender];
    }

    function employeeCount() external view returns (uint256) {
        return employees.length;
    }
}
