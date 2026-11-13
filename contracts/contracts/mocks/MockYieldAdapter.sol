// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IYieldAdapter} from "../interfaces/IYieldAdapter.sol";

/// @notice MOCK yield consists only of tokens explicitly funded for a position.
contract MockYieldAdapter is IYieldAdapter, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    address public immutable funder;
    address public vault;
    uint256 public totalPrincipal;
    uint256 public totalYield;
    mapping(uint256 => uint256) public principalOf;
    mapping(uint256 => uint256) public yieldOf;

    error Unauthorized();
    error InvalidPosition();
    error InvalidVault();
    error UnsupportedToken();

    event VaultBound(address indexed vault);
    event YieldFunded(uint256 indexed subscriptionId, uint256 amount);

    constructor(IERC20 token_, address funder_) {
        if (address(token_).code.length == 0 || funder_ == address(0)) revert InvalidVault();
        token = token_;
        funder = funder_;
    }

    modifier onlyVault() {
        if (msg.sender != vault) revert Unauthorized();
        _;
    }

    function bindVault(address vault_) external {
        if (msg.sender != funder) revert Unauthorized();
        if (vault != address(0) || vault_.code.length == 0) revert InvalidVault();
        vault = vault_;
        emit VaultBound(vault_);
    }

    function deposit(uint256 subscriptionId, uint256 principal) external onlyVault nonReentrant {
        if (principal == 0 || principalOf[subscriptionId] != 0) revert InvalidPosition();
        principalOf[subscriptionId] = principal;
        totalPrincipal += principal;
        _receive(msg.sender, principal);
    }

    function fundYield(uint256 subscriptionId, uint256 amount) external nonReentrant {
        if (msg.sender != funder) revert Unauthorized();
        if (principalOf[subscriptionId] == 0 || amount == 0) revert InvalidPosition();
        yieldOf[subscriptionId] += amount;
        totalYield += amount;
        _receive(msg.sender, amount);
        emit YieldFunded(subscriptionId, amount);
    }

    function estimateYield(uint256 subscriptionId) external view returns (uint256) {
        return yieldOf[subscriptionId];
    }

    function withdraw(uint256 subscriptionId, uint256 principal)
        external onlyVault nonReentrant returns (uint256 realizedYield)
    {
        if (principal == 0 || principal > principalOf[subscriptionId]) revert InvalidPosition();
        realizedYield = yieldOf[subscriptionId];
        principalOf[subscriptionId] -= principal;
        totalPrincipal -= principal;
        yieldOf[subscriptionId] = 0;
        totalYield -= realizedYield;
        token.safeTransfer(vault, principal + realizedYield);
    }

    function _receive(address from, uint256 amount) private {
        uint256 beforeBalance = token.balanceOf(address(this));
        token.safeTransferFrom(from, address(this), amount);
        if (token.balanceOf(address(this)) - beforeBalance != amount) revert UnsupportedToken();
    }
}
