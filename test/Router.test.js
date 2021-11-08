const { expectRevert, time } = require('@openzeppelin/test-helpers');
const { AddressZero } = require("@ethersproject/constants")
const { assert } = require('chai');
const ethers = require('ethers');

const LuckyChipFactory = artifacts.require('LuckyChipFactory');
const LuckyChipRouter02 = artifacts.require('LuckyChipRouter02');
const LuckyChipPair = artifacts.require('LuckyChipPair');
const MockBEP20 = artifacts.require('MockBEP20');
const WBNB = artifacts.require('WBNB');

contract('LuckyChipRouter02', ([creater, swapFeeTo]) => {
    beforeEach(async () => {
        this.factory = await LuckyChipFactory.new(creater, { from: creater });
        console.log(`init_code_hash,${await this.factory.INIT_CODE_HASH()}`);
        await this.factory.setFeeTo(swapFeeTo, {from: creater});
        console.log(`feeTo,${await this.factory.feeTo()}`);

        this.token0 = await MockBEP20.new('Token0', 'Token0', ethers.utils.parseEther('1000000'), { from: creater });
        this.token1 = await MockBEP20.new('Token1', 'Token1', ethers.utils.parseEther('1000000'), { from: creater });
        console.log(`token0,${this.token0.address},token1,${this.token1.address}`);

        this.WBNB = await WBNB.new({from: creater});

        this.router = await LuckyChipRouter02.new(
            this.factory.address, 
            this.WBNB.address, 
            {from: creater});

        await this.token0.approve(this.router.address, ethers.constants.MaxUint256, {from: creater});
        await this.token1.approve(this.router.address, ethers.constants.MaxUint256, {from: creater});
        console.log(`token0 balance,${await this.token0.balanceOf(creater)}`);
        console.log(`token1 balance,${await this.token1.balanceOf(creater)}`);
        await this.router.addLiquidity(
            this.token0.address, 
            this.token1.address, 
            ethers.utils.parseEther('2'), 
            ethers.utils.parseEther('1'), 
            ethers.utils.parseEther('2'), 
            ethers.utils.parseEther('1'),
            creater,
            ethers.constants.MaxUint256
        );
        console.log(`token0 balance,${await this.token0.balanceOf(creater)}`);
        console.log(`token1 balance,${await this.token1.balanceOf(creater)}`);
    });
    it('removeLiquidity', async () => {
        const pairAddr = await this.factory.getPair(this.token0.address, this.token1.address);
        console.log(`pair,${pairAddr}`);
        const pair = await LuckyChipPair.at(pairAddr);
        const balance = await pair.balanceOf(creater);
        console.log(`balance,${balance}`);
        const result = await pair.getReserves.call();
        console.log(`${result[0]},${result[1]},${result[2]}`);

        await pair.approve(this.router.address, ethers.constants.MaxUint256, {from: creater});
        await this.router.removeLiquidity(
            this.token0.address, 
            this.token1.address, 
            balance,
            0,
            0,
            creater,
            ethers.constants.MaxUint256,
            {from: creater}
            );
        console.log(`token0 balance,${await this.token0.balanceOf(creater)}`);
        console.log(`token1 balance,${await this.token1.balanceOf(creater)}`);
    })
});
