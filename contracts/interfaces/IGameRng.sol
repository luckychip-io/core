// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IGameRng {
    /**
     * Requests randomness off-chain
     */
    function getRandomNumberOffChain(uint256 betId) external returns (uint256);

    /**
     * Requests randomness on-chain
     */
    function getRandomNumberOnChain(uint256 betId) external returns (uint256);
}
