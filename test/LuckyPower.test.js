const { expectRevert, time } = require('@openzeppelin/test-helpers');
const { AddressZero } = require("@ethersproject/constants");
const { assert } = require('chai');
const { ethers } = require('ethers');

const BetMining = artifacts.require('BetMining');
const LuckyChipFactory = artifacts.require('LuckyChipFactory');
const LuckyChipRouter02 = artifacts.require('LuckyChipRouter02');
const WBNB = artifacts.require('WBNB');
const LCToken = artifacts.require('LCToken');
const Oracle = artifacts.require('Oracle');
const Referral = artifacts.require('Referral');
const DiceToken = artifacts.require('DiceToken');
const Dice = artifacts.require('Dice');

contract('LuckyPower', ([alice, bob, referrer, treasury, dev2, lotteryAdmin, lcAdmin, creater, swapFeeTo, lucky0, ]) => {
    beforeEach(async () => {
        // factory
        this.factory = await LuckyChipFactory.new(creater, { from: creater });
        console.log(`init_code_hash,${await this.factory.INIT_CODE_HASH()}`);
        await this.factory.setFeeTo(swapFeeTo, {from: creater});
        console.log(`feeTo,${await this.factory.feeTo()}`);

        // WBNB
        this.WBNB = await WBNB.new({from: creater});
        await this.WBNB.deposit({from: creater, value: ethers.utils.parseEther("10")});

        // LC
        this.lc = await LCToken.new({ from: creater });
        await this.lc.addMinter(creater, {from: creater});
        await this.lc.mint(creater, ethers.utils.parseEther("1000000"), { from: creater });
        console.log(`lc,${this.lc.address}`);

        // Router
        this.router = await LuckyChipRouter02.new(
            this.factory.address, 
            this.WBNB.address, 
            {from: creater});
        await this.WBNB.approve(this.router.address, ethers.constants.MaxUint256, {from: creater});
        await this.lc.approve(this.router.address, ethers.constants.MaxUint256, {from: creater});
        console.log(`WBNB balance,${await this.WBNB.balanceOf(creater)}`);
        console.log(`lc balance,${await this.lc.balanceOf(creater)}`);
        await this.router.addLiquidityETH(
            this.lc.address, 
            ethers.utils.parseEther('6000'), 
            ethers.utils.parseEther('4800'), 
            ethers.utils.parseEther('0.8'), 
            creater,
            ethers.constants.MaxUint256,
            {value: ethers.utils.parseEther('1'), from: creater}
        );
        console.log(`WBNB balance,${await this.WBNB.balanceOf(creater)}`);
        console.log(`lc balance,${await this.lc.balanceOf(creater)}`);

        // oracle
        this.oracle = await Oracle.new(this.factory.address, this.lc.address, { from: creater});

        // referral
        this.referral = await Referral.new(this.lc.address, {from: creater});
        
		// lottery
		this.lottery = await Lottery.new(this.lc.address, {from: creater});
        await this.lottery.injectFirstPrize([lucky0], ethers.utils.parseEther('12'), {from: creater});

        // betMining
        this.betMining = await BetMining.new(this.lc.address, this.oracle.address, treasury, ethers.utils.parseEther('950'), '100', { from: creater });
        await this.lc.addMinter(this.betMining.address, { from: creater });
        await this.referral.addOperator(this.betMining.address, {from: creater});
        await this.betMining.setReferral(this.referral.address, {from: creater});
        
        console.log(`rewardTokenPerBlock,${await this.betMining.rewardTokenPerBlock()}`);
		await this.betMining.add('700', this.lc.address, { from: creater });
		await this.betMining.add('250', this.WBNB.address, { from: creater });

		// masterChef
		

		// Dice
		this.diceToken = await DiceToken.new('LuckyChipDice', 'LuckyChipDice', {from: creater});
		this.dice = await Dice.new(
			this.lc.address, 
			this.lc.address, 
			this.diceToken.address, 
			AddressZero,
			dev2,
			lotteryAdmin,
			20,
			500,
			600,
			ethers.utils.parseEther('0.001'),
			ethers.utils.parseEther('0.001'),
			ethers.utils.parseEther('300000000'),
			{from: creater});
		await this.lc.addMinter(this.dice.address, {from: creater});
		await this.diceToken.transferOwnership(this.dice.address, {from: creater});
		await this.dice.setAdmin(lcAdmin, dev2, lotteryAdmin, {from: creater});
		await this.dice.setBetMining(this.betMining.address, { from: lcAdmin});
		await this.betMining.addBetTable(this.dice.address, {from: creater});
    });
    it('real case', async () => {
        await this.lc.approve(this.dice.address, ethers.constants.MaxUint256, {from: creater});
		await this.diceToken.approve(this.dice.address, ethers.constants.MaxUint256, {from: creater});

		await time.advanceBlockTo('150');
		await this.dice.deposit(ethers.utils.parseEther("100000"), {from: creater});

		await this.lc.mint(alice, ethers.utils.parseEther("50"), {from: creater});
		await this.lc.approve(this.dice.address, ethers.constants.MaxUint256, {from: alice});
		await this.lc.mint(bob, ethers.utils.parseEther("300"), {from: creater});
		await this.lc.approve(this.dice.address, ethers.constants.MaxUint256, {from: bob});

		let randomNumber = ethers.utils.hexlify(ethers.utils.randomBytes(32));
		let bankHash = ethers.utils.keccak256(randomNumber);
		console.log(randomNumber, bankHash);
		//await expectRevert(this.dice.endBankerTime(1, bankHash, {from: creater}), 'not admin');
		await this.dice.endBankerTime(1, bankHash, {from: lcAdmin});

		let round = await this.dice.rounds(1);
		console.log(`round1`);
		for(var i = 0; i < 13; i ++){
			console.log(`${round[i]}`);
		}
		console.log(`round1 end`);

		console.log('alice balance: ', (await this.lc.balanceOf(alice)).toString());		
		console.log('bob balance: ', (await this.lc.balanceOf(bob)).toString());
		await this.dice.betNumber([false, false, false, false, false, true], ethers.utils.parseEther("50"), referrer, {value: ethers.utils.parseEther("0.001"), from: alice});
		await this.dice.betNumber([true,true,true,true,true,true], ethers.utils.parseEther("300"), referrer, {value: ethers.utils.parseEther("0.001"), from: bob});
		console.log('alice balance: ', (await this.lc.balanceOf(alice)).toString());		
		console.log('bob balance: ', (await this.lc.balanceOf(bob)).toString());

		lockBlock = round[1];
		console.log(`Current block: ${(await time.latestBlock())},${lockBlock}`);
        
        let reward = await this.dice.pendingReward(alice, {from: alice});
		console.log(`reward: ${reward[0]},${reward[1]},${reward[2]}`);
		assert.equal(reward[0].toString(), '0');
		await time.advanceBlockTo(lockBlock);
		let newRandomNumber = ethers.utils.hexlify(ethers.utils.randomBytes(32));
		let newBankHash = ethers.utils.keccak256(newRandomNumber);
		console.log(newRandomNumber, newBankHash);
		await this.dice.executeRound(1, newBankHash, {from: lcAdmin});
		await this.dice.sendSecret(1, randomNumber, {from: lcAdmin});

		round = await this.dice.rounds(1);
		for(var i = 0; i < 13; i ++){
			console.log(`${round[i]}`);
		}
		console.log(`finalNumber,${round[11]}`);

		betInfo = await this.dice.ledger(1, alice, {from: alice});
		console.log(`${betInfo[0]},${betInfo[1]},${betInfo[2]},${betInfo[3]},${betInfo[4]}`)
		betInfo = await this.dice.ledger(1, bob, {from: alice});
		console.log(`${betInfo[0]},${betInfo[1]},${betInfo[2]},${betInfo[3]},${betInfo[4]}`)

		reward = await this.dice.pendingReward(alice, {from: alice});
		if(reward[0] > 0){
			await this.dice.claimReward({from: alice});
			console.log(`claim for alice,${reward[0]},${reward[1]},${reward[2]}`);
		}else{
			console.log('no reward for alice');
        }

		round = await this.dice.rounds(2);
        for(var i = 0; i < 13; i ++){
            console.log(`${round[i]}`);
        }

        lockBlock = round[1];
        await time.advanceBlockTo(lockBlock);
        await this.dice.endPlayerTime(2, newRandomNumber, {from: lcAdmin});

		reward = await this.dice.pendingReward(bob, {from: bob});
		//assert.equal((reward[0]).toString(), '23000');
		await this.dice.claimReward({from: bob});
		console.log('alice balance: ', (await this.lc.balanceOf(alice)).toString());		
		console.log('bob balance: ', (await this.lc.balanceOf(bob)).toString());		
		console.log('bankerAmount',(await this.dice.bankerAmount()).toString());
		balance = await this.diceToken.balanceOf(creater);
		await this.dice.withdraw(balance, {from: creater});
		console.log('bankerAmount',(await this.dice.bankerAmount()).toString());

		await this.betMining.withdraw(0, { from: alice });
		user = await this.betMining.userInfo(0, alice, {from: alice});
		console.log(`userInfo,${user[0]},${user[1]},${user[2]},${user[3]},${user[4]}`);
        result = await this.betMining.poolInfo(0);
        console.log(`poolInfo,${result[0]},${result[1]},${result[2]},${result[3]},${result[4]},${result[5]},${result[6]},${result[7]}`);
        let aliceBalance = await this.lc.balanceOf(alice);
        console.log('alice balance: ', aliceBalance.toString());
		console.log(`Current block: ${(await time.latestBlock())}`);

        result = await this.referral.getReferralCommission.call(referrer);
        console.log(`commission,${result[0]},${result[1]},${result[2]},${result[3]},${result[4]},${result[5]}`);
        assert.equal((await this.lc.balanceOf(referrer)).toString(), '0');
        await this.referral.claimBetCommission({from: referrer});
        console.log(`referrer lcBalance,${await this.lc.balanceOf(referrer)}`);
        //assert.equal((await this.lc.balanceOf(referrer)).toString(), '1750');

    })
});
