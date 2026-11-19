// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IYieldAdapter {
    function token() external view returns (IERC20);
    function vault() external view returns (address);
    function deposit(uint256 subscriptionId, uint256 principal) external;
    function withdraw(uint256 subscriptionId, uint256 principal) external returns (uint256 realizedYield);
    function estimateYield(uint256 subscriptionId) external view returns (uint256);
}
