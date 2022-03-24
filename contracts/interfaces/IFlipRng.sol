// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IFlipRng {
    /**
     * Requests randomness from a user-provided seed
     */
    function getPrivateRandomNumber(uint256 betId) external returns (uint256);
}
