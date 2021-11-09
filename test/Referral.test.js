const { assert } = require("chai");

const LCToken = artifacts.require('LCToken');
const Referral = artifacts.require('Referral');

contract('Referral', ([ref0, ref1, ref2, creater]) => {
    beforeEach(async () => {
        this.lc = await LCToken.new({ from: creater });
        await this.lc.addMinter(creater, {from: creater});
        await this.lc.mint(creater, ethers.utils.parseEther('100'), { from: creater })
        assert.equal((await this.lc.balanceOf(creater)).toString(), ethers.utils.parseEther('100').toString());
        
        this.referral = await Referral.new(this.lc.address, {from: creater});
        console.log(`referral,${this.referral.address}`);
        await this.lc.approve(this.referral.address, ethers.constants.MaxUint256, {from: creater});

        await this.referral.addOperator(creater, {from: creater});
    });

    it('recordReferrer', async () => {
        await this.referral.recordReferrer(ref1, ref0, {from: creater});
        result = await this.referral.getReferrer.call(ref1);
        assert.equal(ref0, result);
        await this.referral.recordReferrer(ref2, ref0, {from: creater});
        result = await this.referral.getReferrer.call(ref2);
        assert.equal(ref0, result);
        result = await this.referral.referralsCount(ref0);
        assert.equal(result, 2);
    })

    it('recordLpCommission', async () => {
        await this.referral.recordReferrer(ref1, ref0, {from: creater});
        await this.referral.recordReferrer(ref2, ref0, {from: creater});
        this.lc.mint(this.referral.address, ethers.utils.parseEther('1'), {from: creater});
        await this.referral.recordLpCommission(ref0, ethers.utils.parseEther('1'), {from: creater});
        result = await this.referral.getReferralCommission.call(ref0);
        console.log(`commission,${result[0]},${result[1]},${result[2]},${result[3]},${result[4]},${result[5]}`);

        assert.equal((await this.lc.balanceOf(ref0)).toString(), ethers.utils.parseEther('0').toString());
        await this.referral.claimLpCommission({from: ref0});
        assert.equal((await this.lc.balanceOf(ref0)).toString(), ethers.utils.parseEther('1').toString());
    })
    it('recordBetCommission', async () => {
        await this.referral.recordReferrer(ref1, ref0, {from: creater});
        await this.referral.recordReferrer(ref2, ref0, {from: creater});
        this.lc.mint(this.referral.address, ethers.utils.parseEther('1'), {from: creater});
        await this.referral.recordBetCommission(ref0, ethers.utils.parseEther('1'), {from: creater});
        result = await this.referral.getReferralCommission.call(ref0);
        console.log(`commission,${result[0]},${result[1]},${result[2]},${result[3]},${result[4]},${result[5]}`);

        assert.equal((await this.lc.balanceOf(ref0)).toString(), ethers.utils.parseEther('0').toString());
        await this.referral.claimBetCommission({from: ref0});
        assert.equal((await this.lc.balanceOf(ref0)).toString(), ethers.utils.parseEther('1').toString());
    })
    it('recordRankCommission', async () => {
        await this.referral.recordReferrer(ref1, ref0, {from: creater});
        await this.referral.recordReferrer(ref2, ref0, {from: creater});
        this.lc.mint(this.referral.address, ethers.utils.parseEther('1'), {from: creater});
        await this.referral.recordRankCommission(ref0, ethers.utils.parseEther('1'), {from: creater});
        result = await this.referral.getReferralCommission.call(ref0);
        console.log(`commission,${result[0]},${result[1]},${result[2]},${result[3]},${result[4]},${result[5]}`);

        assert.equal((await this.lc.balanceOf(ref0)).toString(), ethers.utils.parseEther('0').toString());
        await this.referral.claimRankCommission({from: ref0});
        assert.equal((await this.lc.balanceOf(ref0)).toString(), ethers.utils.parseEther('1').toString());
    })
    
});
