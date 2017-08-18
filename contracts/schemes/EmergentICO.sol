pragma solidity ^0.4.11;

import "../controller/Controller.sol";

contract EmergentICO {

  event LogDonationReceived
  (
    uint indexed _donationId,
    address indexed _donator,
    address indexed _beneficiary,
    uint _periodId,
    uint _value,
    uint _minRate
  );
  event LogPeriodAverageComputed(uint _periodId);
  event LogCollect(uint _donation, uint tokens);

  struct Donation {
    address donor;
    address beneficiary;
    uint periodId;
    uint value;
    uint minRate;
    bool isCollected;
  }

  struct AvarageComputator {
    uint periodId;
    uint donorsCounted;
    uint avarageRateComputed;
    uint fundsToBeReturned;
  }

  struct Period {
    uint donationsCounterInPeriod;
    uint clearedDonations;
    uint incomingInPeriod;
    uint raisedInPeriod;
    uint raisedUpToPeriod;
    uint averageRate;
    bool isInitialized;
    bool isAverageRateComputed;
    uint[] donationsIdsWithLimit;
  }


  mapping (uint=>Donation) donations;
  mapping (uint=>Period) periods;
  mapping (address=>AvarageComputator) avarageComputators;

  // Parameters:
  Controller public controller; // The conroller is responsible to mint tokens.
  address public admin; // Admin can halt and resume the ICO, and also clear batches for everyone.
  address public target; // The funds will be tranffered here.
  uint public startBlock; // ICO starting block.
  uint public clearancePeriodDuration; // The length of each clearance period in blocks.
  uint public minDonation;
  // Rate function is initialRate*(rateFractionNumerator/rateFractionDenominator)^x.
  uint public initialRate;
  uint public rateFractionNumerator;
  uint public rateFractionDenominator;
  uint public batchSize;

  // Variables:
  uint public totalReceived; // Total of funds received in the contract, including the returned change.
  uint public totalDonated; // The total funds actually donated.
  uint public donationCounter;
  bool public isHalted; // Flag to indicate ICO is halted.

  /**
   * @dev Modifier, Allow only an admin to access:
   */
  modifier onlyAdmin() {
    require(msg.sender == admin);
    _;
  }

  /**
   * @dev Modifier, Check if a given period is finished:
   * @param _periodId the period checked.
   */
  modifier isPeriodOver(uint _periodId) {
    require(_periodId < currentClearancePeriod());
    _;
  }

  /**
   * @dev Modifier, Check if a given period is initialized for average computations:
   * @param _periodId the period checked.
   */
  modifier isPeriodInitialized(uint _periodId) {
    require(periods[_periodId].isInitialized);
    _;
  }

  /**
   * @dev Constructor, setting all the parameters:
   */
  function EmergentICO(
    Controller _controller,
    address _admin,
    address _target,
    uint _startBlock,
    uint _clearancePeriodDuration,
    uint _minDonation,
    uint _initialRate,
    uint _rateFractionNumerator,
    uint _rateFractionDenominator,
    uint _batchSize
    ) {
      // Set parameters:
      controller = _controller;
      admin = _admin;
      target = _target;
      startBlock = _startBlock;
      clearancePeriodDuration = _clearancePeriodDuration;
      minDonation = _minDonation;
      initialRate = _initialRate;
      rateFractionNumerator = _rateFractionNumerator;
      rateFractionDenominator = _rateFractionDenominator;
      batchSize = _batchSize;

      // Initialize:
      periods[0].isInitialized = true;
  }

  /**
   * @dev Pausing ICO, using onlyAdmin modifier:
   */
  function haltICO() onlyAdmin {
    isHalted = true;
  }

  /**
   * @dev Resuming ICO, using onlyAdmin modifier:
   */
  function resumeICO() onlyAdmin {
    isHalted = false;
  }

  /**
   * @dev Modifier, Check if a given period is initialized for average computations:
   * @param _periodId the period checked.
   */
  function getIsPeriodInitialized(uint _periodId) constant returns(bool) {
    return(periods[_periodId].isInitialized);
  }

  /**
   * @dev Constant boolean function, checking if the ICO is active:
   */
  function isActive() constant returns(bool) {
    if (isHalted) {
      return false;
    }
    if (block.number < startBlock) {
      return false;
    }
    return true;
  }

  /**
   * @dev Constant function, returns the current periodId:
   */
  function currentClearancePeriod() constant returns(uint) {
    require(block.number >= startBlock);
    return ((block.number - startBlock)/clearancePeriodDuration);
  }

  /**
   * @dev Constant function, computes the rate for in a given batch:
   * @param _batch the batch for which the computation is done.
   */
  function rate18Digits(uint _batch) constant returns(uint) {
    return ((10**18)*initialRate*rateFractionNumerator**_batch/rateFractionDenominator**_batch);
  }

  /**
   * @dev Constant function, computes the average rate between two points.
   * @param _start the starting point for the computation.
   * @param _end the starting point for the computation.
   */
  function averageRateCalc18Digits(uint _start, uint _end) constant returns(uint) {
    uint batchStart = _start/batchSize;
    uint batchEnd = _end/batchSize;
    uint partOfStartBatch = batchSize - _start%batchSize;
    uint partOfEndBatch = _end%batchSize;
    uint delta = batchEnd - batchStart;

    if (delta == 0) {
        return rate18Digits(batchStart);
    }
    if (delta == 1) {
        return (partOfStartBatch*rate18Digits(batchStart) + partOfEndBatch*rate18Digits(batchEnd))/(_end-_start);
    }
    if (delta > 1) {
        uint geomSeries = batchSize*(rate18Digits(batchStart+1)-rate18Digits(batchEnd))*rateFractionDenominator/(rateFractionDenominator-rateFractionNumerator);
        return (geomSeries + partOfStartBatch*rate18Digits(batchStart) + partOfEndBatch*rate18Digits(batchEnd))/(_end-_start);
    }
  }

  /**
   * @dev The actual donation function.
   * @param _beneficiary The address that will receive the tokens.
   * @param _minRate the minimum rate the donor is willing to participate in.
   */
  function donate(address _beneficiary, uint _minRate) payable {
    // Check ICO is open:
    require(isActive());

    // Check minimum donation:
    require(msg.value >= minDonation);

    // Update period data:
    uint currentPeriod = currentClearancePeriod();
    Period period = periods[currentPeriod];
    period.incomingInPeriod += msg.value;
    period.donationsCounterInPeriod++;
    if (_minRate != 0) {
      period.donationsIdsWithLimit.push(donationCounter);
    } else {
      period.raisedInPeriod += msg.value;
    }

    // Update donation data:
    donations[donationCounter] = Donation({
      donor: msg.sender,
      beneficiary: _beneficiary,
      periodId: currentPeriod,
      value: msg.value,
      minRate: _minRate,
      isCollected: false
    });
    donationCounter++;
    totalReceived += msg.value;

    // If minimum rate is 0 move funds to target now:
    if (_minRate == 0) {
      totalDonated += msg.value;
      target.transfer(msg.value);
    }

    // If we can determine that the donation will not go through, revert:
    if (_minRate != 0 && period.isInitialized) {
      if (averageRateCalc18Digits(period.raisedUpToPeriod, period.raisedUpToPeriod+period.raisedInPeriod) < _minRate) {
        revert();
      }
    }

    // Event:
    LogDonationReceived(donationCounter-1, msg.sender, _beneficiary, currentClearancePeriod(), msg.value, _minRate);
  }

  /**
   * @dev Fallback function.
   * upon receivng funds, treat it as donation with default parameters, minRate=0.
   */
  function () payable {
    donate(msg.sender, 0);
  }

  /**
   * @dev an agent can set what he thinks is the correct average for a period and start the test.
   * @param _periodId the period for which average is computed.
   * @param _average the average computed by the user.
   * @param _iterations number of iterations to check from the array donationsIdsWithLimit.
   */
  function setAverageAndTest(uint _periodId, uint _average, uint _iterations)
    isPeriodOver(_periodId)
    isPeriodInitialized(_periodId)
  {
    avarageComputators[msg.sender] = AvarageComputator({
      periodId: _periodId,
      donorsCounted: 0,
      avarageRateComputed: _average,
      fundsToBeReturned: 0
    });
    checkAverage(_periodId, _iterations);
  }

  /**
   * @dev an agent testing his average computation.
   * @param _periodId the period for which average is computed.
   * @param _iterations number of iterations to check from the array donationsIdsWithLimit.
   */
  function checkAverage(uint _periodId, uint _iterations)
    isPeriodOver(_periodId)
    isPeriodInitialized(_periodId)
  {
    Period memory period = periods[_periodId];
    AvarageComputator avgComp = avarageComputators[msg.sender];
    require(avgComp.periodId == _periodId);

    // Run over the array of donors with limit, sum the ones that are to be refunded:
    for (uint cnt=0; cnt < _iterations; cnt++) {
      uint donationId = period.donationsIdsWithLimit[avgComp.donorsCounted];
      if (donations[donationId].minRate > avgComp.avarageRateComputed) {
        avgComp.fundsToBeReturned += donations[donationId].value;
      }
      avgComp.donorsCounted += 1;
    }
    // Check if finished:
    if (avgComp.donorsCounted == period.donationsIdsWithLimit.length) {
      uint computedRaisedInPeriod = period.incomingInPeriod - avgComp.fundsToBeReturned;
      uint computedRate = averageRateCalc18Digits(period.raisedUpToPeriod, periods[_periodId].raisedUpToPeriod+computedRaisedInPeriod);
      if (computedRate == avgComp.avarageRateComputed) {
        period.isAverageRateComputed = true;
        period.raisedInPeriod = computedRaisedInPeriod;
        period.averageRate = computedRate;
        periods[_periodId+1].raisedUpToPeriod = period.raisedUpToPeriod + period.raisedInPeriod;
        periods[_periodId+1].isInitialized = true;
        delete avarageComputators[msg.sender];
        LogPeriodAverageComputed(_periodId);
      }
    }
  }

  /**
   * @dev Internal function, clearing donation, either minting tokens or refunding.
   * @param _donationId The donation to be cleared.
   */
  function collectTokens(uint _donationId) internal {
    Donation memory donation = donations[_donationId];
    Period memory period = periods[donation.periodId];

    // Check collection is possible:
    require(donation.periodId  < currentClearancePeriod());
    require(period.isAverageRateComputed);
    if (donation.isCollected) {
      return;
    }

    // Mark donation as collected:
    donation.isCollected = true;
    period.clearedDonations++;

    // Check the donation minimum rate is valid, if so mint tokens, else, return funds:
    if (donation.minRate >= period.averageRate) {
      uint tokensToMint = period.averageRate*donation.value/period.raisedInPeriod/(10**18);
      controller.mintTokens(tokensToMint, donation.beneficiary);
      LogCollect(_donationId, tokensToMint);
    } else {
      donation.donor.transfer(donation.value);
      LogCollect(_donationId, 0);
    }
  }

  /**
   * @dev Collecting donor own tokens.
   * Although not really necessary, only the doner (or the admin) can clear his own donation.
   * @param _donationId The donation to be cleared.
   */
  function collectMine(uint _donationId) {
    // Check sender is indeed the donor:
    require(msg.sender == donations[_donationId].donor);
    // Collect:
    collectTokens(_donationId);
  }

  /**
   * @dev OnlyAdmin function, can clear donations for everyone.
   * Although not really necessary, only the doner (or the admin) can clear his own donation.
   * @param _donationIds array of donations to be cleared.
   */
  function collectMulti(uint[] _donationIds) onlyAdmin {
    for (uint cnt=0; cnt<_donationIds.length; cnt++) {
      collectTokens(_donationIds[cnt]);
    }
  }
}