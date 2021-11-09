const { assert } = require("chai");

const LCToken = artifacts.require('LCToken');

contract('LCToken', ([alice, bob, carol, dev, creater]) => {
    beforeEach(async () => {
        this.lc = await LCToken.new({ from: creater });
        await this.lc.addMinter(creater, {from: creater});
    });


    it('mint', async () => {
        await this.lc.mint(alice, 1000, { from: creater });
        assert.equal((await this.lc.balanceOf(alice)).toString(), '1000');
    })
});
