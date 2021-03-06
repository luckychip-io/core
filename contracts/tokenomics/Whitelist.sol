// SPDX-License-Identifier: MIT
  
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IBEP20.sol";
import "../libraries/SafeBEP20.sol";

interface ISeasonDice {
    function getUserBetCount(address user) external view returns (uint256);
}

contract Whitelist is Ownable, ReentrancyGuard{
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    uint256 public constant PRICE = 125000;
    uint256 public constant MIN_AMOUNT = 1e17;
    uint256 public constant MAX_AMOUNT = 1e18;

    address[] public accounts;
    mapping(address => bool) public inWhiteist;
    mapping(address => uint256) private _balances;

    ISeasonDice bnbDice;
    ISeasonDice usdtDice;

    event JoinWhitelist(address indexed user, uint256 amount);

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

    constructor(address _bnbDiceAddr, address _usdtDiceAddr) public {
        bnbDice = ISeasonDice(_bnbDiceAddr);
        usdtDice = ISeasonDice(_usdtDiceAddr);
    }

    function canJoin(address account) public view returns (bool) {
        if(address(bnbDice) != address(0) && bnbDice.getUserBetCount(account) > 0){
            return true;
        }else if(address(usdtDice) != address(0) && usdtDice.getUserBetCount(account) > 0){
            return true;
        }else{
            return false;
        }
    }

    function joinWhitelist() external payable nonReentrant notContract{
        address account = msg.sender;
        require(canJoin(account), "Play dice more than once");
        uint256 amount = msg.value;
        require(amount >= MIN_AMOUNT && amount <= MAX_AMOUNT, "within 0.1 and 1 BNB");

        uint256 balance = _balances[account];
        require(balance.add(amount) <= MAX_AMOUNT, "Max 1 BNB for each account");
        
        if(!inWhiteist[account]){
            inWhiteist[account] = true;
            accounts.push(account);
        }
        _balances[account] = _balances[account].add(amount);

        emit JoinWhitelist(account, amount);
    }

    function setDice(address _bnbDiceAddr, address _usdtDiceAddr) external onlyOwner{
        require(_bnbDiceAddr != address(0) && _usdtDiceAddr != address(0), "Zero");
        bnbDice = ISeasonDice(_bnbDiceAddr);
        usdtDice = ISeasonDice(_usdtDiceAddr);
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function pendingLC(address account) public view returns (uint256) {
        return _balances[account].mul(PRICE);
    }

    function accountLength() public view returns (uint256) {
        return accounts.length;
    }

    function _safeTransferBNB(address to, uint256 value) internal {
        (bool success, ) = to.call{gas: 23000, value: value}("");
        require(success, 'BNB_TRANSFER_FAILED');
    }

    // Owner can withdraw BNB funds
    function withdrawFunds(uint withdrawAmount) external onlyOwner {
        require(withdrawAmount <= address(this).balance, "Withdrawal exceeds limit");
        _safeTransferBNB(owner(), withdrawAmount);
    }

    function withdrawTokens(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        IBEP20(_tokenAddress).safeTransfer(address(msg.sender), _tokenAmount);
    }
}
