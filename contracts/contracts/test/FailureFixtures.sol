// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {MockUSDC} from "../mocks/MockUSDC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IYieldAdapter} from "../interfaces/IYieldAdapter.sol";

/// @dev Test-only contracts. Deployment scripts export and deploy only the named demo contracts.
contract FailingToken is MockUSDC {
    bool public failTransfers;
    constructor(address funder) MockUSDC(funder) {}
    function setFailTransfers(bool value) external { failTransfers = value; }
    function _update(address from, address to, uint256 amount) internal override {
        require(!failTransfers, "test transfer failure");
        super._update(from, to, amount);
    }
}

contract ShortAdapter is IYieldAdapter {
    IERC20 public immutable token;
    address public vault;
    constructor(IERC20 token_, address) { token = token_; }
    function bindVault(address vault_) external { vault = vault_; }
    function deposit(uint256, uint256 amount) external { token.transferFrom(msg.sender, address(this), amount); }
    function withdraw(uint256, uint256 amount) external returns (uint256) {
        token.transfer(msg.sender, amount - 1);
        return 0;
    }
    function estimateYield(uint256) external pure returns (uint256) { return 0; }
}

contract CallbackToken is MockUSDC {
    address public callbackTarget;
    bytes public callbackData;
    bool public callbackSucceeded;
    bytes public callbackResult;
    constructor(address funder) MockUSDC(funder) {}
    function setCallback(address target, bytes calldata data) external {
        callbackTarget = target;
        callbackData = data;
    }
    function _update(address from, address to, uint256 amount) internal override {
        super._update(from, to, amount);
        if (from != address(0) && callbackTarget != address(0)) {
            (callbackSucceeded, callbackResult) = callbackTarget.call(callbackData);
        }
    }
}

contract FeeToken is MockUSDC {
    constructor(address funder) MockUSDC(funder) {}
    function _update(address from, address to, uint256 amount) internal override {
        if (from != address(0) && to != address(0) && amount > 0) {
            super._update(from, address(0), 1);
            amount--;
        }
        super._update(from, to, amount);
    }
}
