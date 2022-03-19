// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../libraries/SafeBEP20.sol";
import "../interfaces/IBEP20.sol";

contract LCBatchTransfer is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    IBEP20 public lcToken; // Address of token contract

    constructor(address _lcTokenAddr) public{
        lcToken = IBEP20(_lcTokenAddr);
    }

    event WithdrawToken(address indexed owner, uint256 stakeAmount);

    // To withdraw tokens from contract, to deposit directly transfer to the contract
    function withdrawToken(uint256 value) public onlyOwner{
        // Check if contract is having required balance 
        require(lcToken.balanceOf(address(this)) >= value, "Not enough balance in the contract");
        lcToken.safeTransfer(msg.sender, value);

        emit WithdrawToken(msg.sender, value);
    }

    // To transfer tokens from Contract to the provided list of token holders with respective amount
    function batchTransfer(address[] calldata tokenHolders, uint256[] calldata amounts) external onlyOwner{
        require(tokenHolders.length == amounts.length, "Invalid input parameters");

        for(uint256 indx = 0; indx < tokenHolders.length; indx++) {
            lcToken.safeTransferFrom(msg.sender, tokenHolders[indx], amounts[indx]);
        }
    }
}
