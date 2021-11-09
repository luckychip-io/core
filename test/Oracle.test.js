const { assert } = require("chai");
const { ethers } = require("ethers");

const LuckyChipFactory = artifacts.require('LuckyChipFactory');
const LuckyChipRouter02 = artifacts.require('LuckyChipRouter02');
const LuckyChipPair = artifacts.require('LuckyChipPair');
const WBNB = artifacts.require('WBNB');
const LCToken = artifacts.require('LCToken');
const Oracle = artifacts.require('Oracle');

contract('Oracle', ([alice, bob, carol, dev, creater, swapFeeTo]) => {
    before(async () => {
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
    });

    it('update', async () => {
        await this.oracle.update(this.lc.address, this.WBNB.address, {from: alice});
    })
    it('updateBlockInfo', async () => {
        await this.oracle.updateBlockInfo({from: creater});
    })
    it('getAveragePrice', async () => {
        const price = await this.oracle.getAveragePrice.call(this.lc.address);
        console.log(`lc price,${price}`);
    })
    it('getAveragePriceBNB', async () => {
        const price = await this.oracle.getAveragePrice.call(this.WBNB.address);
        console.log(`bnb price,${price}`);
    })
    it('getQuantity', async () => {
        const quantity = await this.oracle.getQuantity.call(this.lc.address, ethers.utils.parseEther("1"));
        console.log(`bnb quantity,${quantity}`);
    })
    it('getQuantityBNB', async () => {
        const quantity = await this.oracle.getQuantity.call(this.WBNB.address, ethers.utils.parseEther("1"));
        console.log(`bnb quantity,${quantity}`);
    })
    it('getLpTokenValue', async () => {
        const pairAddr = await this.factory.getPair(this.lc.address, this.WBNB.address);
        console.log(`pair,${pairAddr}`);
        const pair = await LuckyChipPair.at(pairAddr);
        const balance = await pair.balanceOf(creater);
        console.log(`balance,${balance}`);
        const value = await this.oracle.getLpTokenValue.call(pairAddr, balance);
        console.log(`lp Token,${value}`);
    })
});
