// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../libraries/SafeBEP20.sol";
import "../interfaces/IBEP20.sol";
import "../libraries/SafeBEP20.sol";
import "./AuthValidator.sol";
import "../game/LuckyGameBNB.sol";

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
    uint256 public flipPercent = 2500;
    uint256 public dicePercent = 7500;

    LuckyGameBNB public bnbGame;
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
        address payable _bnbGameAddr, 
        address _authValidatorAddr
    ) public {
        endTimestamp = _endTimestamp;
        MAXIMUM_AMOUNT_TO_CLAIM = _maximumAmountToClaim;
        singleAmount = _singleAmount;

        lcToken = IBEP20(_lcToken);

        bnbGame = LuckyGameBNB(_bnbGameAddr);
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
        (bool flipPlayed, bool dicePlayed) = isDicePlayed(msg.sender);
        if(flipPlayed && !hasClaimedFlip[msg.sender]) {
            totalAmount += amount * flipPercent / TOTAL_PERCENT;
            hasClaimedFlip[msg.sender] = true;
        }
        if(dicePlayed && !hasClaimedDice[msg.sender]){
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
            (bool flipPlayed, bool dicePlayed) = isDicePlayed(user);
            if(flipPlayed && !hasClaimedFlip[user]) {
                totalAmount += amount * flipPercent / TOTAL_PERCENT;
            }
            if(dicePlayed && !hasClaimedDice[user]){
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

    function setGame(address payable _bnbGameAddr) external onlyOwner{
        require(_bnbGameAddr != address(0), "Zero");
        bnbGame = LuckyGameBNB(_bnbGameAddr);
    }

    function setPercent(uint256 _flipPercent, uint256 _dicePercent) external onlyOwner{
        require(_flipPercent + _dicePercent == TOTAL_PERCENT, "Sum to TOTAL_PERCENT");
        flipPercent = _flipPercent;
        dicePercent = _dicePercent;
    }

    function isDicePlayed(address user) public view returns (bool flipPlayed, bool dicePlayed) {
        if(address(bnbGame) != address(0)){
            uint256 userBetLength = bnbGame.getUserBetLength(user);
            if(userBetLength > 0){
                uint8 modulo = 0;
                uint256 outcome = 0;
                (,uint256[] memory userBets) = bnbGame.getUserBets(user, 0, userBetLength);
                for(uint256 i = userBetLength - 1; i > 0; i --){
                    (,,,outcome,,,modulo,,) = bnbGame.bets(userBets[i]);
                    if(!flipPlayed){
                        if(modulo == 2 && outcome == 1){
                            flipPlayed = true;
                        }
                    }
                    if(!dicePlayed){
                        if(modulo == 6 && outcome == 5){
                            dicePlayed = true;
                        }
                    }

                    if(flipPlayed && dicePlayed){
                        break;
                    }
                }
                (,,,outcome,,,modulo,,) = bnbGame.bets(userBets[0]);
                if(!flipPlayed){
                    if(modulo == 2 && outcome == 1){
                        flipPlayed = true;
                    }
                }
                if(!dicePlayed){
                    if(modulo == 6 && outcome == 5){
                        dicePlayed = true;
                    }
                }
            }
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