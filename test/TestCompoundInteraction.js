const { time } = require("@openzeppelin/test-helpers");
const assert = require("assert");
const BN = require("bn.js");
const { ethers } = require("hardhat");
const { pow } = require("./util");

const IERC20 = await ethers.getContractFactory("IERC20");
const CErc20 = await ethers.getContractFactory("CErc20");
const CompoundInteraction = await ethers.getContractFactory(
  "TestCompoundErc20"
);

const DEPOSIT_AMOUNT = pow(10, 8).mul(new BN(1)).toString();

contract("TestCompoundErc20", (accounts) => {
  const WHALE = 0xf977814e90da44bfa03b6295a0616a897441acec;
  const TOKEN = 0x6b175474e89094c44da98b954eedeac495271d0f;
  const C_TOKEN = 0x5d3a536e4d6dbd6114cc1ead35777bab948e3643;

  let testCompound;
  let token;
  let cToken;
  beforeEach(async () => {
    await ethers.provider.send("eth_sendTransaction", [
      { from: accounts[0], to: WHALE, value: "0x1" },
    ]);

    testCompound = await CompoundInteraction.deploy(TOKEN, C_TOKEN);
    token = await IERC20.attach(TOKEN);
    cToken = await CErc20.attach(C_TOKEN);

    const bal = await token.balanceOf(WHALE);
    console.log(`whale balance: ${bal}`);
    assert(bal.gte(DEPOSIT_AMOUNT), "bal < deposit");
  });

  const getData = async (testCompound, token, cToken) => {
    // static call to a non view/pure function
    const { exchangeRate, supplyRate } = await testCompound.getInfo.call();

    return {
      exchangeRate,
      supplyRate,
      estimateBalance: await testCompound.estimateBalanceOfUnderlying.call(),
      balanceOfUnderlying: await testCompound.balanceOfUnderlying.call(),
      token: await token.balanceOf(testCompound.address),
      cToken: await cToken.balanceOf(testCompound.address),
    };
  };

  it("should supply and redeem", async () => {
    await token.approve(testCompound.address, DEPOSIT_AMOUNT, { from: WHALE });

    let tx = await testCompound.depositToken(DEPOSIT_AMOUNT, {
      from: WHALE,
    });

    let after = await getData(testCompound, token, cToken);

    // for (const log of tx.logs) {
    //   console.log(log.event, log.args.message, log.args.val.toString())
    // }

    console.log("--- supply ---");
    console.log(`exchange rate ${after.exchangeRate}`);
    console.log(`supply rate ${after.supplyRate}`);
    console.log(`estimate balance ${after.estimateBalance}`);
    console.log(`balance of underlying ${after.balanceOfUnderlying}`);
    console.log(`token balance ${after.token}`);
    console.log(`c token balance ${after.cToken}`);

    // gain interest on deposited token
    const block = await ethers.provider.getBlockNumber();
    await time.advanceBlockTo(block + 100);

    after = await getData(testCompound, token, cToken);

    console.log(`--- after some blocks... ---`);
    console.log(`balance of underlying ${after.balanceOfUnderlying}`);

    // test redeem
    const cTokenAmount = await cToken.balanceOf(testCompound.address);
    tx = await testCompound.redeem(cTokenAmount, {
      from: WHALE,
    });

    after = await getData(testCompound, token, cToken);

    console.log(`--- redeem ---`);
    console.log(`balance of underlying ${after.balanceOfUnderlying}`);
    console.log(`token balance ${after.token}`);
    console.log(`c token balance ${after.cToken}`);
  });
});
