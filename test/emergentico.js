import * as helpers from './helpers';
import { Organization } from '../lib/organization.js';

const EmergentICO = artifacts.require("./EmergentICO.sol");

// Vars
let accounts, org, newICO;
let admin, target, startBlock,clearancePeriodDuration, minDonation, initialRate, rateFractionNumerator, rateFractionDenominator, batchSize;

const setupEmergentICO = async function(){

  accounts = web3.eth.accounts;

  admin = accounts[0];
  target = accounts[9];
  startBlock = web3.eth.blockNumber;
  clearancePeriodDuration = 10;
  minDonation =  web3.toWei(1, "ether");
  initialRate = 100;
  rateFractionNumerator = 99;
  rateFractionDenominator = 100;
  batchSize = web3.toWei(20, "ether");
  const founders = [
    {
      address: accounts[0],
      reputation: 30,
      tokens: 30,
    }];
  org = await Organization.new({
    orgName: 'AdamsOrg',
    tokenName: 'AdamCoin',
    tokenSymbol: 'ADM',
    founders,
  });
    newICO = await EmergentICO.new(org.contoller, admin, target, startBlock, clearancePeriodDuration, minDonation, initialRate, rateFractionNumerator, rateFractionDenominator, batchSize);
};

contract("EmergentICO", function(accounts){
  before(function() {
    helpers.etherForEveryone();
  });

  it("Check rate function", async function(){
    await setupEmergentICO();

    const frac = rateFractionNumerator/rateFractionDenominator;

    const batch7Rate = Number(web3.toWei(initialRate*frac**7),"ether");
    const batch17Rate =  Number(web3.toWei(initialRate*frac**17),"ether");

    // Checking rate is the same up to rounding error:
    assert(Math.abs(batch7Rate - Number (await newICO.rate18Digits(7)))/batch7Rate < 10**(-8));
    assert(Math.abs(batch17Rate - Number (await newICO.rate18Digits(17)))/batch7Rate < 10**(-8));
  });

  it("Check average rate function", async function(){
    await setupEmergentICO();

    const frac = rateFractionNumerator/rateFractionDenominator;
    const start = 31;
    const end = 85;

    const averageRate = initialRate*(9*frac + 20*frac**2 + 20*frac**3 + 5*frac**4)/(end-start);
    const averageRate18Digits = Number(web3.toWei(averageRate, "ether"));
    const averageRateCalc18Digits = Number(await newICO.averageRateCalc18Digits(web3.toWei(start, "ether"), web3.toWei(end, "ether")));

    // Checking rate is the same up to rounding error:
    assert(Math.abs(averageRate18Digits - averageRateCalc18Digits)/averageRate18Digits < 10**(-8));
  });

  it("Only admin can halt and resume the ICO", async function(){

    await setupEmergentICO();

    await newICO.haltICO();
    // ICO should be inactive - Admin halted
    assert.equal(await newICO.isActive(), false);
    newICO.resumeICO();
    // ICO should be active - Admin resumed
    assert.equal(await newICO.isActive(), true);

    // only the admin can halt the ICO
    try {
        await newICO.haltICO({from: accounts[1]});
        throw 'an error'; // make sure that an error is thrown
    } catch(error) {
        helpers.assertVMException(error);
    }
    // ICO should be still active - The halt request sent from non admin account
    assert.equal(await newICO.isActive(), true);

    // Halting the ICO:
    await newICO.haltICO();
    // only the admin can resume the ICO
    try {
        await newICO.resumeICO({from: accounts[1]});
        throw 'an error'; // make sure that an error is thrown
    } catch(error) {
        helpers.assertVMException(error);
    }
    // ICO should still be halted:
    assert.equal(await newICO.isActive(), false);
  });

  it("Try donating when ICO is halted", async function(){
    await setupEmergentICO();

    // Halting the ICO:
    await newICO.haltICO();

    // Try to donate:
    try {
      await web3.eth.sendTransaction({
        from: accounts[1],
        to: newICO.address,
        value: web3.toWei(2, "ether"),
      });
      throw 'an error'; // make sure that an error is thrown
    } catch(error) {
        helpers.assertVMException(error);
    }

    // Checking contract variables:
    assert.equal(await newICO.totalReceived(), 0);
    assert.equal(await newICO.donationCounter(), 0);
  });

  it("Try donating below minimum", async function(){
    await setupEmergentICO();


    // Try to donate:
    try {
      await web3.eth.sendTransaction({
        from: accounts[1],
        to: newICO.address,
        value: web3.toWei(0.5, "ether"),
      });
      throw 'an error'; // make sure that an error is thrown
    } catch(error) {
        helpers.assertVMException(error);
    }

    // Checking contract variables:
    assert.equal(await newICO.totalReceived(), 0);
    assert.equal(await newICO.donationCounter(), 0);
  });

  it("Single regular donation", async function(){
    await setupEmergentICO();

    const donationInWei = web3.toWei(2, "ether");
    const targetOriginalBalance = await web3.eth.getBalance(target);

    // Regular small send:
    await web3.eth.sendTransaction({
      from: accounts[1],
      to: newICO.address,
      value: web3.toWei(2, "ether"),
      gas: 600000
    });
    // Checking contract variables:
    assert.equal(Number(await newICO.totalReceived()), donationInWei);
    assert.equal(Number(await newICO.totalDonated()), donationInWei);
    assert.equal(await newICO.donationCounter(), 1);
    assert.equal(Number(await web3.eth.getBalance(target)), Number(targetOriginalBalance) + Number(donationInWei));
  });

  it("Single donation with limit", async function(){
    await setupEmergentICO();

    const donationInWei = web3.toWei(2, "ether");
    const targetOriginalBalance = await web3.eth.getBalance(target);

    // Donating:
    await newICO.donate(accounts[2], web3.toWei(5,"ether"), {from: accounts[1], value: donationInWei});

    // Checking contract variables:
    assert.equal(Number(await newICO.totalReceived()), donationInWei);
    assert.equal(await newICO.totalDonated(), 0);
    assert.equal(await newICO.donationCounter(), 1);
    assert.equal(await Number(web3.eth.getBalance(target)), Number(targetOriginalBalance));
  });

  it("Test donations and average calculation of period [ToDo: add more checks about the final state]", async function(){
    await setupEmergentICO();

    // Original data:
    const period = Number(await newICO.currentClearancePeriod());

    // Donating:
    await newICO.donate(accounts[1], 0, {from: accounts[1], value: web3.toWei(15, "ether")});
    await newICO.donate(accounts[3], web3.toWei(99.95,"ether"), {from: accounts[3], value: web3.toWei(4, "ether")});
    await newICO.donate(accounts[4], web3.toWei(99,"ether"), {from: accounts[4], value: web3.toWei(12, "ether")});
    await newICO.donate(accounts[5], web3.toWei(98.5,"ether"), {from: accounts[5], value: web3.toWei(11, "ether")});

    // Mining blocks to end period:
    while(Number(await newICO.currentClearancePeriod()) == period) {
        await web3.eth.sendTransaction({
          from: accounts[0],
          to: accounts[1],
          value: web3.toWei(0.1,"ether")
        });
    }

    // Checking contract variables:
    assert.equal(Number(await newICO.totalReceived()), Number(web3.toWei(42, "ether")));
    assert.equal(await newICO.totalDonated(), Number(web3.toWei(15, "ether")));
    assert.equal(await newICO.donationCounter(), 4);

    // Compute all previous periods, and initialize current period:
    for (let cnt=0; cnt<period; cnt++) {
      await newICO.setAverageAndTest(cnt, web3.toWei(initialRate), 0);
    }
    const periodInit = await newICO.getIsPeriodInitialized(period);
    assert.equal(periodInit, true);

    // Try a wrong average:
    const avgWrong = await newICO.averageRateCalc18Digits(0, web3.toWei(39,"ether"));
    await newICO.setAverageAndTest(period, avgWrong, 3);
    const periodPlus1InitFalse = await newICO.getIsPeriodInitialized(period+1);
    assert.equal(periodPlus1InitFalse, false);

    // Compute average and let contract test it:
    const avg = await newICO.averageRateCalc18Digits(0, web3.toWei(38,"ether"));
    await newICO.setAverageAndTest(period, avg, 1);
    await newICO.checkAverage(period, 2);
    const periodPlus1Init = await newICO.getIsPeriodInitialized(period+1);
    assert.equal(periodPlus1Init, true);

     // Collect tokens:
    //  const token = org.token;
    //  const initBalance5 = await token.balanceOf(accounts[5]);
    //  console.log(Number(initBalance5));
    //  await newICO.collectMine(3, { from: accounts[5] });
    //  const balance5 = await token.balanceOf(accounts[5]);
    //  console.log(Number(balance5));
  });

  it("Test collection of funds and tokens [ToDo]", async function() {
  });

});