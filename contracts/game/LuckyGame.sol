// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IBEP20.sol";
import "../interfaces/IGame.sol";
import "../interfaces/IRouter.sol";
import "../libraries/SafeBEP20.sol";
import "../token/GameToken.sol";
import "../token/LCToken.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/ILuckyPower.sol";
import "../interfaces/IGameRng.sol";

contract LuckyGame is IGame, Ownable, ReentrancyGuard, Pausable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Modulo is the number of equiprobable outcomes in a game:
    //  2 for coin flip
    //  6 for dice roll
    //  36 for double dice roll
    //  37 for roulette
    //  100 for polyroll
    uint256 constant MAX_MODULO = 100;

    // Modulos below MAX_MASK_MODULO are checked against a bit mask, allowing betting on specific outcomes. 
    // For example in a dice roll (modolo = 6), 
    // 000001 mask means betting on 1. 000001 converted from binary to decimal becomes 1.
    // 101000 mask means betting on 4 and 6. 101000 converted from binary to decimal becomes 40.
    // The specific value is dictated by the fact that 256-bit intermediate
    // multiplication result allows implementing population count efficiently
    // for numbers that are up to 42 bits, and 40 is the highest multiple of eight below 42.
    uint256 constant MAX_MASK_MODULO = 40;

     // This is a check on bet mask overflow. Maximum mask is equivalent to number of possible binary outcomes for maximum modulo.
    uint256 constant MAX_BET_MASK = 2 ** MAX_MASK_MODULO;

    // These are constants that make O(1) population count in placeBet possible.
    uint256 constant POPCNT_MULT = 0x0000000000002000000000100000000008000000000400000000020000000001;
    uint256 constant POPCNT_MASK = 0x0001041041041041041041041041041041041041041041041041041041041041;
    uint256 constant POPCNT_MODULO = 0x3F;

    uint256 public prevBankerAmount; // previous banker amount
    uint256 public bankerAmount; // current banker amount
    uint256 public netValue; // net value
    uint256 public playerEndBlock;
    uint256 public bankerEndBlock;
    uint256 public betAmount;
    uint256 public playerTimeBlocks;
    uint256 public bankerTimeBlocks;
    uint256 public constant TOTAL_RATE = 10000; // 100%
    uint256 public gapRate = 300;// Gap rate, default 3%
    uint256 public operationRate = 500; // 5% in gap
    uint256 public treasuryRate = 500; // 5% in gap
    uint256 public bonusRate = 2000; // 20% in gap
    uint256 public lotteryRate = 500; // 5% in gap
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
    IBEP20 public token;
    IBEP20 public lcToken;
    GameToken public gameToken;
    IGameRng public gameRng;

    // Info of each bet.
    struct Bet {
        // Address of a gambler, used to pay out winning bets.
        address gambler;
        // Block number of placeBet
        uint256 blockNumber;
        // Wager amount in wei.
        uint256 amount;
        // Outcome of bet
        uint256 outcome;
        // Win amount.
        uint256 winAmount;
        // Bit mask representing winning bet outcomes (see MAX_MASK_MODULO comment).
        uint40 mask;
        // Modulo of a game.
        uint8 modulo;
        // Number of winning outcomes, used to compute winning payment (* modulo/rollUnder),
        // and used instead of mask for games with modulo > MAX_MASK_MODULO.
        uint8 rollUnder;
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
    event SetRates(uint256 gapRate, uint256 operationRate, uint256 treasuryRate, uint256 bonusRate, uint256 lotteryRate);
    event SetAmounts(uint256 maxBankerAmount, uint256 minBetAmount, uint256 offChainFeeAmount, uint256 onChainFeeAmount);
    event SetRatios(uint256 maxWithdrawFeeRatio, uint256 maxBetRatio);
    event SetContract(address lcTokenAddr, address oracleAddr, address luckyPowerAddr, address flipRngAddr);
    event EndPlayerTime();
    event EndBankerTime();
    event UpdateNetValue(uint256 netValue);
    event Deposit(address indexed user, uint256 tokenAmount);
    event Withdraw(address indexed user, uint256 gameTokenAmount);

    event BetPlaced(uint256 indexed betId, address indexed gambler, uint256 amount, uint8 indexed modulo, uint8 rollUnder, uint40 mask, bool rngOnChain);
    event SwapBetPlaced(uint256 indexed betId, address indexed gambler, address tokenAddr, uint256 tokenAmount, uint256 amount, uint8 indexed modulo, uint8 rollUnder, uint40 mask, bool rngOnChain);
    event BetSettled(uint256 indexed betId, address indexed gambler, uint256 amount, uint8 indexed modulo, uint8 rollUnder, uint40 mask, uint256 outcome, uint256 winAmount);
    event BetRefunded(uint256 indexed betId, address indexed gambler, uint256 amount);

    constructor(
        address _tokenAddr,
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
        token = IBEP20(_tokenAddr);
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
    function setRates(uint256 _gapRate, uint256 _operationRate, uint256 _treasuryRate, uint256 _bonusRate, uint256 _lotteryRate) external onlyOwner {
        require(_gapRate <= 1000 && _operationRate.add(_treasuryRate).add(_bonusRate).add(_lotteryRate) <= TOTAL_RATE, "rate limit");
        gapRate = _gapRate;
        operationRate = _operationRate;
        treasuryRate = _treasuryRate;
        bonusRate = _bonusRate;
        lotteryRate = _lotteryRate;
        emit SetRates(_gapRate, operationRate, treasuryRate, bonusRate, lotteryRate);
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
    function endPlayerTime() external onlyOwner whenNotPaused{
        _pause();
        netValue = netValue.mul(bankerAmount).div(prevBankerAmount);
        emit UpdateNetValue(netValue);
        _claimBonusAndLottery();
        emit EndPlayerTime();
    }

    // Claim all bonus to LuckyPower
    function _claimBonusAndLottery() internal {
        if(betAmount > 0){
            uint256 gapAmount = betAmount.mul(gapRate).div(TOTAL_RATE);
            uint256 totalOperationAmount = 0;

            uint256 treasuryAmount = gapAmount.mul(treasuryRate).div(TOTAL_RATE);
            if(treasuryAmount > 0){
                if(address(token) == address(lcToken)){
                    lcToken.safeTransfer(treasuryAddr, treasuryAmount);
                }
                else if(defaultSwapRouterId < swapRouters.length && swapRouters[defaultSwapRouterId] != address(0)){
                    IRouter swapRouter = IRouter(swapRouters[defaultSwapRouterId]);
                    address[] memory path = new address[](2);
                    path[0] = address(token);
                    path[1] = address(lcToken);
                    uint256 amountOut = swapRouter.getAmountsOut(treasuryAmount, path)[1];
                    token.safeApprove(address(swapRouter), treasuryAmount);
                    uint256 lcAmount = swapRouter.swapExactTokensForTokens(treasuryAmount, amountOut.mul(995).div(1000), path, address(this), block.timestamp + (5 minutes))[1];
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

            betAmount = 0;
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

    // Returns the expected win amount.
    function getWinAmount(uint256 amount, uint256 modulo, uint256 rollUnder) private view returns (uint256 winAmount) {
        require(0 < rollUnder && rollUnder <= modulo, "Win probability out of range");
        uint256 houseEdgeFee = amount.mul(gapRate).div(TOTAL_RATE);
        winAmount = amount.sub(houseEdgeFee).mul(modulo).div(rollUnder);
    }

    // Place bet
    function placeBet(uint256 amount, uint256 betMask, uint256 modulo, bool rngOnChain) external payable whenNotPaused nonReentrant notContract {
        require(modulo > 1 && modulo <= MAX_MODULO && betMask > 0 && betMask < MAX_BET_MASK, "Para error");

        // Validate input data.
        token.safeTransferFrom(address(msg.sender), address(this), amount);
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

        uint256 rollUnder;
        uint256 mask;

        if (modulo <= MAX_MASK_MODULO) {
            // Small modulo games can specify exact bet outcomes via bit mask.
            // rollUnder is a number of 1 bits in this mask (population count).
            // This magic looking formula is an efficient way to compute population
            // count on EVM for numbers below 2**40. 
            rollUnder = ((betMask * POPCNT_MULT) & POPCNT_MASK) % POPCNT_MODULO;
            mask = betMask;
        } else {
            // Larger modulos games specify the right edge of half-open interval of winning bet outcomes.
            require(betMask > 0 && betMask <= modulo, "betMask larger than modulo");
            rollUnder = betMask;
        }

        require(amount >= minBetAmount && amount <= bankerAmount.mul(maxBetRatio).div(TOTAL_RATE).mul(rollUnder).div(modulo), "Range limit");

        uint256 requestId;
        if(rngOnChain){
            requestId = gameRng.getRandomNumberOnChain(bets.length);
        }else{
            requestId = gameRng.getRandomNumberOffChain(bets.length);
        }

        betMap[requestId] = bets.length;
        userBets[msg.sender].push(bets.length);

        // Record bet in event logs. Placed before pushing bet to array in order to get the correct bets.length.
        emit BetPlaced(bets.length, msg.sender, amount, uint8(modulo), uint8(rollUnder), uint40(mask), rngOnChain);

        // Store bet in bet list.
        bets.push(Bet(
            {
                gambler: msg.sender,
                blockNumber: block.number,
                amount: amount,
                outcome: 0,
                winAmount: 0,
                mask: uint40(mask),
                modulo: uint8(modulo),
                rollUnder: uint8(rollUnder),
                isSettled: false
            }
        ));

    }

    // swap and place bet
    function swapAndBet(address tokenAddr, uint256 tokenAmount, uint256 swapRounterId, uint256 slippage, uint256 betMask, uint256 modulo, bool rngOnChain) external payable whenNotPaused nonReentrant notContract {
        require(modulo > 1 && modulo <= MAX_MODULO && betMask > 0 && betMask < MAX_BET_MASK && swapRounterId < swapRouters.length, "Para error");
        
        uint256 amount;
        {
            IBEP20(tokenAddr).safeTransferFrom(address(msg.sender), address(this), tokenAmount);
            address[] memory path = new address[](2);
            path[0] = tokenAddr;
            path[1] = address(token);
            IRouter swapRouter = IRouter(swapRouters[swapRounterId]);
            uint256 amountOut = swapRouter.getAmountsOut(tokenAmount, path)[1];
            IBEP20(tokenAddr).safeApprove(address(swapRouter), tokenAmount);
            amount = swapRouter.swapExactTokensForTokens(tokenAmount, amountOut.mul(TOTAL_RATE).div(TOTAL_RATE.add(slippage)), path, address(this), block.timestamp + (5 minutes))[1];
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

        uint256 rollUnder;
        uint256 mask;

        if (modulo <= MAX_MASK_MODULO) {
            // Small modulo games can specify exact bet outcomes via bit mask.
            // rollUnder is a number of 1 bits in this mask (population count).
            // This magic looking formula is an efficient way to compute population
            // count on EVM for numbers below 2**40. 
            rollUnder = ((betMask * POPCNT_MULT) & POPCNT_MASK) % POPCNT_MODULO;
            mask = betMask;
        } else {
            // Larger modulos games specify the right edge of half-open interval of winning bet outcomes.
            require(betMask > 0 && betMask <= modulo, "betMask larger than modulo");
            rollUnder = betMask;
        }

        require(amount >= minBetAmount && amount <= bankerAmount.mul(maxBetRatio).div(TOTAL_RATE).mul(rollUnder).div(modulo), "Range limit");

        uint256 requestId;
        if(rngOnChain){
            requestId = gameRng.getRandomNumberOnChain(bets.length);
        }else{
            requestId = gameRng.getRandomNumberOffChain(bets.length);
        }

        betMap[requestId] = bets.length;
        userBets[msg.sender].push(bets.length);

        // Record bet in event logs. Placed before pushing bet to array in order to get the correct bets.length.
        emit SwapBetPlaced(bets.length, msg.sender, tokenAddr, tokenAmount, amount, uint8(modulo), uint8(rollUnder), uint40(mask), rngOnChain);

        // Store bet in bet list.
        bets.push(Bet(
            {
                gambler: msg.sender,
                blockNumber: block.number,
                amount: amount,
                outcome: 0,
                winAmount: 0,
                mask: uint40(mask),
                modulo: uint8(modulo),
                rollUnder: uint8(rollUnder),
                isSettled: false
            }
        ));
    }

    // Settle bet. Function can only be called by fulfillRandomness function, which in turn can only be called by Chainlink VRF.
    function settleBet(uint256 requestId, uint256 randomNumber) external override nonReentrant {
        require(msg.sender == address(gameRng), "Only gameRng");

        uint256 betId = betMap[requestId];
        Bet storage bet = bets[betId];
        uint256 amount = bet.amount;

        if(amount > 0 && bet.isSettled == false){
            uint256 modulo = bet.modulo;
            uint256 rollUnder = bet.rollUnder;

            // Do a roll by taking a modulo of random number.
            uint256 outcome = randomNumber % modulo;

            // Win amount if gambler wins this bet
            uint256 possibleWinAmount = getWinAmount(amount, modulo, rollUnder);

            // Actual win amount by gambler.
            uint256 winAmount = 0;

            // Determine dice outcome.
            if (modulo <= MAX_MASK_MODULO) {
                // For small modulo games, check the outcome against a bit mask.
                if ((2 ** outcome) & bet.mask != 0) {
                    winAmount = possibleWinAmount;
                }
            } else {
                // For larger modulos, check inclusion into half-open interval.
                if (outcome < rollUnder) {
                    winAmount = possibleWinAmount;
                }
            }

            uint256 tmpBankerAmount = bankerAmount;
            tmpBankerAmount = tmpBankerAmount.add(amount);
            if(winAmount > 0){
                tmpBankerAmount = tmpBankerAmount.sub(winAmount);
                token.safeTransfer(bet.gambler, winAmount);
            }

            betAmount = betAmount.add(amount);

            uint256 gapAmount = amount.mul(gapRate).div(TOTAL_RATE);
            tmpBankerAmount = tmpBankerAmount.sub(gapAmount.mul(operationRate.add(treasuryRate).add(bonusRate).add(lotteryRate)).div(TOTAL_RATE));

            bankerAmount = tmpBankerAmount;
            bet.outcome = outcome;
            bet.winAmount = winAmount;
            bet.isSettled = true;
            
            // Record bet settlement in event log.
            emit BetSettled(betId, bet.gambler, amount, uint8(modulo), uint8(rollUnder), bet.mask, outcome, winAmount);
        }
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
        emit BetRefunded(betId, bet.gambler, amount);
    }

    // Deposit token to Dice as a banker, get Syrup back.
    function deposit(uint256 _tokenAmount) public whenPaused nonReentrant notContract {
        require(_tokenAmount > 0 && bankerAmount.add(_tokenAmount) < maxBankerAmount, 'Amount Limit');
        uint256 prevGameTokenAmount = bankerInfo[msg.sender];
        token.safeTransferFrom(address(msg.sender), address(this), _tokenAmount);
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
            uint256 bankerTvl = oracle.getQuantity(address(token), tokenAmount);
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
        return address(token);
    }
}
