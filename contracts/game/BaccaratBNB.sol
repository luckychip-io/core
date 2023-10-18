// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IBEP20.sol";
import "../interfaces/IWBNB.sol";
import "../interfaces/IGame.sol";
import "../interfaces/IRouter.sol";
import "../libraries/SafeBEP20.sol";
import "../token/GameToken.sol";
import "../token/LCToken.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/ILuckyPower.sol";
import "../interfaces/IGameRng.sol";

contract BaccaratBNB is IGame, Ownable, ReentrancyGuard, Pausable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    uint256 public prevBankerAmount; // previous banker amount
    uint256 public bankerAmount; // current banker amount
    uint256 public netValue; // net value
    uint256 public playerEndBlock;
    uint256 public bankerEndBlock;
    uint256 public betAmount;
    uint256 public playerTimeBlocks;
    uint256 public bankerTimeBlocks;
    uint256 public constant TOTAL_RATE = 10000; // 100%
    uint256 public operationRate = 500; // 5% of banker profit to operation address
    uint256 public treasuryRate = 500; // 5% of banker profit to treasury address
    uint256 public bonusRate = 2000; // 20% of banker profit to bonus address
    uint256 public lotteryRate = 500; // 5% of banker profit to lottery address
    uint256 public maxBankerAmount; // max amount can bank
    uint256 public offChainFeeAmount; // Off-chain fee amount for rng
    uint256 public onChainFeeAmount; // On-chain fee amount for rng
    uint256 public minBetAmount; // Minimum bet amount
    uint256 public maxBetRatio = 100; // Maximum bet amount
    uint256 public maxWithdrawFeeRatio = 20; // 0.2% for withdrawFee
    uint256 public fullyWithdrawTh = 1000; //the threshold to judge whether a user can withdraw fully, default 10%
    uint256 public defaultSwapRouterId = 0; // 0 for pancakeswap, 1 for biswap, 2 for apeswap, 3 for babyswap

    address public operationAddr;
    address public treasuryAddr;
    address public lotteryAddr;
    IOracle public oracle;
    ILuckyPower public luckyPower;
    address public immutable WBNB;
    IBEP20 public lcToken;
    GameToken public gameToken;
    IGameRng public gameRng;

    // Info of each bet.
    struct Bet {
        // Address of a gambler, used to pay out winning bets.
        address gambler;
        // Block number of placeBet
        uint256 blockNumber;
        // Bet amount(in wei), [banker_amount, player_amount, tie_amount, banker_pairs_amount, player_pairs_amount]
        uint256[5] amounts;
        // Win amount.
        uint256 winAmount;
        // Cards of banker
        uint8[3] bankerCards;
        // Cards of player
        uint8[3] playerCards;
        // Final poionts [bankerPoint, playerPoint]
        uint8[2] finalPoints;
        // Poker nums of banker and player [bankerPokerNum, playerPokerNum]
        uint8[2] pokerNums;
        // Use random number generator on chain or not. If rngOnChain==true, use VRF from ChainLink, else use rng off-line
        bool rngOnChain;
        // Status of bet settlement
        bool isSettled;
    }

    // for coinflip
    Bet[] public bets;
    address[] public swapRouters;
    mapping(uint256 => uint) public betMap; // Mapping requestId to bet Id.
    mapping(address => uint256[]) public userBets;
    mapping(address => uint256) public bankerInfo;

    event SetAdmin(address operationAddr, address treasuryAddr, address lotteryAddr);
    event SetRates(uint256 operationRate, uint256 treasuryRate, uint256 bonusRate, uint256 lotteryRate);
    event SetAmounts(uint256 maxBankerAmount, uint256 minBetAmount, uint256 offChainFeeAmount, uint256 onChainFeeAmount);
    event SetRatios(uint256 maxWithdrawFeeRatio, uint256 maxBetRatio);
    event SetContract(address lcTokenAddr, address oracleAddr, address luckyPowerAddr, address flipRngAddr);
    event EndPlayerTime();
    event EndBankerTime();
    event UpdateNetValue(uint256 netValue);
    event Deposit(address indexed user, uint256 tokenAmount);
    event Withdraw(address indexed user, uint256 gameTokenAmount);

    event BetPlaced(uint256 indexed betId, address indexed gambler, uint256[5] amounts, bool rngOnChain);
    event SwapBetPlaced(uint256 indexed betId, address indexed gambler, address tokenAddr, uint256[5] tokenAmounts, uint256[5] amounts, bool rngOnChain);
    event BetSettled(uint256 indexed betId, address indexed gambler, uint256[5] amounts, uint256 winAmount, uint8[3] bankerCards, uint8[3] playerCards, uint8[2] finalPoints, uint8[2] pokerNums, bool rngOnChain);
    event BetRefunded(uint256 indexed betId, address indexed gambler, uint256[5] amounts, uint256 amount);

    constructor(
        address _WBNBAddr,
        address _lcTokenAddr,
        address _gameTokenAddr,
        address _gameRngAddr,
        address _operationAddr,
        address _treasuryAddr,
        address _lotteryAddr,
        uint256 _playerTimeBlocks,
        uint256 _bankerTimeBlocks,
        uint256 _maxBankerAmount,
        uint256 _minBetAmount,
        uint256 _offChainFeeAmount,
        uint256 _onChainFeeAmount
    ) public {
        WBNB = _WBNBAddr;
        lcToken = LCToken(_lcTokenAddr);
        gameToken = GameToken(_gameTokenAddr);
        gameRng = IGameRng(_gameRngAddr);
        operationAddr = _operationAddr;
        treasuryAddr = _treasuryAddr;
        lotteryAddr = _lotteryAddr;
        playerTimeBlocks = _playerTimeBlocks;
        bankerTimeBlocks = _bankerTimeBlocks;
        maxBankerAmount = _maxBankerAmount;
        minBetAmount = _minBetAmount;
        offChainFeeAmount = _offChainFeeAmount;
        onChainFeeAmount = _onChainFeeAmount;
        netValue = uint256(1e12);
        _pause();
    }

    fallback() external payable {}
    receive() external payable {}

    modifier notContract() {
        require((!_isContract(msg.sender)) && (msg.sender == tx.origin), "no contract");
        _;
    }

    // set blocks
    function setBlocks(uint256 _playerTimeBlocks, uint256 _bankerTimeBlocks) external onlyOwner {
        playerTimeBlocks = _playerTimeBlocks;
        bankerTimeBlocks = _bankerTimeBlocks;
    }

    // set rates
    function setRates(uint256 _operationRate, uint256 _treasuryRate, uint256 _bonusRate, uint256 _lotteryRate) external onlyOwner {
        require(_operationRate.add(_treasuryRate).add(_bonusRate).add(_lotteryRate) <= TOTAL_RATE.div(2), "rate limit");
        operationRate = _operationRate;
        treasuryRate = _treasuryRate;
        bonusRate = _bonusRate;
        lotteryRate = _lotteryRate;
        emit SetRates(operationRate, treasuryRate, bonusRate, lotteryRate);
    }

    // set amounts
    function setAmounts(uint256 _maxBankerAmount, uint256 _minBetAmount, uint256 _offChainFeeAmount, uint256 _onChainFeeAmount) external onlyOwner {
        maxBankerAmount = _maxBankerAmount;
        minBetAmount = _minBetAmount;
        offChainFeeAmount = _offChainFeeAmount;
        onChainFeeAmount = _onChainFeeAmount;
        emit SetAmounts(maxBankerAmount, minBetAmount, offChainFeeAmount, onChainFeeAmount);
    }

    // set ratios
    function setRatios(uint256 _maxWithdrawFeeRatio, uint256 _maxBetRatio) external onlyOwner {
        require(_maxWithdrawFeeRatio <= 100 && _maxBetRatio <= 500, "ratio limit");
        maxWithdrawFeeRatio = _maxWithdrawFeeRatio;
        maxBetRatio = _maxBetRatio;
        emit SetRatios(maxWithdrawFeeRatio, maxBetRatio);
    }

    // set address
    function setAdmin(address _operationAddr, address _treasuryAddr, address _lotteryAddr) external onlyOwner {
        require(_operationAddr != address(0) && _treasuryAddr != address(0) && _lotteryAddr != address(0), "Zero");
        operationAddr = _operationAddr;
        treasuryAddr = _treasuryAddr;
        lotteryAddr = _lotteryAddr;
        emit SetAdmin(operationAddr, treasuryAddr, lotteryAddr);
    }

    // Update the swap router.
    function setContract(address _lcTokenAddr, address _oracleAddr, address _luckyPowerAddr, address _gameRngAddr) external onlyOwner {
        lcToken = LCToken(_lcTokenAddr);
        oracle = IOracle(_oracleAddr);
        luckyPower = ILuckyPower(_luckyPowerAddr);
        gameRng = IGameRng(_gameRngAddr);
        emit SetContract(_lcTokenAddr, _oracleAddr, _luckyPowerAddr, _gameRngAddr);
    }

    function setOtherParas(uint256 _fullyWithdrawTh, uint256 _defaultSwapRouterId) external onlyOwner {
        require(_fullyWithdrawTh <= 5000, "Not valid"); // maximum 50%
        fullyWithdrawTh = _fullyWithdrawTh;
        defaultSwapRouterId = _defaultSwapRouterId;
    }

    function addSwapRouter(address swapRouterAddr) external onlyOwner {
        require(swapRouterAddr != address(0), "Zero address");
        swapRouters.push(swapRouterAddr);
    }

    function getSwapRoutersLength() external view returns (uint256){
        return swapRouters.length;
    }

    // End banker time
    function endBankerTime() external onlyOwner whenPaused {
        require(bankerAmount > 0, "bankerAmount gt 0");
        prevBankerAmount = bankerAmount;
        _unpause();
        emit EndBankerTime();
        
        playerEndBlock = block.number.add(playerTimeBlocks);
        bankerEndBlock = block.number.add(bankerTimeBlocks);
    }

    // end player time, triggers banker time
    function endPlayerTime() external onlyOwner whenNotPaused {
        _pause();
        _claimBonusAndLottery();
        netValue = netValue.mul(bankerAmount).div(prevBankerAmount);
        emit UpdateNetValue(netValue);
        emit EndPlayerTime();
    }

    // Claim all bonus to LuckyPower
    function _claimBonusAndLottery() internal {
        
        if(bankerAmount > prevBankerAmount){
            uint256 gapAmount = bankerAmount.sub(prevBankerAmount);
            bankerAmount = bankerAmount.sub(gapAmount.mul(operationRate.add(treasuryRate).add(bonusRate).add(lotteryRate)).div(TOTAL_RATE));
            
            uint256 totalOperationAmount = 0;

            uint256 treasuryAmount = gapAmount.mul(treasuryRate).div(TOTAL_RATE);
            if(treasuryAmount > 0){
                if(defaultSwapRouterId < swapRouters.length && swapRouters[defaultSwapRouterId] != address(0)){
                    IRouter swapRouter = IRouter(swapRouters[defaultSwapRouterId]);
                    address[] memory path = new address[](2);
                    path[0] = WBNB;
                    path[1] = address(lcToken);
                    uint256 amountOut = swapRouter.getAmountsOut(treasuryAmount, path)[1];
                    uint256 lcAmount = swapRouter.swapExactETHForTokens{value: treasuryAmount}(amountOut.mul(995).div(1000), path, address(this), block.timestamp + (5 minutes))[1];
                    lcToken.safeTransfer(treasuryAddr, lcAmount);
                }else{
                    totalOperationAmount = totalOperationAmount.add(treasuryAmount);
                }
            }

            uint256 bonusAmount = gapAmount.mul(bonusRate).div(TOTAL_RATE);
            if(bonusAmount > 0){
                if(address(luckyPower) != address(0)){
                    IWBNB(WBNB).deposit{value: bonusAmount}();
                    assert(IWBNB(WBNB).transfer(address(luckyPower), bonusAmount));
                    luckyPower.updateBonus(WBNB, bonusAmount);
                }else{
                    totalOperationAmount = totalOperationAmount.add(bonusAmount);
                }
            }

            uint256 operationAmount = gapAmount.mul(operationRate).div(TOTAL_RATE);
            totalOperationAmount = totalOperationAmount.add(operationAmount);
            if(totalOperationAmount > 0){
                _safeTransferBNB(operationAddr, totalOperationAmount);
            }

            uint256 lotteryAmount = gapAmount.mul(lotteryRate).div(TOTAL_RATE);
            if(lotteryAmount > 0){
                _safeTransferBNB(lotteryAddr, lotteryAmount);
            }
        }
    }

    function getUserBetLength(address user) external view returns (uint256){
        return userBets[user].length;
    }

    // Return betId that a user has participated
    function getUserBets(
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

    function getBetsLength() external view returns (uint256){
        return bets.length;
    }

    // Place bet
    function placeBet(uint256[5] calldata amounts, bool rngOnChain) external payable whenNotPaused nonReentrant notContract {
        // Validate input data.
        uint256 amount;
        for(uint256 i = 0; i < 5; i ++){
            amount = amount.add(amounts[i]);
        }
        
        if(rngOnChain){
            require(msg.value >= amount.add(onChainFeeAmount), "Wrong para");
            if(onChainFeeAmount > 0){
                _safeTransferBNB(owner(), onChainFeeAmount);
            }
        }else{
            require(msg.value >= amount.add(offChainFeeAmount), "Wrong para");
            if(offChainFeeAmount > 0){
                _safeTransferBNB(owner(), offChainFeeAmount);
            }
        }

        require(amount >= minBetAmount && amount <= bankerAmount.mul(maxBetRatio).div(TOTAL_RATE), "Range limit");

        uint256 requestId;
        if(rngOnChain){
            requestId = gameRng.getRandomNumberOnChain(bets.length);
        }else{
            requestId = gameRng.getRandomNumberOffChain(bets.length);
        }

        betMap[requestId] = bets.length;
        userBets[msg.sender].push(bets.length);

        // Record bet in event logs. Placed before pushing bet to array in order to get the correct bets.length.
        emit BetPlaced(bets.length, msg.sender, amounts, rngOnChain);

        // Store bet in bet list.
        bets.push(Bet(
            {
                gambler: msg.sender,
                blockNumber: block.number,
                amounts: amounts,
                winAmount: 0,
                bankerCards: new uint8[](3),
                playerCards: new uint8[](3),
                finalPoints: new uint8[](2),
                pokerNums: new uint8[](2),
                rngOnChain: rngOnChain,
                isSettled: false
            }
        ));
    }

    // swap and place bet
    function swapAndBet(address tokenAddr, uint256[5] calldata tokenAmounts, uint256 swapRounterId, uint256 slippage, bool rngOnChain) external payable whenNotPaused nonReentrant notContract {
        require(swapRounterId < swapRouters.length, "Para error");
        
        uint256 amount;
        uint256 tokenAmount;
        for(uint256 i = 0; i < 5; i ++){
            tokenAmount = tokenAmount.add(tokenAmounts[i]);
        }

        {
            IBEP20(tokenAddr).safeTransferFrom(address(msg.sender), address(this), tokenAmount);
            address[] memory path = new address[](2);
            path[0] = tokenAddr;
            path[1] = WBNB;
            IRouter swapRouter = IRouter(swapRouters[swapRounterId]);
            uint256 amountOut = swapRouter.getAmountsOut(tokenAmount, path)[1];
            IBEP20(tokenAddr).safeApprove(address(swapRouter), tokenAmount);
            amount = swapRouter.swapExactTokensForETH(tokenAmount, amountOut.mul(TOTAL_RATE).div(TOTAL_RATE.add(slippage)), path, address(this), block.timestamp + (5 minutes))[1];
        }

        // Validate input data.
        if(rngOnChain){
            require(msg.value >= onChainFeeAmount, "Wrong para");
            if(onChainFeeAmount > 0){
                _safeTransferBNB(owner(), onChainFeeAmount);
            }
        }else{
            require(msg.value >= offChainFeeAmount, "Wrong para");
            if(offChainFeeAmount > 0){
                _safeTransferBNB(owner(), offChainFeeAmount);
            }
        }

        require(amount >= minBetAmount && amount <= bankerAmount.mul(maxBetRatio).div(TOTAL_RATE), "Range limit");
        uint256[5] memory amounts = new uint256[](5);
        for(uint256 i = 0; i < 5; i ++){
            amounts[i] = amount.mul(tokenAmounts[i]).div(tokenAmount);
        }

        uint256 requestId;
        if(rngOnChain){
            requestId = gameRng.getRandomNumberOnChain(bets.length);
        }else{
            requestId = gameRng.getRandomNumberOffChain(bets.length);
        }

        betMap[requestId] = bets.length;
        userBets[msg.sender].push(bets.length);

        // Record bet in event logs. Placed before pushing bet to array in order to get the correct bets.length.
        emit SwapBetPlaced(bets.length, msg.sender, tokenAddr, tokenAmounts, amounts, rngOnChain);

        // Store bet in bet list.
        bets.push(Bet(
            {
                gambler: msg.sender,
                blockNumber: block.number,
                amounts: amounts,
                winAmount: 0,
                bankerCards: new uint8[](3),
                playerCards: new uint8[](3),
                finalPoints: new uint8[](2),
                pokerNums: new uint8[](2),
                rngOnChain: rngOnChain,
                isSettled: false
            }
        ));
    }

    // Get different digits of random number
    function getNumberDigit(uint number, uint start, uint long) public returns (uint) {
        return (number / (10 ** start)) % (10 ** long);
    }

    // Settle bet. Function can only be called by fulfillRandomness function, which in turn can only be called by Chainlink VRF.
    function settleBet(uint256 requestId, uint256 randomNumber) external override nonReentrant {
        require(msg.sender == address(gameRng), "Only gameRng");

        uint256 betId = betMap[requestId];
        Bet storage bet = bets[betId];
        uint256 amount;
        for(uint256 i = 0; i < 5; i ++){
            amount = amount.add(bet.amounts[i]);
        }

        if(amount > 0 && bet.isSettled == false){
            randomNumber = randomNumber ^ (uint256(keccak256(abi.encode(block.timestamp, block.difficulty))) % 1000000000000000000);

            // Cards of banker
            uint8[3] memory bankerCards = new uint8[](3);
            // Cards of player
            uint8[3] memory playerCards = new uint8[](3);
            
            for (uint i = 0; i < 6; i++)
            {
                if(i < 3){
                    playerCards[i] = getNumberDigit(randomNumber, 1 + i * 3, 3) % (52 * 8);
                }else{
                    bankerCards[i - 3] = getNumberDigit(randomNumber, 1 + i * 3, 3) % (52 * 8);
                }
            }

            // Final poionts [bankerPoint, playerPoint]
            uint8[2] memory finalPoints = new uint8[](3);
            // Poker nums of banker and player [bankerPokerNum, playerPokerNum]
            uint8[2] memory pokerNums = [2, 2];

            // A ~ K  1 ~ 13
            uint256 playerCard0 = (playerCards[0] % 13 + 1) >= 10 ? 0 : (playerCards[0] % 13 + 1);
            uint256 playerCard1 = (playerCards[1] % 13 + 1) >= 10 ? 0 : (playerCards[1] % 13 + 1);
            uint256 playerCard2 = (playerCards[2] % 13 + 1) >= 10 ? 0 : (playerCards[2] % 13 + 1);

            uint256 bankerCard0 = (bankerCards[0] % 13 + 1) >= 10 ? 0 : (bankerCards[0] % 13 + 1);
            uint256 bankerCard1 = (bankerCards[1] % 13 + 1) >= 10 ? 0 : (bankerCards[1] % 13 + 1);
            uint256 bankerCard2 = (bankerCards[2] % 13 + 1) >= 10 ? 0 : (bankerCards[2] % 13 + 1);

            uint256 playerTwoCardPoint = (playerCard0 + playerCard1) % 10;
            uint256 bankerTwoCardPoint = (bankerCard0 + bankerCard1) % 10;
            uint256 playerThreeCardPoint = (playerCard0 + playerCard1 + playerCard2) % 10;
            uint256 bankerThreeCardPoint = (bankerCard0 + bankerCard1 + bankerCard2) % 10;

            uint256 playerFinalPoint = 0;
            uint256 bankerFinalPoint = 0;

            // Drawing rules
            if (playerTwoCardPoint < 6 && bankerTwoCardPoint < 8) {// Player need to draw a third card
                playerFinalPoint = playerThreeCardPoint;
                pokerNums[0] = 3;
            } else {
                playerFinalPoint = playerTwoCardPoint;
                pokerNums[0] = 2;
            }

            if (bankerTwoCardPoint < 7 && playerTwoCardPoint < 8) {// Banker need to draw a third card
                if (bankerTwoCardPoint < 3) {
                    bankerFinalPoint = bankerThreeCardPoint;
                    pokerNums[1] = 3;
                } else {
                    if (playerTwoCardPoint < 6) {// Player has draw a third card
                        if (bankerTwoCardPoint == 3 && playerCard2 != 8) {
                            bankerFinalPoint = bankerThreeCardPoint;
                            pokerNums[1] = 3;
                        } else if (bankerTwoCardPoint == 4 && playerCard2 > 1 && playerCard2 < 8) {
                            bankerFinalPoint = bankerThreeCardPoint;
                            pokerNums[1] = 3;
                        } else if (bankerTwoCardPoint == 5 && playerCard2 > 3 && playerCard2 < 8) {
                            bankerFinalPoint = bankerThreeCardPoint;
                            pokerNums[1] = 3;
                        } else if (bankerTwoCardPoint == 6 && playerCard2 > 5 && playerCard2 < 8) {
                            bankerFinalPoint = bankerThreeCardPoint;
                            pokerNums[1] = 3;
                        } else {
                            bankerFinalPoint = bankerTwoCardPoint;
                            pokerNums[1] = 2;
                        }
                    } else {// Player hasn't draw a third card
                        if (bankerTwoCardPoint < 6) {
                            bankerFinalPoint = bankerThreeCardPoint;
                            pokerNums[1] = 3;
                        } else {
                            bankerFinalPoint = bankerTwoCardPoint;
                            pokerNums[1] = 2;
                        }
                    }
                }
            } else {
                bankerFinalPoint = bankerTwoCardPoint;
                pokerNums[1] = 2;
            }

            finalPoints = [playerFinalPoint, bankerFinalPoint];

            // Actual win amount by gambler.
            uint256 winAmount = 0;
            if(bankerFinalPoint > playerFinalPoint){
                if(bet.amounts[0] > 0){
                    winAmount = bet.amounts[0].add(bet.amounts[0].mul(9500).div(TOTAL_RATE));
                }
            }else if(bankerFinalPoint < playerFinalPoint){
                if(bet.amounts[1] > 0){
                    winAmount = bet.amounts[1].mul(2);
                }
            }else{
                if(bet.amounts[2] > 0){
                    winAmount = bet.amounts[2].mul(9);
                }
                if(bet.amounts[0] > 0){ // return banker's money back
                    winAmount = winAmount.add(bet.amounts[0]);
                }
                if(bet.amounts[1] > 0){ // return player's money back
                    winAmount = winAmount.add(bet.amounts[1]);
                }
            }

            // BANKER_PAIRS
            if(bet.amounts[3] > 0 && bankerCard0 == bankerCard1){
                winAmount = winAmount.add(bet.amounts[3].mul(12));
            }

            // PLAYER_PAIRS
            if(bet.amounts[4] > 0 && playerCard0 == playerCard1){
                winAmount = winAmount.add(bet.amounts[4].mul(12));
            }

            uint256 tmpBankerAmount = bankerAmount;
            tmpBankerAmount = tmpBankerAmount.add(amount);
            if(winAmount > 0){
                tmpBankerAmount = tmpBankerAmount.sub(winAmount);
                _safeTransferBNB(bet.gambler, winAmount);
            }

            betAmount = betAmount.add(amount);
            
            bankerAmount = tmpBankerAmount;

            bet.winAmount = winAmount;
            bet.bankerCards = bankerCards;
            bet.playerCards = playerCards;
            bet.finalPoints = finalPoints;
            bet.pokerNums = pokerNums;
            bet.isSettled = true;
            
            // Record bet settlement in event log.
            emit BetSettled(betId, bet.gambler, bet.amounts, winAmount, bankerCards, playerCards, finalPoints, pokerNums);
        }
    }

    // Return the bet in the very unlikely scenario it was not settled by Chainlink VRF. 
    // In case you find yourself in a situation like this, just contact Polyroll support.
    // However, nothing precludes you from calling this method yourself.
    function refundBet(uint256 betId) external nonReentrant {
        
        Bet storage bet = bets[betId];
        uint256 amount;
        for(uint256 i = 0; i < 5; i ++){
            amount = amount.add(bet.amounts[i]);
        }

        // Validation checks
        require(amount > 0 && bet.isSettled == false && block.number > bet.blockNumber + playerTimeBlocks, "No refundable");

        // Update bet records
        bet.isSettled = true;
        bet.winAmount = amount;

        // Send the refund.
        _safeTransferBNB(bet.gambler, amount);

        // Record refund in event logs
        emit BetRefunded(betId, bet.gambler, bet.amounts, amount);
    }

    // Deposit token to Dice as a banker, get Syrup back.
    function deposit() public payable whenPaused nonReentrant notContract {
        uint256 _tokenAmount = msg.value;
        require(_tokenAmount > 0 && bankerAmount.add(_tokenAmount) < maxBankerAmount, 'Amount Limit');
        uint256 prevGameTokenAmount = bankerInfo[msg.sender];
        uint256 gameTokenAmount = _tokenAmount.mul(1e12).div(netValue);
        gameToken.mint(address(msg.sender), gameTokenAmount);
        uint256 totalGameTokenAmount = prevGameTokenAmount.add(gameTokenAmount);
        bankerInfo[msg.sender] = totalGameTokenAmount;
        bankerAmount = bankerAmount.add(_tokenAmount);
        emit Deposit(msg.sender, _tokenAmount);    
    }

    function getWithdrawFeeRatio(address _user) public view returns (uint256 ratio){
        ratio = 0;
        if(address(luckyPower) != address(0) && address(oracle) != address(0)){
            uint256 gameTokenAmount = bankerInfo[msg.sender];
            (uint256 totalPower,,,,,) = luckyPower.pendingPower(_user);
            uint256 tokenAmount = gameTokenAmount.mul(netValue).div(1e12);
            uint256 bankerTvl = oracle.getQuantity(WBNB, tokenAmount);
            if(bankerTvl > 0 && fullyWithdrawTh > 0 && totalPower < bankerTvl.mul(fullyWithdrawTh).div(TOTAL_RATE)){
                // y = - x * maxWithdrawFeeRatio / fullyWithdrawTh + maxWithdrawFeeRatio
                uint256 x = totalPower.mul(TOTAL_RATE).div(bankerTvl);
                ratio = maxWithdrawFeeRatio.sub(x.mul(maxWithdrawFeeRatio).div(fullyWithdrawTh));
            }
        }
    }

    // Withdraw syrup from dice to get token back
    function withdraw(uint256 _gameTokenAmount) public whenPaused nonReentrant notContract {
        uint256 prevGameTokenAmount = bankerInfo[msg.sender];
        require(_gameTokenAmount > 0 && _gameTokenAmount <= prevGameTokenAmount, "0 < gameTokenAmount <= prevGameTokenAmount");
        uint256 ratio = getWithdrawFeeRatio(msg.sender);
        bankerInfo[msg.sender] = prevGameTokenAmount.sub(_gameTokenAmount); 
        SafeBEP20.safeTransferFrom(gameToken, msg.sender, address(this), _gameTokenAmount);
        gameToken.burn(address(this), _gameTokenAmount);
        uint256 tokenAmount = _gameTokenAmount.mul(netValue).div(1e12);
        bankerAmount = bankerAmount.sub(tokenAmount);

        if(ratio > 0){
            uint256 withdrawFee = tokenAmount.mul(ratio).div(TOTAL_RATE);
            if(withdrawFee > 0){
                _safeTransferBNB(operationAddr, withdrawFee);
            }
            tokenAmount = tokenAmount.sub(withdrawFee);
        }

        if(tokenAmount > 0){
            _safeTransferBNB(address(msg.sender), tokenAmount);
        }
        
        emit Withdraw(msg.sender, _gameTokenAmount);
    }

    // Judge address is contract or not
    function _isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    // View function to see banker gameToken Value on frontend.
    function canWithdrawToken(address bankerAddr) external view returns (uint256){
        return bankerInfo[bankerAddr].mul(netValue).div(1e12);
    }

    // View function to see banker gameToken Value on frontend.
    function canWithdrawAmount(uint256 _amount) external override view returns (uint256){
        return _amount.mul(netValue).div(1e12);    
    }

    function _safeTransferBNB(address to, uint256 value) internal {
        (bool success, ) = to.call{gas: 23000, value: value}("");
        require(success, 'BNB_TRANSFER_FAILED');
    }

    function tokenAddr() public override view returns (address){
        return WBNB;
    }
}
