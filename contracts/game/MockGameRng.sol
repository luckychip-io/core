// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IBEP20.sol";
import "../libraries/SafeBEP20.sol";
import "../interfaces/IGame.sol";
import "../interfaces/IGameRng.sol";

contract MockGameRng is IGameRng, Ownable {
    using SafeBEP20 for IBEP20;

    IGame public game;

    /**
     * @notice Request randomness off-chain
     */
    function getRandomNumberOffChain(uint256 betId) external override returns (uint256) {
        require(msg.sender == address(game), "Only game");
        return betId;
    }

    /**
     * @notice Request randomness on-chain
     */
    function getRandomNumberOnChain(uint256 betId) external override returns (uint256) {
        require(msg.sender == address(game), "Only game");
        return betId;
    }

    /**
     * @notice Callback function
     */
    function fulfillRandomnessOffChain(uint256 requestId, uint256 randomness) external onlyOwner {
        game.settleBet(requestId, randomness);
    }

    /**
     * @notice Set the address for the LuckyGame
     * @param _gameAddr: address of the LuckyGame
     */
    function setGame(address _gameAddr) external onlyOwner {
        game = IGame(_gameAddr);
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