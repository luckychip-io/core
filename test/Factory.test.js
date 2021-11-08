const { expectRevert, time } = require('@openzeppelin/test-helpers');
const { AddressZero } = require("@ethersproject/constants")
const { assert } = require('chai');
const ethers = require('ethers');

const LuckyChipFactory = artifacts.require('LuckyChipFactory');
const MockBEP20 = artifacts.require('MockBEP20');

contract('LuckyChipFactory', ([creater, swapFeeTo]) => {
    beforeEach(async () => {
        this.factory = await LuckyChipFactory.new(creater, { from: creater });
        console.log(`init_code_hash,${await this.factory.INIT_CODE_HASH()}`);
        await this.factory.setFeeTo(swapFeeTo, {from: creater});
        console.log(`feeTo,${await this.factory.feeTo()}`);

        this.token0 = await MockBEP20.new('Token0', 'Token0', '1000000', { from: creater });
        this.token1 = await MockBEP20.new('Token1', 'Token1', '1000000', { from: creater });
        
        console.log(`token0,${this.token0.address},token1,${this.token1.address}`);
    });

    it('createPair', async () => {
        await this.factory.createPair(this.token0.address, this.token1.address, { from: creater });
        console.log(`pair0,${await this.factory.allPairs(0)}`);
    })
});
