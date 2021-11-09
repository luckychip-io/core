const { assert } = require("chai");

const LCToken = artifacts.require('LCToken');
const Lottery = artifacts.require('Lottery');

contract('Lottery', ([alice, bob, carol, lucky0, lucky1, lucky2, lucky3, creater]) => {
    beforeEach(async () => {
        this.lc = await LCToken.new({ from: creater });
        await this.lc.addMinter(creater, {from: creater});
        await this.lc.mint(creater, ethers.utils.parseEther('100'), { from: creater })
        assert.equal((await this.lc.balanceOf(creater)).toString(), ethers.utils.parseEther('100').toString());
        
        this.lottery = await Lottery.new(this.lc.address, {from: creater});
        console.log(`lottery,${this.lottery.address}`);
        await this.lc.approve(this.lottery.address, ethers.constants.MaxUint256, {from: creater});
    });

    it('injectFirstPrize', async () => {
        await this.lottery.injectFirstPrize([lucky0], ethers.utils.parseEther('12'), {from: creater});
        const result = await this.lottery.getLotteryInfo.call(lucky0);
        console.log(`lotteryInfo,${result[0]},${result[1]},${result[2]},${result[3]},${result[4]}`);
        assert.equal((await this.lc.balanceOf(creater)).toString(), ethers.utils.parseEther('88').toString());
    })
    it('injectSecondPrize', async () => {
        await this.lottery.injectSecondPrize([lucky1, lucky2], ethers.utils.parseEther('12'), {from: creater});
        const result = await this.lottery.getLotteryInfo.call(lucky1);
        console.log(`lotteryInfo,${result[0]},${result[1]},${result[2]},${result[3]},${result[4]}`);
        assert.equal((await this.lc.balanceOf(creater)).toString(), ethers.utils.parseEther('88').toString());
    })
    it('injectThirdPrize', async () => {
        await this.lottery.injectThirdPrize([lucky0, lucky2, lucky3], ethers.utils.parseEther('12'), {from: creater});
        const result = await this.lottery.getLotteryInfo.call(lucky3);
        console.log(`lotteryInfo,${result[0]},${result[1]},${result[2]},${result[3]},${result[4]}`);
        assert.equal((await this.lc.balanceOf(creater)).toString(), ethers.utils.parseEther('88').toString());
    })
    it('claimLottery', async () => {
        await this.lottery.injectFirstPrize([lucky0], ethers.utils.parseEther('12'), {from: creater});
        await this.lottery.injectSecondPrize([lucky1, lucky2], ethers.utils.parseEther('12'), {from: creater});
        await this.lottery.injectThirdPrize([lucky0, lucky2, lucky3], ethers.utils.parseEther('12'), {from: creater});
        result = await this.lottery.getLotteryInfo.call(lucky0);
        console.log(`lotteryInfo,${result[0]},${result[1]},${result[2]},${result[3]},${result[4]}`);
        result = await this.lottery.getLotteryInfo.call(lucky2);
        console.log(`lotteryInfo,${result[0]},${result[1]},${result[2]},${result[3]},${result[4]}`);
        assert.equal((await this.lc.balanceOf(creater)).toString(), ethers.utils.parseEther('64').toString());

        assert.equal((await this.lc.balanceOf(lucky0)).toString(), ethers.utils.parseEther('0').toString());
        await this.lottery.claimLottery({from: lucky0});
        assert.equal((await this.lc.balanceOf(lucky0)).toString(), ethers.utils.parseEther('16').toString());

        assert.equal((await this.lc.balanceOf(lucky1)).toString(), ethers.utils.parseEther('0').toString());
        await this.lottery.claimLottery({from: lucky1});
        assert.equal((await this.lc.balanceOf(lucky1)).toString(), ethers.utils.parseEther('6').toString());

        assert.equal((await this.lc.balanceOf(lucky2)).toString(), ethers.utils.parseEther('0').toString());
        await this.lottery.claimLottery({from: lucky2});
        assert.equal((await this.lc.balanceOf(lucky2)).toString(), ethers.utils.parseEther('10').toString());

        assert.equal((await this.lc.balanceOf(lucky3)).toString(), ethers.utils.parseEther('0').toString());
        await this.lottery.claimLottery({from: lucky3});
        assert.equal((await this.lc.balanceOf(lucky3)).toString(), ethers.utils.parseEther('4').toString());

        result = await this.lottery.getSecondPrize.call();
        console.log(`lotteryInfo,${result[0][0]},${result[0][1]},${result[1]},${result[2]}`);
    })
});
