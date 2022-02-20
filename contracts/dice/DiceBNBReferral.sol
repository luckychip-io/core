// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IBEP20.sol";
import "../interfaces/IDiceReferral.sol";
import "../libraries/SafeBEP20.sol";

contract DiceBNBReferral is IDiceReferral, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;
    using EnumerableSet for EnumerableSet.AddressSet;
   
    EnumerableSet.AddressSet private _operators;
    uint256 public accCommission;

    struct ReferrerInfo{
        uint256 accCommission;
        uint256 pendingCommission;
    }

    mapping(address => address) public referrers; // user address => referrer address
    mapping(address => uint256) public referralsCount; // referrer address => referrals count
    mapping(address => ReferrerInfo) public referrerInfo; // referrer address => Referrer Info

    event ReferrerRecorded(address indexed user, address indexed referrer);
    event CommissionRecorded(address indexed user, address indexed referrer, uint256 commission, uint256 accCommission, uint256 pendingCommission);
    event ClaimCommission(address indexed referrer, uint256 amount);

    // Fallback & receive payable function used to top up the bank roll.
    fallback() external payable {}
    receive() external payable {}

    function isOperator(address account) public view returns (bool) {
        return EnumerableSet.contains(_operators, account);
    }

    // modifier for operator
    modifier onlyOperator() {
        require(isOperator(msg.sender), "caller is not a operator");
        _;
    }

    function addOperator(address _addOperator) public onlyOwner returns (bool) {
        require(_addOperator != address(0), "Token: _addOperator is the zero address");
        return EnumerableSet.add(_operators, _addOperator);
    }

    function delOperator(address _delOperator) public onlyOwner returns (bool) {
        require(_delOperator != address(0), "Token: _delOperator is the zero address");
        return EnumerableSet.remove(_operators, _delOperator);
    }

    function recordReferrer(address _user, address _referrer) public override onlyOperator {
        if (_user != address(0)
            && _referrer != address(0)
            && _user != _referrer
            && referrers[_user] == address(0)
        ) {
            referrers[_user] = _referrer;
            referralsCount[_referrer] = referralsCount[_referrer].add(1);
            emit ReferrerRecorded(_user, _referrer);
        }
    }

    function recordCommission(address _user, address _referrer, uint256 _commission) public override onlyOperator {
        if (_referrer != address(0) && _commission > 0) {
            ReferrerInfo storage info = referrerInfo[_referrer];
            info.accCommission = info.accCommission.add(_commission);
            info.pendingCommission = info.pendingCommission.add(_commission);
            accCommission = accCommission.add(_commission);

            emit CommissionRecorded(_user, _referrer, _commission, info.accCommission, info.pendingCommission);
        }
    }

    // Get the referrer address that referred the user
    function getReferrer(address _user) public override view returns (address) {
        return referrers[_user];
    }

    function getReferralCommission(address _referrer) public override view returns(uint256, uint256, uint256){
        ReferrerInfo storage info = referrerInfo[_referrer];
        return (info.accCommission, info.pendingCommission, referralsCount[_referrer]);
    }

    function claimCommission() public override nonReentrant {
        address referrer = msg.sender;
        ReferrerInfo storage info = referrerInfo[referrer];
        if(info.pendingCommission > 0){
            uint256 tmpAmount = info.pendingCommission;
            info.pendingCommission = 0;
            _safeTransferBNB(referrer, tmpAmount);
            emit ClaimCommission(referrer, tmpAmount);
        }
    }

    // Owner can withdraw non-MATIC tokens.
    function withdrawToken(address tokenAddress) external onlyOwner {
        IBEP20(tokenAddress).safeTransfer(owner(), IBEP20(tokenAddress).balanceOf(address(this)));
    }

    function _safeTransferBNB(address to, uint256 value) internal {
        (bool success, ) = to.call{gas: 23000, value: value}("");
        require(success, 'BNB_TRANSFER_FAILED');
    }
}
