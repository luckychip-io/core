const { expectRevert, time } = require('@openzeppelin/test-helpers');
const { assert } = require('chai');
const { AddressZero } = require("@ethersproject/constants")

const BetMining = artifacts.require('BetMining');
const LuckyChipFactory = artifacts.require('LuckyChipFactory');
const LuckyChipRouter02 = artifacts.require('LuckyChipRouter02');
const WBNB = artifacts.require('WBNB');
const LCToken = artifacts.require('LCToken');
const Oracle = artifacts.require('Oracle');
const Referral = artifacts.require('Referral');

let perBlock = '950';

contract('BetMining', ([alice, bob, carol, treasury, creater, swapFeeTo]) => {
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
        
        // betMining
        this.betMining = await BetMining.new(this.lc.address, this.oracle.address, treasury, perBlock, '100', { from: creater });
        await this.lc.addMinter(this.betMining.address, { from: creater });
        await this.referral.addOperator(this.betMining.address, {from: creater});
        await this.betMining.setReferral(this.referral.address, {from: creater});

        await this.WBNB.approve(this.betMining.address, ethers.constants.MaxUint256, { from: alice });
        await this.lc.approve(this.betMining.address, ethers.constants.MaxUint256, { from: alice });
        await this.betMining.addBetTable(creater, {from: creater});
        console.log(`rewardTokenPerBlock,${await this.betMining.rewardTokenPerBlock()}`);
    });
    it('real case', async () => {
        await this.betMining.add('700', this.lc.address, { from: creater });
		assert.equal((await this.betMining.getPoolLength.call()).toString(), "1");
		assert.equal((await this.betMining.totalAllocPoint()).toString(), "700");
        await this.betMining.add('250', this.WBNB.address, { from: creater });
        assert.equal((await this.betMining.getPoolLength.call()).toString(), "2");
		assert.equal((await this.betMining.totalAllocPoint()).toString(), "950");
		console.log(`startBlock: ${(await this.betMining.startBlock())}`);
        result = await this.betMining.poolInfo(0);
        console.log(`poolInfo,${result[0]},${result[1]},${result[2]},${result[3]},${result[4]},${result[5]},${result[6]},${result[7]}`);
        result = await this.betMining.getMultiplier.call(150, 170, { from: creater});
        console.log(`multiplier,${result}`);

        //1 - lp
        console.log('----Deposit----');
		assert.equal((await this.lc.balanceOf(alice)).toString(), '0');
        await time.advanceBlockTo('150');
		console.log(`Current block: ${(await time.latestBlock())}`);
        await this.betMining.bet(alice, bob, this.lc.address, '20', { from: creater });
        result = await this.betMining.poolInfo(0);
        console.log(`poolInfo,${result[0]},${result[1]},${result[2]},${result[3]},${result[4]},${result[5]},${result[6]},${result[7]}`);

        assert.equal(await this.referral.getReferrer.call(alice), bob);
		let user = await this.betMining.userInfo(0, alice, {from: alice});
		console.log(`userInfo,${user[0]},${user[1]},${user[2]},${user[3]},${user[4]}`);
		console.log((await this.betMining.pendingRewards(0, alice)).toString());
        await time.advanceBlockTo('170');
		console.log((await this.betMining.pendingRewards(0, alice)).toString());
        console.log('---Withdraw---');
		console.log((await this.betMining.pendingRewards(0, alice)).toString());
		console.log(`Current block: ${(await time.latestBlock())}`);
        await time.advanceBlockTo('200'); 
        await this.betMining.withdraw(0, { from: alice });
		user = await this.betMining.userInfo(0, alice, {from: alice});
		console.log(`userInfo,${user[0]},${user[1]},${user[2]},${user[3]},${user[4]}`);
        result = await this.betMining.poolInfo(0);
        console.log(`poolInfo,${result[0]},${result[1]},${result[2]},${result[3]},${result[4]},${result[5]},${result[6]},${result[7]}`);
        let aliceBalance = await this.lc.balanceOf(alice);
        console.log('alice balance: ', aliceBalance.toString());
		console.log(`Current block: ${(await time.latestBlock())}`);

        console.log('---------------');

        await time.advanceBlockTo('210'); 

        result = await this.referral.getReferralCommission.call(bob);
        console.log(`commission,${result[0]},${result[1]},${result[2]},${result[3]},${result[4]},${result[5]}`);
        assert.equal((await this.lc.balanceOf(bob)).toString(), '0');
        await this.referral.claimBetCommission({from: bob});
        console.log(`bob lcBalance,${await this.lc.balanceOf(bob)}`);
        assert.equal((await this.lc.balanceOf(bob)).toString(), '1750');
    })
});
