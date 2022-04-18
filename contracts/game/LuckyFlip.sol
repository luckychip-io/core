// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IBEP20.sol";
import "../interfaces/IDice.sol";
import "../interfaces/IPancakeRouter02.sol";
import "../libraries/SafeBEP20.sol";
import "../token/DiceToken.sol";
import "../token/LCToken.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/ILuckyPower.sol";
import "../interfaces/IFlipRng.sol";

contract LuckyFlip is IDice, Ownable, ReentrancyGuard, Pausable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    uint256 public prevBankerAmount;
    uint256 public bankerAmount;
    uint256 public netValue;
    uint256 public playerEndBlock;
    uint256 public bankerEndBlock;
    uint256 public privateBetAmount;
    uint256 public playerTimeBlocks;
    uint256 public bankerTimeBlocks;
    uint256 public constant TOTAL_RATE = 10000; // 100%
    uint256 public privateGapRate = 300;// Private gap rate, default 3%
    uint256 public operationRate = 500; // 5% in gap
    uint256 public treasuryRate = 500; // 5% in gap
    uint256 public bonusRate = 2000; // 20% in gap
    uint256 public lotteryRate = 500; // 5% in gap
    uint256 public maxBankerAmount; // max amount can bank
    uint256 public privateFeeAmount; // Fee amount for private game
    uint256 public minPrivateBetAmount; // Minimum private bet amount
    uint256 public maxPrivateBetRatio = 100; // Maximum private bet amount
    uint256 public maxWithdrawFeeRatio = 20; // 0.2% for withdrawFee
    uint256 public fullyWithdrawTh = 1000; //the threshold to judge whether a user can withdraw fully, default 10%

    address public adminAddr;
    address public operationAddr;
    address public treasuryAddr;
    address public lotteryAddr;
    IOracle public oracle;
    ILuckyPower public luckyPower;
    IBEP20 public token;
    IBEP20 public lcToken;
    DiceToken public diceToken;    
    IPancakeRouter02 public swapRouter;
    IFlipRng public flipRng;

    struct BankerInfo {
        uint256 diceTokenAmount;
        uint256 avgBuyValue;
    }

    // Info of each private bet.
    struct Bet {
        // Block number
        uint256 blockNumber;
        // Address of a gambler, used to pay out winning bets.
        address gambler;
        // Wager amount in wei.
        uint256 amount;
        // Win amount.
        uint256 winAmount;
        // bet head
        bool betHead;
        // bet tail
        bool betTail;
        // Final result
        bool isHead;
        // Status of bet settlement
        bool isSettled;
    }

    // for coinflip
    Bet[] public bets;
    
    mapping(uint256 => uint) public betMap; // Mapping requestId to bet Id.
    mapping(address => uint256[]) public userBets;
    mapping(address => BankerInfo) public bankerInfo;

    event SetAdmin(address adminAddr, address operationAddr, address treasuryAddr, address lotteryAddr);
    event SetBlocks(uint256 playerTimeBlocks, uint256 bankerTimeBlocks);
    event SetRates(uint256 privateGapRate, uint256 operationRate, uint256 treasuryRate, uint256 bonusRate, uint256 lotteryRate);
    event SetAmounts(uint256 maxBankerAmount, uint256 minPrivateBetAmount, uint256 minPrivateFeeAmount);
    event SetRatios(uint256 maxWithdrawFeeRatio, uint256 maxPrivateBetRatio);
    event SetContract(address lcTokenAddr, address swapRouterAddr, address oracleAddr, address luckyPowerAddr, address flipRngAddr);
    event EndPlayerTime();
    event EndBankerTime();
    event UpdateNetValue(uint256 netValue);
    event Deposit(address indexed user, uint256 tokenAmount);
    event Withdraw(address indexed user, uint256 diceTokenAmount);

    event PrivateBetPlaced(uint256 indexed betId, address gambler, address referrer, uint256 amount, bool betHead, bool betTail);
    event PrivateBetSettled(uint256 indexed betId, address indexed gambler, uint256 amount, uint256 winAmount, bool betHead, bool betTail, bool isHead);
    event PrivateBetRefunded(uint256 indexed betId, address indexed gambler, uint256 amount);

    constructor(
        address _tokenAddr,
        address _lcTokenAddr,
        address _diceTokenAddr,
        address _flipRngAddr,
        address _operationAddr,
        address _treasuryAddr,
        address _lotteryAddr,
        uint256 _playerTimeBlocks,
        uint256 _bankerTimeBlocks,
        uint256 _maxBankerAmount,
        uint256 _minPrivateBetAmount,
        uint256 _privateFeeAmount
    ) public {
        token = IBEP20(_tokenAddr);
        lcToken = LCToken(_lcTokenAddr);
        diceToken = DiceToken(_diceTokenAddr);
        flipRng = IFlipRng(_flipRngAddr);
        operationAddr = _operationAddr;
        treasuryAddr = _treasuryAddr;
        lotteryAddr = _lotteryAddr;
        playerTimeBlocks = _playerTimeBlocks;
        bankerTimeBlocks = _bankerTimeBlocks;
        maxBankerAmount = _maxBankerAmount;
        minPrivateBetAmount = _minPrivateBetAmount;
        privateFeeAmount = _privateFeeAmount;
        netValue = uint256(1e12);
        _pause();
    }

    fallback() external payable {}
    receive() external payable {}

    modifier notContract() {
        require((!_isContract(msg.sender)) && (msg.sender == tx.origin), "no contract");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == adminAddr, "not admin");
        _;
    }

    // set blocks
    function setBlocks(uint256 _playerTimeBlocks, uint256 _bankerTimeBlocks) external onlyAdmin {
        playerTimeBlocks = _playerTimeBlocks;
        bankerTimeBlocks = _bankerTimeBlocks;
        emit SetBlocks(playerTimeBlocks, bankerTimeBlocks);
    }

    // set rates
    function setRates(uint256 _privateGapRate, uint256 _operationRate, uint256 _treasuryRate, uint256 _bonusRate, uint256 _lotteryRate) external onlyAdmin {
        require(_privateGapRate <= 1000 && _operationRate.add(_treasuryRate).add(_bonusRate).add(_lotteryRate) <= TOTAL_RATE, "rate limit");
        privateGapRate = _privateGapRate;
        operationRate = _operationRate;
        treasuryRate = _treasuryRate;
        bonusRate = _bonusRate;
        lotteryRate = _lotteryRate;
        emit SetRates(privateGapRate, operationRate, treasuryRate, bonusRate, lotteryRate);
    }

    // set amounts
    function setAmounts(uint256 _maxBankerAmount, uint256 _minPrivateBetAmount, uint256 _privateFeeAmount) external onlyAdmin {
        maxBankerAmount = _maxBankerAmount;
        minPrivateBetAmount = _minPrivateBetAmount;
        privateFeeAmount = _privateFeeAmount;
        emit SetAmounts(maxBankerAmount, minPrivateBetAmount, privateFeeAmount);
    }

    // set ratios
    function setRatios(uint256 _maxWithdrawFeeRatio, uint256 _maxPrivateBetRatio) external onlyAdmin {
        require(_maxWithdrawFeeRatio <= 100 && maxPrivateBetRatio <= 500, "ratio limit");
        maxWithdrawFeeRatio = _maxWithdrawFeeRatio;
        maxPrivateBetRatio = _maxPrivateBetRatio;
        emit SetRatios(maxWithdrawFeeRatio, maxPrivateBetRatio);
    }

    // set admin address
    function setAdmin(address _adminAddr, address _operationAddr, address _treasuryAddr, address _lotteryAddr) external onlyOwner {
        require(_adminAddr != address(0) && _operationAddr != address(0) && _treasuryAddr != address(0) && _lotteryAddr != address(0), "Zero");
        adminAddr = _adminAddr;
        operationAddr = _operationAddr;
        treasuryAddr = _treasuryAddr;
        lotteryAddr = _lotteryAddr;
        emit SetAdmin(adminAddr, operationAddr, treasuryAddr, lotteryAddr);
    }

    // Update the swap router.
    function setContract(address _lcTokenAddr, address _router, address _oracleAddr, address _luckyPowerAddr, address _flipRngAddr) external onlyAdmin {
        lcToken = LCToken(_lcTokenAddr);
        swapRouter = IPancakeRouter02(_router);
        oracle = IOracle(_oracleAddr);
        luckyPower = ILuckyPower(_luckyPowerAddr);
        flipRng = IFlipRng(_flipRngAddr);
        emit SetContract(_lcTokenAddr, _router, _oracleAddr, _luckyPowerAddr, _flipRngAddr);
    }

    function setFullyWithdrawTh(uint256 _fullyWithdrawTh) external onlyAdmin {
        require(_fullyWithdrawTh <= 5000, "range"); // maximum 50%
        fullyWithdrawTh = _fullyWithdrawTh;
    }

    // End banker time
    function endBankerTime() external onlyAdmin whenPaused {
        require(bankerAmount > 0, "bankerAmount gt 0");
        prevBankerAmount = bankerAmount;
        _unpause();
        emit EndBankerTime();
        
        playerEndBlock = block.number.add(playerTimeBlocks);
        bankerEndBlock = block.number.add(bankerTimeBlocks);
    }

    // end player time, triggers banker time
    function endPlayerTime() external onlyAdmin whenNotPaused{
        _pause();
        netValue = netValue.mul(bankerAmount).div(prevBankerAmount);
        emit UpdateNetValue(netValue);
        _claimBonusAndLottery();
        emit EndPlayerTime();
    }

    // Claim all bonus to LuckyPower
    function _claimBonusAndLottery() internal {
        if(privateBetAmount > 0){
            uint256 gapAmount = privateBetAmount.mul(privateGapRate).div(TOTAL_RATE);
            uint256 totalOperationAmount = 0;

            uint256 treasuryAmount = gapAmount.mul(treasuryRate).div(TOTAL_RATE);
            if(treasuryAmount > 0){
                if(address(token) == address(lcToken)){
                    lcToken.safeTransfer(treasuryAddr, treasuryAmount);
                }else if(address(swapRouter) != address(0)){
                    address[] memory path = new address[](2);
                    path[0] = address(token);
                    path[1] = address(lcToken);
                    uint256 amountOut = swapRouter.getAmountsOut(treasuryAmount, path)[1];
                    token.safeApprove(address(swapRouter), treasuryAmount);
                    uint256 lcAmount = swapRouter.swapExactTokensForTokens(treasuryAmount, amountOut.mul(98).div(100), path, address(this), block.timestamp + (5 minutes))[1];
                    lcToken.safeTransfer(treasuryAddr, lcAmount);
                }else{
                    totalOperationAmount = totalOperationAmount.add(treasuryAmount);
                }
            }

            uint256 bonusAmount = gapAmount.mul(bonusRate).div(TOTAL_RATE);
            if(bonusAmount > 0){
                if(address(luckyPower) != address(0)){
                    token.safeTransfer(address(luckyPower), bonusAmount);
                    luckyPower.updateBonus(address(token), bonusAmount);
                }else{
                    totalOperationAmount = totalOperationAmount.add(bonusAmount);
                }
            }

            uint256 operationAmount = gapAmount.mul(operationRate).div(TOTAL_RATE);
            totalOperationAmount = totalOperationAmount.add(operationAmount);
            if(totalOperationAmount > 0){
                token.safeTransfer(operationAddr, totalOperationAmount);
            }

            uint256 lotteryAmount = gapAmount.mul(lotteryRate).div(TOTAL_RATE);
            if(lotteryAmount > 0){
                token.safeTransfer(lotteryAddr, lotteryAmount);
            }

            privateBetAmount = 0;
        }
    }

    function getUserPrivateBetLength(address user) external view returns (uint256){
        return userBets[user].length;
    }

    // Return betId that a user has participated
    function getUserPrivateBets(
        address user,
        uint256 fromIndex,
        uint256 toIndex
    ) external view returns (uint256, uint256[] memory) {
        uint256 realToIndex = toIndex;
        if(realToIndex > userBets[user].length){
            realToIndex = userBets[user].length;
        }

        if(fromIndex < realToIndex){
            uint256 length = realToIndex - fromIndex;
            uint256[] memory values = new uint256[](length);
            for (uint256 i = 0; i < length; i++) {
                values[i] = userBets[user][fromIndex.add(i)];
            }
            return (length, values);
        }
    }

    function getPrivateBetsLength() external view returns (uint256){
        return bets.length;
    }

    // Place bet
    function placePrivateBet( uint256 amount, bool betHead, bool betTail, address _referrer) external payable whenNotPaused nonReentrant notContract {
        require(betHead || betTail, "At least one side");

        // Validate input data.
        address gambler = msg.sender;

        require(msg.value >= privateFeeAmount, "Wrong para");
        require(amount >= minPrivateBetAmount && amount <= bankerAmount.mul(maxPrivateBetRatio).div(TOTAL_RATE), "Range limit");

        // Check whether contract has enough funds to accept this bet.
        if(privateFeeAmount > 0){
            _safeTransferBNB(adminAddr, msg.value);
        }

        uint256 requestId = flipRng.getPrivateRandomNumber(bets.length);
        betMap[requestId] = bets.length;
        userBets[gambler].push(bets.length);

        // Record bet in event logs. Placed before pushing bet to array in order to get the correct bets.length.
        emit PrivateBetPlaced(bets.length, gambler, _referrer, amount, betHead, betTail);

        // Store bet in bet list.
        bets.push(Bet(
            {
                blockNumber: block.number,
                gambler: gambler,
                amount: amount,
                winAmount: 0,
                betHead: betHead,
                betTail: betTail,
                isHead: false,
                isSettled: false
            }
        ));

    }

    // Just for override
    function sendSecret(uint256 requestId, uint256 randomNumber) external override onlyAdmin nonReentrant {
    }

    // Settle bet. Function can only be called by fulfillRandomness function, which in turn can only be called by Chainlink VRF.
    function settlePrivateBet(uint256 requestId, uint256 randomNumber) external override nonReentrant {
        require(msg.sender == address(flipRng), "Only flipRng");

        uint256 betId = betMap[requestId];
        Bet storage bet = bets[betId];
        uint256 amount = bet.amount;

        require(amount > 0 && bet.isSettled == false, "Not Valid");

        uint256 winAmount = 0;
        bool isHead = randomNumber % 2 == 0;
        uint256 numberCount = 0;
        if(bet.betHead){
            numberCount = numberCount + 1;
        }
        if(bet.betTail){
            numberCount = numberCount + 1;
        }

        require(numberCount > 0, "At least one side");

        uint256 tmpBankerAmount = bankerAmount;
        tmpBankerAmount = tmpBankerAmount.add(amount);
        if((bet.betHead && isHead) || (bet.betTail && !isHead)){
            tmpBankerAmount = tmpBankerAmount.sub(amount.mul(2).div(numberCount).mul(TOTAL_RATE.sub(privateGapRate)).div(TOTAL_RATE));
            winAmount = amount.mul(2).div(numberCount).mul(TOTAL_RATE.sub(privateGapRate)).div(TOTAL_RATE);
            token.safeTransfer(bet.gambler, winAmount);
        }

        privateBetAmount = privateBetAmount.add(amount);

        uint256 gapAmount = amount.mul(privateGapRate).div(TOTAL_RATE);
        tmpBankerAmount = tmpBankerAmount.sub(gapAmount.mul(operationRate.add(treasuryRate).add(bonusRate).add(lotteryRate)).div(TOTAL_RATE));

        bankerAmount = tmpBankerAmount;
        bet.winAmount = winAmount;
        bet.isHead = isHead;
        bet.isSettled = true;
        
        // Record bet settlement in event log.
        emit PrivateBetSettled(betId, bet.gambler, amount, winAmount, bet.betHead, bet.betTail, isHead);
    }

    // Return the bet in the very unlikely scenario it was not settled by Chainlink VRF. 
    // In case you find yourself in a situation like this, just contact Polyroll support.
    // However, nothing precludes you from calling this method yourself.
    function refundBet(uint256 betId) external nonReentrant {
        
        Bet storage bet = bets[betId];
        uint256 amount = bet.amount;

        // Validation checks
        require(amount > 0 && bet.isSettled == false && block.number > bet.blockNumber + playerTimeBlocks, "No refundable");

        // Update bet records
        bet.isSettled = true;
        bet.winAmount = amount;

        // Send the refund.
        token.safeTransfer(bet.gambler, amount);

        // Record refund in event logs
        emit PrivateBetRefunded(betId, bet.gambler, amount);
    }

    // Deposit token to Dice as a banker, get Syrup back.
    function deposit(uint256 _tokenAmount) public whenPaused nonReentrant notContract {
        require(_tokenAmount > 0, "Amount > 0");
        require(bankerAmount.add(_tokenAmount) < maxBankerAmount, 'maxBankerAmount Limit');
        BankerInfo storage banker = bankerInfo[msg.sender];
        token.safeTransferFrom(address(msg.sender), address(this), _tokenAmount);
        uint256 diceTokenAmount = _tokenAmount.mul(1e12).div(netValue);
        diceToken.mint(address(msg.sender), diceTokenAmount);
        uint256 totalDiceTokenAmount = banker.diceTokenAmount.add(diceTokenAmount);
        banker.avgBuyValue = banker.avgBuyValue.mul(banker.diceTokenAmount).div(1e12).add(_tokenAmount).mul(1e12).div(totalDiceTokenAmount);
        banker.diceTokenAmount = totalDiceTokenAmount;
        bankerAmount = bankerAmount.add(_tokenAmount);
        emit Deposit(msg.sender, _tokenAmount);    
    }

    function getWithdrawFeeRatio(address _user) public view returns (uint256 ratio){
        ratio = 0;
        if(address(luckyPower) != address(0) && address(oracle) != address(0)){
            BankerInfo storage banker = bankerInfo[_user];
            (uint256 totalPower,,,,,) = luckyPower.pendingPower(_user);
            uint256 tokenAmount = banker.diceTokenAmount.mul(netValue).div(1e12);
            uint256 bankerTvl = oracle.getQuantity(address(token), tokenAmount);
            if(bankerTvl > 0 && fullyWithdrawTh > 0 && totalPower < bankerTvl.mul(fullyWithdrawTh).div(TOTAL_RATE)){
                // y = - x * maxWithdrawFeeRatio / fullyWithdrawTh + maxWithdrawFeeRatio
                uint256 x = totalPower.mul(TOTAL_RATE).div(bankerTvl);
                ratio = maxWithdrawFeeRatio.sub(x.mul(maxWithdrawFeeRatio).div(fullyWithdrawTh));
            }
        }
    }

    // Withdraw syrup from dice to get token back
    function withdraw(uint256 _diceTokenAmount) public whenPaused nonReentrant notContract {
        BankerInfo storage banker = bankerInfo[msg.sender];
        require(_diceTokenAmount > 0 && _diceTokenAmount <= banker.diceTokenAmount, "0 < diceTokenAmount <= banker.diceTokenAmount");
        uint256 ratio = getWithdrawFeeRatio(msg.sender);
        banker.diceTokenAmount = banker.diceTokenAmount.sub(_diceTokenAmount); 
        SafeBEP20.safeTransferFrom(diceToken, msg.sender, address(this), _diceTokenAmount);
        diceToken.burn(address(this), _diceTokenAmount);
        uint256 tokenAmount = _diceTokenAmount.mul(netValue).div(1e12);
        bankerAmount = bankerAmount.sub(tokenAmount);

        if(address(token) != address(lcToken)){
            if(ratio > 0){
                uint256 withdrawFee = tokenAmount.mul(ratio).div(TOTAL_RATE);
                if(withdrawFee > 0){
                    token.safeTransfer(operationAddr, withdrawFee);
                }
                tokenAmount = tokenAmount.sub(withdrawFee);
            }
        }

        if(tokenAmount > 0){
            token.safeTransfer(address(msg.sender), tokenAmount);
        }
        
        emit Withdraw(msg.sender, _diceTokenAmount);
    }

    // Judge address is contract or not
    function _isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    // View function to see banker diceToken Value on frontend.
    function canWithdrawToken(address bankerAddr) external view returns (uint256){
        return bankerInfo[bankerAddr].diceTokenAmount.mul(netValue).div(1e12);    
    }

    // View function to see banker diceToken Value on frontend.
    function canWithdrawAmount(uint256 _amount) external override view returns (uint256){
        return _amount.mul(netValue).div(1e12);    
    }

    function _safeTransferBNB(address to, uint256 value) internal {
        (bool success, ) = to.call{gas: 23000, value: value}("");
        require(success, 'BNB_TRANSFER_FAILED');
    }

    function tokenAddr() public override view returns (address){
        return address(token);
    }

}
