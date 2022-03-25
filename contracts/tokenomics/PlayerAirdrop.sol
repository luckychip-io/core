// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../libraries/SafeBEP20.sol";
import "../interfaces/IBEP20.sol";
import "../libraries/SafeBEP20.sol";
import "./AuthValidator.sol";

interface ILuckyDice {
    function getUserPrivateBetLength(address user) external view returns (uint256);
}

/**
 * @title LuckyChip Airdrop For Player
 */
contract PlayerAirdrop is Pausable, ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    IBEP20 public immutable lcToken;
    uint256 public immutable MAXIMUM_AMOUNT_TO_CLAIM;

    uint256 public singleAmount;
    uint256 public endTimestamp;

    uint256 public constant TOTAL_PERCENT = 10000;
    uint256 public flipPercent = 3000;
    uint256 public dicePercent = 7000;

    ILuckyDice public bnbFlip;
    ILuckyDice public bnbDice;
    AuthValidator public authValidator;

    mapping(address => bool) public hasClaimedFlip;
    mapping(address => bool) public hasClaimedDice;
    mapping(address => uint256) public claimedAmount;

    event AirdropRewardsClaim(address indexed user, uint256 amount);
    event NewEndTimestamp(uint256 endTimestamp);
    event TokensWithdrawn(uint256 amount);

    /**
     * @notice Constructor
     * @param _endTimestamp end timestamp for claiming
     * @param _maximumAmountToClaim maximum amount to claim per a user
     * @param _lcToken address of the lc token
     */
    constructor(
        uint256 _endTimestamp,
        uint256 _maximumAmountToClaim,
        uint256 _singleAmount,
        address _lcToken,
        address _bnbFlipAddr,
        address _bnbDiceAddr, 
        address _authValidatorAddr
    ) public {
        endTimestamp = _endTimestamp;
        MAXIMUM_AMOUNT_TO_CLAIM = _maximumAmountToClaim;
        singleAmount = _singleAmount;

        lcToken = IBEP20(_lcToken);

        bnbFlip = ILuckyDice(_bnbFlipAddr);
        bnbDice = ILuckyDice(_bnbDiceAddr);
        authValidator = AuthValidator(_authValidatorAddr);
    }

    /**
     * @notice Claim tokens for airdrop
     */
    function claim(bytes memory signature) external whenNotPaused nonReentrant {
        require(block.timestamp <= endTimestamp, "Airdrop: Too late to claim");

        // Verify the user has claimed
        require(!hasClaimedFlip[msg.sender] || !hasClaimedDice[msg.sender], "Airdrop: Already claimed");

        _checkValidity(msg.sender, singleAmount, signature);

        // Set as claimed
        uint256 totalAmount = 0;
        uint256 amount = singleAmount;
        if(address(bnbFlip) != address(0) && bnbFlip.getUserPrivateBetLength(msg.sender) > 0 && !hasClaimedFlip[msg.sender]){
            totalAmount += amount * flipPercent / TOTAL_PERCENT;
            hasClaimedFlip[msg.sender] = true;
        }
        if(address(bnbDice) != address(0) && bnbDice.getUserPrivateBetLength(msg.sender) > 0 && !hasClaimedDice[msg.sender]){
            totalAmount += amount * dicePercent / TOTAL_PERCENT;
            hasClaimedDice[msg.sender] = true;
        }

        if(totalAmount > 0){
            // Transfer tokens
            claimedAmount[msg.sender] = claimedAmount[msg.sender] + totalAmount;
            lcToken.safeTransfer(msg.sender, totalAmount);
            emit AirdropRewardsClaim(msg.sender, totalAmount);
        }
    }

    function _checkValidity(address user, uint256 amount, bytes memory signature) internal view{
        bytes32 hashedData = keccak256(abi.encodePacked(user, amount));
        require(authValidator.isAuthValid(signature, hashedData), "INVALID_AUTH");
    }

    /**
     * @notice Check whether it is possible to claim (it doesn't check orders)
     * @param user address of the user
     */
    function pendingAirdrop(
        address user
    ) public view returns (uint256) {
        if (block.timestamp <= endTimestamp) {
            uint256 totalAmount = 0;
            uint256 amount = singleAmount;
            if(address(bnbFlip) != address(0) && bnbFlip.getUserPrivateBetLength(user) > 0 && !hasClaimedFlip[user]){
                totalAmount += amount * flipPercent / TOTAL_PERCENT;
            }
            if(address(bnbDice) != address(0) && bnbDice.getUserPrivateBetLength(user) > 0 && !hasClaimedDice[user]){
                totalAmount += amount * dicePercent / TOTAL_PERCENT;
            }
            return totalAmount;
        } else {
            return 0;
        }
    }

    function setSingleAmount(uint256 _singleAmount) external onlyOwner{
        require(_singleAmount <= MAXIMUM_AMOUNT_TO_CLAIM, "Airdrop: singleAmount too high");
        singleAmount = _singleAmount;
    }

    function setAuthValidator(address _authValidatorAddr) external onlyOwner{
        require(_authValidatorAddr != address(0), "Zero");
        authValidator = AuthValidator(_authValidatorAddr);
    }

    function setDice(address _bnbFlipAddr, address _bnbDiceAddr) external onlyOwner{
        require(_bnbFlipAddr != address(0) && _bnbDiceAddr != address(0), "Zero");
        bnbFlip = ILuckyDice(_bnbFlipAddr);
        bnbDice = ILuckyDice(_bnbDiceAddr);
    }

    function setPercent(uint256 _flipPercent, uint256 _dicePercent) external onlyOwner{
        require(_flipPercent + _dicePercent == TOTAL_PERCENT, "Sum to TOTAL_PERCENT");
        flipPercent = _flipPercent;
        dicePercent = _dicePercent;
    }

    function isDicePlayed(address user) public view returns (bool flipPlayed, bool dicePlayed) {
        if(address(bnbFlip) != address(0) && bnbFlip.getUserPrivateBetLength(user) > 0){
            flipPlayed = true;
        }
        if(address(bnbDice) != address(0) && bnbDice.getUserPrivateBetLength(user) > 0){
            dicePlayed = true;
        }
    }

    /**
     * @notice Unpause airdrop
     */
    function unpauseAirdrop() external onlyOwner whenPaused {
        _unpause();
    }

    /**
     * @notice Update end timestamp
     * @param newEndTimestamp new endtimestamp
     * @dev Must be within 30 days
     */
    function updateEndTimestamp(uint256 newEndTimestamp) external onlyOwner {
        require(block.timestamp + 30 days > newEndTimestamp, "Owner: New timestamp too far");
        endTimestamp = newEndTimestamp;

        emit NewEndTimestamp(newEndTimestamp);
    }

    /**
     * @notice Transfer tokens back to owner
     */
    function withdrawTokenRewards() external onlyOwner {
        require(block.timestamp > (endTimestamp + 1 days), "Owner: Too early to remove rewards");
        uint256 balanceToWithdraw = lcToken.balanceOf(address(this));
        lcToken.safeTransfer(msg.sender, balanceToWithdraw);

        emit TokensWithdrawn(balanceToWithdraw);
    }
}