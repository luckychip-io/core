// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IBEP20.sol";
import "../libraries/SafeBEP20.sol";
import "../interfaces/IFlipRng.sol";
import "../interfaces/IDice.sol";

contract FlipRng is IFlipRng, Ownable {
    using SafeBEP20 for IBEP20;

    IDice public flip;

    /**
     * @notice Request private randomness
     */
    function getPrivateRandomNumber(uint256 betId) external override returns (uint256) {
        require(msg.sender == address(flip), "Only flip");
        return betId;
    }

    /**
     * @notice Callback function
     */
    function fulfillPrivateRandomness(uint256 requestId, uint256 randomness) external onlyOwner {
        flip.settlePrivateBet(requestId, randomness);
    }

    /**
     * @notice Set the address for the LuckyFlip
     * @param _flipAddr: address of the LuckyFlip
     */
    function setFlip(address _flipAddr) external onlyOwner {
        flip = IDice(_flipAddr);
    }

    /**
     * @notice It allows the admin to withdraw tokens sent to the contract
     * @param _tokenAddress: the address of the token to withdraw
     * @param _tokenAmount: the number of token amount to withdraw
     * @dev Only callable by owner.
     */
    function withdrawTokens(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        IBEP20(_tokenAddress).safeTransfer(address(msg.sender), _tokenAmount);
    }

}