const { expectRevert, time } = require('@openzeppelin/test-helpers');
const { AddressZero } = require("@ethersproject/constants")
const { assert } = require('chai');
const ethers = require('ethers');

const LuckyChipFactory = artifacts.require('LuckyChipFactory');
const LuckyChipRouter02 = artifacts.require('LuckyChipRouter02');
const MockBEP20 = artifacts.require('MockBEP20');
const WBNB = artifacts.require('WBNB');

contract('LuckyChipRouter02', ([creater, dev2, swapFeeTo]) => {
    beforeEach(async () => {
        this.factory = await LuckyChipFactory.new(creater, { from: creater });
        console.log(`init_code_hash,${await this.factory.INIT_CODE_HASH()}`);
        await this.factory.setFeeTo(swapFeeTo, {from: creater});
        console.log(`feeTo,${await this.factory.feeTo()}`);

        this.token0 = await MockBEP20.new('Token0', 'Token0', '1000000', { from: creater });
        this.token1 = await MockBEP20.new('Token1', 'Token1', '1000000', { from: creater });
        console.log(`token0,${this.token0.address},token1,${this.token1.address}`);

        this.WBNB = await WBNB.new({from: creater});

        this.router = await LuckyChipRouter02.new(this.factory.address, this.WBNB, {from: creater});
        
    });

    it('addLiquidity', async () => {
        await this.router.addLiquidity(
            this.token0.address, 
            this.token1.address, 
            ethers.utils.parseEther('2'), 
            ethers.utils.parseEther('1'), 
            ethers.utils.parseEther('1.6'), 
            ethers.utils.parseEther('0.8'),
            dev2,
            ethers.constants.MaxUint256
            );
        
    })
});
