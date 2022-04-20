// SPDX-License-Identifier: MIT
  
pragma solidity 0.6.12;

interface IGame {
    function tokenAddr() external view returns (address);
    function canWithdrawAmount(uint256 _amount) external view returns (uint256);
    function settleBet(uint256 requestId, uint256 randomNumber) external;
}
