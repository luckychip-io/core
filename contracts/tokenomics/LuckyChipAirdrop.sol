// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/cryptography/MerkleProof.sol";
import "../interfaces/IBEP20.sol";
import "../libraries/SafeBEP20.sol";

interface ILuckyGame {
    function getUserBetLength(address user) external view returns (uint256);
}

/**
 * @title LuckyChipAirdrop
 * @notice It distributes LC tokens with a Merkle-tree airdrop.
 */
contract LuckyChipAirdrop is Pausable, ReentrancyGuard, Ownable {
    using SafeBEP20 for IBEP20;
    using SafeMath for uint256;

    IBEP20 public immutable lcToken;
    uint256 public immutable MAXIMUM_AMOUNT_TO_CLAIM;

    bool public isMerkleRootSet;
    bytes32 public merkleRoot;
    uint256 public endTimestamp;

    ILuckyGame public bnbGame;

    mapping(address => bool) public hasClaimed;
    mapping(address => uint256) public claimedAmount;

    event AirdropRewardsClaim(address indexed user, uint256 amount);
    event MerkleRootSet(bytes32 merkleRoot);
    event NewEndTimestamp(uint256 endTimestamp);
    event TokensWithdrawn(uint256 amount);

    /**
     * @notice Constructor
     * @param _endTimestamp end timestamp for claiming
     * @param _maximumAmountToClaim maximum amount to claim per a user
     * @param _lcToken address of the lc token
     * @param _bnbGameAddr address of the lucky game
     */
    constructor(
        uint256 _endTimestamp,
        uint256 _maximumAmountToClaim,
        address _lcToken,
        address _bnbGameAddr
    ) public {
        endTimestamp = _endTimestamp;
        MAXIMUM_AMOUNT_TO_CLAIM = _maximumAmountToClaim;

        lcToken = IBEP20(_lcToken);
        bnbGame = ILuckyGame(_bnbGameAddr);
    }

    /**
     * @notice Claim tokens for airdrop
     * @param amount amount to claim for the airdrop
     * @param merkleProof array containing the merkle proof
     */
    function claim(
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external whenNotPaused nonReentrant {
        require(isMerkleRootSet, "Airdrop: Merkle root not set");
        require(amount <= MAXIMUM_AMOUNT_TO_CLAIM, "Airdrop: Amount too high");
        require(block.timestamp <= endTimestamp, "Airdrop: Too late to claim");

        // Verify the user has claimed
        require(!hasClaimed[msg.sender], "Airdrop: Already claimed");

        // Compute the node and verify the merkle proof
        bytes32 node = keccak256(abi.encodePacked(msg.sender, amount));
        require(MerkleProof.verify(merkleProof, merkleRoot, node), "Airdrop: Invalid proof");

        // Set as claimed
        if(address(bnbGame) != address(0) && bnbGame.getUserBetLength(msg.sender) > 0 && !hasClaimed[msg.sender]){
            hasClaimed[msg.sender] = true;
            claimedAmount[msg.sender] = claimedAmount[msg.sender].add(amount);
            lcToken.safeTransfer(msg.sender, amount);
            emit AirdropRewardsClaim(msg.sender, amount);
        }
    }

    /**
     * @notice Check whether it is possible to claim (it doesn't check orders)
     * @param user address of the user
     * @param amount amount to claim
     * @param merkleProof array containing the merkle proof
     */
    function canClaim(
        address user,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) public view returns (bool) {
        if (block.timestamp <= endTimestamp) {
            // Compute the node and verify the merkle proof
            bytes32 node = keccak256(abi.encodePacked(user, amount));
            return MerkleProof.verify(merkleProof, merkleRoot, node);
        } else {
            return false;
        }
    }

    /**
     * @notice Check whether it is possible to claim (it doesn't check orders)
     * @param user address of the user
     * @param amount amount to claim
     * @param merkleProof array containing the merkle proof
     */
    function pendingAirdrop(
        address user,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) public view returns (uint256) {
        if (block.timestamp <= endTimestamp) {
            // Compute the node and verify the merkle proof
            bytes32 node = keccak256(abi.encodePacked(user, amount));
            if(MerkleProof.verify(merkleProof, merkleRoot, node)){
                if(address(bnbGame) != address(0) && bnbGame.getUserBetLength(user) > 0 && !hasClaimed[user]){
                    return amount;
                }else{
                   return 0;
                }
            }else{
                return 0;
            }
        } else {
            return 0;
        }
    }

    function setGame(address _bnbGameAddr) external onlyOwner{
        require(_bnbGameAddr != address(0), "Zero");
        bnbGame = ILuckyGame(_bnbGameAddr);
    }

    function isGamePlayed(address user) public view returns (bool gamePlayed) {
        if(address(bnbGame) != address(0) && bnbGame.getUserBetLength(user) > 0){
            gamePlayed = true;
        }
    }

    /**
     * @notice Pause airdrop
     */
    function pauseAirdrop() external onlyOwner whenNotPaused {
        _pause();
    }

    /**
     * @notice Set merkle root for airdrop
     * @param _merkleRoot merkle root
     */
    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        require(!isMerkleRootSet, "Owner: Merkle root already set");

        isMerkleRootSet = true;
        merkleRoot = _merkleRoot;

        emit MerkleRootSet(_merkleRoot);
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