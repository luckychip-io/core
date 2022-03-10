// SPDX-License-Identifier: MIT
  
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LuckyReward is Ownable, ReentrancyGuard{
    using SafeMath for uint256;

    struct RewardInfo {
        uint256 pendingAmount;
        uint256 firstPrizeAmount;
        uint256 secondPrizeAmount;
        uint256 thirdPrizeAmount;
        uint256 accAmount;
    }

    address[] firstPrizeAddrs;
    address[] secondPrizeAddrs;
    address[] thirdPrizeAddrs;
    uint256 firstPrizeAmount;
    uint256 secondPrizeAmount;
    uint256 thirdPrizeAmount;

    uint256 public accFirstPrizeAmount;
    uint256 public accSecondPrizeAmount;
    uint256 public accThirdPrizeAmount;

    mapping(address => RewardInfo) public rewardInfo;

    event InjectFirstPrize(address indexed src, uint256 blockNumber, uint256 amount, address[] dst, uint256 length);
    event InjectSecondPrize(address indexed src, uint256 blockNumber, uint256 amount, address[] dst, uint256 length);
    event InjectThirdPrize(address indexed src, uint256 blockNumber, uint256 amount, address[] dst, uint256 length);

    modifier notContract() {
        require((!_isContract(msg.sender)) && (msg.sender == tx.origin), "no contract");
        _;
    }

    // Judge address is contract or not
    function _isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    function injectFirstPrize(address[] calldata dst, uint256 amount) public nonReentrant notContract {
        uint256 length = dst.length;
        uint256 tmpAmount = amount.div(length);
        firstPrizeAddrs = dst;
        firstPrizeAmount = amount;
        for(uint256 i = 0; i < length; i ++){
            RewardInfo storage info = rewardInfo[dst[i]];
            info.pendingAmount = info.pendingAmount.add(tmpAmount);
            info.accAmount = info.accAmount.add(tmpAmount);
            info.firstPrizeAmount = info.firstPrizeAmount.add(tmpAmount);
        }
        accFirstPrizeAmount = accFirstPrizeAmount.add(amount);
        
        emit InjectFirstPrize(msg.sender, block.number, amount, dst, dst.length); 
    }

    function injectSecondPrize(address[] calldata dst, uint256 amount) public nonReentrant notContract {
        uint256 length = dst.length;
        uint256 tmpAmount = amount.div(length);
        secondPrizeAddrs = dst;
        secondPrizeAmount = amount;
        for(uint256 i = 0; i < length; i ++){
            RewardInfo storage info = rewardInfo[dst[i]];
            info.pendingAmount = info.pendingAmount.add(tmpAmount);
            info.accAmount = info.accAmount.add(tmpAmount);
            info.secondPrizeAmount = info.secondPrizeAmount.add(tmpAmount);
        }
        accSecondPrizeAmount = accSecondPrizeAmount.add(amount);
        
        emit InjectSecondPrize(msg.sender, block.number, amount, dst, dst.length);
    }

    function injectThirdPrize(address[] calldata dst, uint256 amount) public nonReentrant notContract {
        uint256 length = dst.length;
        uint256 tmpAmount = amount.div(length);
        thirdPrizeAddrs = dst;
        thirdPrizeAmount = amount;
        for(uint256 i = 0; i < length; i ++){
            RewardInfo storage info = rewardInfo[dst[i]];
            info.pendingAmount = info.pendingAmount.add(tmpAmount);
            info.accAmount = info.accAmount.add(tmpAmount);
            info.thirdPrizeAmount = info.thirdPrizeAmount.add(tmpAmount);
        }
        accThirdPrizeAmount = accThirdPrizeAmount.add(amount);
        
        emit InjectThirdPrize(msg.sender, block.number, amount, dst, dst.length); 
    }

    function getRewardInfo(address user) external view returns (uint256, uint256, uint256, uint256, uint256) {
        RewardInfo storage info = rewardInfo[user];
        return (info.pendingAmount, info.firstPrizeAmount, info.secondPrizeAmount, info.thirdPrizeAmount, info.accAmount);
    }

    function getFirstPrize() external view returns (address[] memory, uint256, uint256){
        return (firstPrizeAddrs, firstPrizeAddrs.length, firstPrizeAmount);
    }

    function getSecondPrize() external view returns (address[] memory, uint256, uint256){
        return (secondPrizeAddrs, secondPrizeAddrs.length, secondPrizeAmount);
    }

    function getThirdPrize() external view returns (address[] memory, uint256, uint256){
        return (thirdPrizeAddrs, thirdPrizeAddrs.length, thirdPrizeAmount);
    }

    function getAccPrize() external view returns (uint256, uint256, uint256){
        return (accFirstPrizeAmount, accSecondPrizeAmount, accThirdPrizeAmount);
    }
}
