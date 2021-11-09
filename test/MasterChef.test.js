const { expectRevert, time } = require('@openzeppelin/test-helpers');
const { assert } = require('chai');
const { AddressZero } = require("@ethersproject/constants")

const LCToken = artifacts.require('LCToken');
const MasterChef = artifacts.require('MasterChef');
const MockBEP20 = artifacts.require('libs/MockBEP20');
const Referral = artifacts.require('Referral');

let perBlock = '1000';

contract('MasterChef', ([alice, bob, carol, dev0, dev1, dev2, ecoAddr, treasuryAddr, creater]) => {
    beforeEach(async () => {
        this.lc = await LCToken.new({ from: creater });
    
        this.lp1 = await MockBEP20.new('LPToken', 'LP1', '1000000', { from: creater });
        this.lp2 = await MockBEP20.new('LPToken', 'LP2', '1000000', { from: creater });
        this.lp3 = await MockBEP20.new('LPToken', 'LP3', '1000000', { from: creater });
        
        this.chef = await MasterChef.new(this.lc.address, dev0, dev1, dev2, ecoAddr, treasuryAddr, perBlock, '100', '7000', '96', '72', '72', '60', '25', { from: creater });
        await this.lc.addMinter(this.chef.address, { from: creater });
    
        this.referral = await Referral.new(this.lc.address, {from: creater});
        await this.referral.addOperator(this.chef.address, {from: creater});
        await this.chef.setReferral(this.referral.address, {from: creater});

        await this.lp1.transfer(alice, '2000', { from: creater });
        await this.lp2.transfer(alice, '2000', { from: creater });
        await this.lp3.transfer(alice, '2000', { from: creater });

        await this.lp1.transfer(bob, '2000', { from: creater });
        await this.lp1.transfer(carol, '2000', { from: creater });
        await this.lp2.transfer(bob, '2000', { from: creater });
        await this.lp2.transfer(carol, '2000', { from: creater });
       // await this.lp3.transfer(bob, '2000', { from: creater });
    });
    it('real case', async () => {
        await this.chef.add('1000', this.lp1.address, { from: creater });
		assert.equal((await this.chef.poolLength()).toString(), "1");
		assert.equal((await this.chef.totalAllocPoint()).toString(), "1000");
		console.log(`startBlock: ${(await this.chef.startBlock())}`);

        //1 - lp
        await this.lp1.approve(this.chef.address, '1000', { from: alice });
        await this.lc.approve(this.chef.address, '1000', { from: alice });
        console.log('----Deposit----');
		assert.equal((await this.lc.balanceOf(alice)).toString(), '0');
        await time.advanceBlockTo('150');
		console.log(`Current block: ${(await time.latestBlock())}`);
        await this.chef.deposit(0, '20', bob, { from: alice });
		let user = await this.chef.userInfo(0, alice, {from: alice});
		console.log(`${user[0]},${user[1]}`);
		console.log((await this.chef.pendingLC(0, alice)).toString());
        await time.advanceBlockTo('170');
		console.log((await this.chef.pendingLC(0, alice)).toString());
        console.log('---Withdraw---');
		console.log((await this.chef.pendingLC(0, alice)).toString());
		console.log(`Current block: ${(await time.latestBlock())}`);
        await time.advanceBlockTo('200'); 
        await this.chef.withdraw(0, '20', { from: alice });
		user = await this.chef.userInfo(0, alice, {from: alice});
		console.log(`${user[0]},${user[1]}`);
        await this.chef.claimLC(0, {from: alice});
        let aliceBalance = await this.lc.balanceOf(alice);
        console.log('alice balance: ', aliceBalance.toString());
		console.log(`Current block: ${(await time.latestBlock())}`);

        console.log('---------------');

        await time.advanceBlockTo('210'); 
        await this.chef.withdrawDevFee({ from: creater });
        let balanceDev0 = await this.lc.balanceOf(dev0);
        console.log('dev0 address balance: ', balanceDev0.toString());
        let balanceDev1 = await this.lc.balanceOf(dev1);
        console.log('dev1 address balance: ', balanceDev1.toString());
        let balanceDev2 = await this.lc.balanceOf(dev2);
        console.log('dev2 address balance: ', balanceDev2.toString());
        let balanceEco = await this.lc.balanceOf(ecoAddr);
        console.log('eco address balance: ', balanceEco.toString());
        let balanceTreasury = await this.lc.balanceOf(treasuryAddr);
        console.log('treasury address balance: ', balanceTreasury.toString());

        result = await this.referral.getReferralCommission.call(bob);
        console.log(`commission,${result[0]},${result[1]},${result[2]},${result[3]},${result[4]},${result[5]}`);
        assert.equal((await this.lc.balanceOf(bob)).toString(), '0');
        await this.referral.claimLpCommission({from: bob});
        assert.equal((await this.lc.balanceOf(bob)).toString(), '1750');
    })
});
