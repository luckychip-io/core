// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IDiceReferral {
    /**
     * @dev Record referrer.
     */
    function recordReferrer(address user, address referrer) external;

    /**
     * @dev Record referral commission.
     */
    function recordCommission(address user, address referrer, uint256 commission) external;

    /**
     * @dev Get the referrer address that referred the user.
     */
    function getReferrer(address user) external view returns (address);

    /**
     * @dev Get the commission referred by the user. (accCommission, pendingCommision, referralsCount)
     */
    function getReferralCommission(address user) external view returns (uint256, uint256, uint256);

    /**
     * @dev claim commission.
     */
    function claimCommission() external;

}
