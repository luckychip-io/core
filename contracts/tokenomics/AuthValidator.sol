
// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "../libraries/SigUtil.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AuthValidator is Ownable {
    address public _signingAuthWallet;

    event SigningWallet(address indexed signingWallet);

    constructor(address initialSigningWallet) public {
        _updateSigningAuthWallet(initialSigningWallet);
    }

    function updateSigningAuthWallet(address newSigningWallet) external onlyOwner {
        _updateSigningAuthWallet(newSigningWallet);
    }

    function _updateSigningAuthWallet(address newSigningWallet) internal {
        require(newSigningWallet != address(0), "INVALID_SIGNING_WALLET");
        _signingAuthWallet = newSigningWallet;
        emit SigningWallet(newSigningWallet);
    }

    function isAuthValid(bytes memory signature, bytes32 hashedData) public view returns (bool) {
        address signer = SigUtil.recover(keccak256(SigUtil.prefixed(hashedData)), signature);
        return signer == _signingAuthWallet;
    }
}