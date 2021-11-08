const { expectRevert, time } = require('@openzeppelin/test-helpers');
const { AddressZero } = require("@ethersproject/constants")
const { assert } = require('chai');
const ethers = require('ethers');
const DiceToken = artifacts.require('DiceToken');
const LCToken = artifacts.require('LCToken');
const Dice = artifacts.require('Dice');
const MockBEP20 = artifacts.require('libs/MockBEP20');
const MasterChef = artifacts.require('MasterChef');

contract('Dice', ([alice, bob, carol, david, admin, lcAdmin, dev0, dev1, dev2, safuAddr, treasuryAddr, minter]) => {
    beforeEach(async () => {
		this.token = await MockBEP20.new('Wrapped BNB', 'WBNB', '300000000', { from: minter });
		await this.token.transfer(alice, '30000000', {from: minter});
		await this.token.transfer(bob, '30000000', {from: minter});
		await this.token.transfer(carol, '30000000', {from: minter});
		await this.token.transfer(david, '30000000', {from: minter});

        this.lc = await LCToken.new({ from: minter});
		this.chef = await MasterChef.new(this.lc.address, dev0, dev1, dev2, safuAddr, treasuryAddr, '1000', '100', '900000','32400', '24300', '24300', '10000', { from: minter });	
        await this.lc.transferOwnership(this.chef.address, { from: minter });

        this.diceToken = await DiceToken.new('LuckyWBNB', 'LuckyWBNB', { from: minter }); 
        this.dice = await Dice.new(this.token.address, this.lc.address, this.diceToken.address, this.chef.address, 0, 20, 500, 600, 1, 1, 30000000, { from: minter });
        await this.diceToken.transferOwnership(this.dice.address, { from: minter});

		this.lp1 = await MockBEP20.new('LPToken', 'LP1', '10000000', { from: minter });
		await this.lp1.transfer(carol, '100000', {from:minter});
		await this.lp1.transfer(david, '100000', {from:minter});
		await this.chef.add('1000', '90', this.lp1.address, { from: minter });
		await this.chef.addBonus(this.token.address, { from: minter });
		await this.lp1.approve(this.chef.address, '100000', {from:carol});
		await this.lp1.approve(this.chef.address, '100000', {from:david});
    
    });
    it('real case', async () => {
		await this.dice.setAdmin(admin, lcAdmin, dev2, {from: minter});

		await this.token.approve(this.dice.address, '30000000', { from: alice });
		await this.token.approve(this.dice.address, '30000000', { from: bob });
		await this.token.approve(this.dice.address, '30000000', { from: carol });
		await this.token.approve(this.dice.address, '30000000', { from: david });
		await this.chef.deposit(0, '100', AddressZero, {from:carol});
		await this.chef.deposit(0, '200', AddressZero, {from:david});
		await this.diceToken.approve(this.dice.address, '10000000', { from: carol });
		await this.diceToken.approve(this.dice.address, '10000000', { from: david });
		await this.dice.deposit(6000000, {from: carol});
		await this.dice.deposit(12000000, {from: david});
		await expectRevert(this.dice.deposit(15000000, {from: david}), 'maxBankerAmount Limit');

		assert.equal((await this.dice.bankerAmount()).toString(), '18000000');
		//assert.equal((await this.dice.canWithdrawToken(carol)).toString(), '6000000');

		let randomNumber = ethers.utils.hexlify(ethers.utils.randomBytes(32));
		let bankHash = ethers.utils.keccak256(randomNumber);
		console.log(randomNumber, bankHash);
		await expectRevert(this.dice.endBankerTime(1, bankHash, {from: minter}), 'not admin');
		await this.dice.endBankerTime(1, bankHash, {from: admin});

		console.log('alice balance: ', (await this.token.balanceOf(alice)).toString());		
		console.log('bob balance: ', (await this.token.balanceOf(bob)).toString());		
		await this.dice.betNumber([false,false,true,false,false,false], 4000, {from:alice, value:1});
		await this.dice.betNumber([true,true,true,true,true,true], 24000, {from:bob, value:1});
		console.log('alice balance: ', (await this.token.balanceOf(alice)).toString());		
		console.log('bob balance: ', (await this.token.balanceOf(bob)).toString());		

		let round = await this.dice.rounds(1);
		for(var i = 0; i < 13; i ++){
			console.log(`${round[i]}`);
		}

		lockBlock = round[1];
		console.log(`Current block: ${(await time.latestBlock())},${lockBlock}`);
        
        let reward = await this.dice.pendingReward(alice, {from: alice});
		console.log(`reward: ${reward[0]},${reward[1]},${reward[2]}`);
		assert.equal(reward[0].toString(), '0');
		await time.advanceBlockTo(lockBlock);
		let newRandomNumber = ethers.utils.hexlify(ethers.utils.randomBytes(32));
		let newBankHash = ethers.utils.keccak256(newRandomNumber);
		console.log(newRandomNumber, newBankHash);
		await this.dice.executeRound(1, newBankHash, {from: admin});
		await this.dice.sendSecret(1, randomNumber, {from: admin});

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

		reward = await this.dice.pendingReward(bob, {from: bob});
		assert.equal((reward[0]).toString(), '23000');
		await this.dice.claimReward({from: bob});
		console.log('alice balance: ', (await this.token.balanceOf(alice)).toString());		
		console.log('bob balance: ', (await this.token.balanceOf(bob)).toString());		
		console.log('bankerAmount',(await this.dice.bankerAmount()).toString());
        console.log('admin balance',(await this.token.balanceOf(admin)).toString());
        console.log('lcAdmin balance',(await this.token.balanceOf(lcAdmin)).toString());

		await expectRevert(this.dice.deposit(200000, {from: alice}), 'Pausable: not paused');
		await expectRevert(this.dice.withdraw(200000, {from: alice}), 'Pausable: not paused');

		await this.dice.betNumber([false,false,true,false,false,true], 8000, {from:alice, value:1});
        await this.dice.betNumber([true,true,true,false,false,false], 12000, {from:bob, value:1});
        console.log('alice balance: ', (await this.token.balanceOf(alice)).toString());
        console.log('bob balance: ', (await this.token.balanceOf(bob)).toString());
		
		round = await this.dice.rounds(2);
		for(var i = 0; i < 13; i ++){
			console.log(`${round[i]}`);
		}

		lockBlock = round[1];
		await time.advanceBlockTo(lockBlock);
		await this.dice.endPlayerTime(2, newRandomNumber, {from: admin});

		round = await this.dice.rounds(2);
		for(var i = 0; i < 13; i ++){
			console.log(`${round[i]}`);
		}
		console.log(`finalNumber,${round[11]}`);

		reward = await this.dice.pendingReward(alice, {from: alice});
		if(reward[0] > 0){
			await this.dice.claimReward({from: alice});
			console.log(`claim for alice,${reward[0]},${reward[1]},${reward[2]}`);
		}else{
			console.log('no reward for alice');
        }

		reward = await this.dice.pendingReward(bob, {from: bob});
		if(reward[0] > 0){
			await this.dice.claimReward({from: bob});
			console.log(`claim for bob,${reward[0]},${reward[1]},${reward[2]}`);
		}else{
			console.log('no reward for bob');
        }

        console.log('alice balance: ', (await this.token.balanceOf(alice)).toString());
        console.log('bob balance: ', (await this.token.balanceOf(bob)).toString());
        console.log('bankerAmount',(await this.dice.bankerAmount()).toString());
        console.log('admin balance',(await this.token.balanceOf(admin)).toString());
        console.log('lcAdmin balance',(await this.token.balanceOf(lcAdmin)).toString());

		round = await this.dice.rounds(2);
		for(var i = 0; i < 13; i ++){
			console.log(`${round[i]}`);
		}

        console.log('netValue ', (await this.dice.netValue()).toString());
        console.log('carol diceToken balance: ', (await this.diceToken.balanceOf(carol)).toString());
        console.log('david diceToken balance: ', (await this.diceToken.balanceOf(david)).toString());
        console.log('carol balance: ', (await this.token.balanceOf(carol)).toString());
        console.log('david balance: ', (await this.token.balanceOf(david)).toString());
		
		await this.dice.withdraw(200000, {from: carol});
		await this.dice.withdraw(400000, {from: david});
        console.log('carol diceToken balance: ', (await this.diceToken.balanceOf(carol)).toString());
        console.log('david diceToken balance: ', (await this.diceToken.balanceOf(david)).toString());
        console.log('carol token balance: ', (await this.token.balanceOf(carol)).toString());
        console.log('david token balance: ', (await this.token.balanceOf(david)).toString());
        console.log('carol lp1 balance: ', (await this.lp1.balanceOf(carol)).toString());
        console.log('david lp1 balance: ', (await this.lp1.balanceOf(david)).toString());
        console.log('chef token balance: ', (await this.token.balanceOf(this.chef.address)).toString());
		await this.chef.withdraw(0, 100, {from: carol});
		await this.chef.withdraw(0, 200, {from: david});
        console.log('chef token balance: ', (await this.token.balanceOf(this.chef.address)).toString());
        console.log('carol lp1 balance: ', (await this.lp1.balanceOf(carol)).toString());
        console.log('david lp1 balance: ', (await this.lp1.balanceOf(david)).toString());
        console.log('carol token balance: ', (await this.token.balanceOf(carol)).toString());
        console.log('david token balance: ', (await this.token.balanceOf(david)).toString());

    });
});
