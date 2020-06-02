pragma solidity ^0.5.9;

import "./LiquidityPool.sol";

contract FXSwap {
    modifier onlyOwner {
		require(msg.sender == owner, "Only the contract owner can call this function");
		_;
	}
	address owner;

    FXSwapManager public fxSwapManager;

    address payable lpAddress;
    address payable buyerAddress;

    int256 public gbpDaiRate;
    uint public expiryTimestamp;
    uint public localAmount;

    uint public buyerAmountinWei;
    uint public lpAmountinWei;

    bool public isBuyerReady;
    bool public isLpReady;

    bool public isSettled;

    uint public marginAmountInEth;

    int256 public chainlinkUsdMultiplier;

    constructor(FXSwapManager _parentContract, address payable _lpAddress, address payable _buyerAddress, int256 _gbpDaiRate, uint _expiryTimestamp, uint256 _localAmount, uint256 _marginAmountInEth, int256 _chainlinkUsdMultiplier) public {
        owner = msg.sender;
        buyerAmountinWei = 0;
        lpAmountinWei = 0;

        fxSwapManager = _parentContract;
        gbpDaiRate = _gbpDaiRate;
        expiryTimestamp = _expiryTimestamp;
        localAmount = _localAmount;

        lpAddress = _lpAddress;
        buyerAddress = _buyerAddress;
        isBuyerReady = false;
        isLpReady = false;
        isSettled = false;
        chainlinkUsdMultiplier = _chainlinkUsdMultiplier;

        marginAmountInEth = _marginAmountInEth;
    }

    function () external payable {
        // Payment trigger, now transfer from LP to here
    }

    // Anyone can settle this
    function settle() external {
        // require(block.timestamp > expiryTimestamp, "Contract cannot be settled before expiry");
        require(isSettled == false, "Contract already settled");

        // Calculate payment due from latest FX rate
        int rateDiff = calculateRateDiff();

        int daiAmountDiff = (int(localAmount) * rateDiff);

        // Payments are made in eth, so convert dai diff to usd to eth
        int usdAmountDiff = (daiAmountDiff * chainlinkUsdMultiplier) / fxSwapManager.getDaiUsdRate();
        int ethAmountDiff = (usdAmountDiff * chainlinkUsdMultiplier) / fxSwapManager.getEthUsdRate();


        // Positive rateDiff means payment from LP to buyer
        // Negative rateDiff means payment from buyer to LP
        uint tmpLpAmountinWei = uint(int(lpAmountinWei) + ethAmountDiff);
        uint tmpBuyerAmountinWei = uint(int(buyerAmountinWei) + ethAmountDiff);

        // Withdaw so set to zero
        lpAmountinWei = 0;
        buyerAmountinWei = 0;

        // Update FXSwapManager balances

        // Update LP

        address(lpAddress).transfer(tmpLpAmountinWei);
        address(buyerAddress).transfer(tmpBuyerAmountinWei);

        // transfer from swap to addresses

        isSettled = true;
    }

    function calculateRateDiff() public view returns(int256) {
        return fxSwapManager.calculateGbpDaiRate() - gbpDaiRate;
    }

    function getBalance() external view returns(uint) {
        return address(this).balance;
    }

    function getMarginAmountInEth() external view returns(uint) {
        return marginAmountInEth;
    }

    function getOwnerAddress() external view returns(address) {
        return owner;
    }

    function setBuyerAmountinWei(uint256 _amount) public onlyOwner {
        buyerAmountinWei = _amount;
    }
    function setLpAmountinWei(uint256 _amount) public onlyOwner {
        lpAmountinWei = _amount;
    }

    // TEMP function 
    function tempReleaseBalance() public {
        uint tmpLpAmountinWei = lpAmountinWei;
        uint tmpBuyerAmountinWei = buyerAmountinWei;
        lpAmountinWei = 0;
        buyerAmountinWei = 0;
        address(lpAddress).transfer(tmpLpAmountinWei);
        address(buyerAddress).transfer(tmpBuyerAmountinWei);
    }
}

// ----------------------------------------------

contract FXSwapManager {
    modifier onlyOwner {
		require(msg.sender == owner, "Only the contract owner can call this function");
		_;
	}
	address owner;

    // struct S_FXSwap {
    //     FXSwap _fxSwap;
    //     // int256 _gbpDaiRate;         // FX Rate
    //     // uint256 _expiryTimestamp;   // Timestamp of maturity
    // }

    // Deposit of hedge buyer
    struct S_Deposit {
        uint256 _amountUnusedInWei; // Initially 0
        uint256 _amountUsedInWei;
        FXSwap _fxSwap;
    }

    // Map of deposits of hedge buyers
    mapping(address => S_Deposit) private buyDeposits;
    mapping(uint => address) private depositsIndex;

    // Margin requirement in percent
    uint margin = 25;

    // Temp
    bool public isSwapFound;
    bool public breakpointSet;

    // LP
    LiquidityPool public lpInstance;

    // All Chainlink USD reference data values are multipled by this
    int256 public chainlinkUsdMultiplier;

    constructor(address _daiUsdChainlinkContract, address _gbpUsdChainlinkContract, address _ethUsdChainlinkContract, int256 _chainlinkUsdMultiplier) public {
        owner = msg.sender;
        chainlinkUsdMultiplier = _chainlinkUsdMultiplier;

        isSwapFound = false;
        breakpointSet= false;

        lpInstance = new LiquidityPool(_daiUsdChainlinkContract, _gbpUsdChainlinkContract, _ethUsdChainlinkContract, _chainlinkUsdMultiplier);
    }

    // Hedge buyer deposits collateral amount needed to protect `daiAmount` for a certain gbp/dai rate and maturity timestamp
    function buyProtection (int256 _gbpDaiRate, uint256 _expiryTimestamp, uint256 _localAmount) external payable {

        // Local amount in Eth
        uint ethAmount = _localAmount * uint(lpInstance.calculateGbpEthRate());

        // Margin is provided in eth!
        // Calculate margin or amount needed as collateral to protect local amount
        uint marginAmountInEth = ethAmount * uint(margin) * uint(chainlinkUsdMultiplier)/100 ;

        // Can only buy protection if buyer has deposited enough ethAmount
        require(buyDeposits[msg.sender]._amountUnusedInWei >= marginAmountInEth, "Not enough funds");

        // Match swap with LP
        (bool isFound, address payable addressOfLP) = lpInstance.getFirstAvailableLP (_gbpDaiRate, _expiryTimestamp, marginAmountInEth);
        isSwapFound = isFound;
        if (isFound) {
            createSwap(this, addressOfLP, _gbpDaiRate, _expiryTimestamp, _localAmount, marginAmountInEth);
        }
    }

    // Buyer deposits eth as collateral
    function () external payable {
         buyDeposits[msg.sender]._amountUnusedInWei += msg.value;
    }

    function createSwap(FXSwapManager _parentContract, address payable _lpAddress, int256 _gbpDaiRate, uint256 _expiryTimestamp, uint256 _localAmount, uint256 _marginAmountInEth) private {
        FXSwap fxswap = new FXSwap(_parentContract, _lpAddress, msg.sender, _gbpDaiRate, _expiryTimestamp, _localAmount, _marginAmountInEth, chainlinkUsdMultiplier);
        buyDeposits[msg.sender]._amountUnusedInWei -= _marginAmountInEth;
        buyDeposits[msg.sender]._amountUsedInWei += _marginAmountInEth;

        // Update balances
        fxswap.setBuyerAmountinWei(_marginAmountInEth);
        fxswap.setLpAmountinWei(_marginAmountInEth);

        // TODO: Assert there is sufficient eth

        // Move margin amounts from buyer to swap
        //// lpInstance.depositToLP.value(msg.value)(msg.sender, _gbpDaiRateInBaseMultiple, _expiryTimestamp);
        address(fxswap).transfer(_marginAmountInEth);

        // Move margin amounts from seller to swap
        lpInstance.transferFromLpToSwap(_lpAddress, address(fxswap), _marginAmountInEth);
        breakpointSet = true;

        // Set swap
        buyDeposits[msg.sender]._fxSwap = fxswap;

    }

    // Buyers can withdraw amount not in use
    function withdraw() public {
        uint _amountToWithdraw = buyDeposits[msg.sender]._amountUnusedInWei;
        buyDeposits[msg.sender]._amountUnusedInWei = 0;

        address(msg.sender).transfer(_amountToWithdraw);
    }

    // TEMP function: Buyers can withdraw amount used
    function withdrawUsed() public {
        uint _amountToWithdraw = buyDeposits[msg.sender]._amountUsedInWei;
        buyDeposits[msg.sender]._amountUsedInWei = 0;

        address(msg.sender).transfer(_amountToWithdraw);
    }

    // FX Calculation
    function calculateGbpDaiRate() public view returns(int256) {
         return lpInstance.calculateGbpDaiRate();
    }
    function calculateGbpEthRate() public view returns(int256) {
        return lpInstance.calculateGbpEthRate();
    }

    // Get ETHUSD from Chainlink
    function getEthUsdRate() public view returns(int256) {
        return lpInstance.getEthUsdRate();
    }
    // Get DAIUSD from Chainlink
    function getDaiUsdRate() public view returns(int256) {
        return lpInstance.getDaiUsdRate();
    }
    // Get GBPUSD from Chainlink
    function getGbpUsdRate() public view returns(int256) {
        return lpInstance.getGbpUsdRate();
    }

    // Get depositor info
    function getBuyerAmountUnused() public view returns(uint256) {
        return buyDeposits[msg.sender]._amountUnusedInWei;
    }
    function getBuyerAmountUsed() public view returns(uint256) {
        return buyDeposits[msg.sender]._amountUsedInWei;
    }
    function getBuyerSwapBalance() public view returns(uint) {
        return buyDeposits[msg.sender]._fxSwap.getBalance();
    }

    function getMarginAmountInEth() public view returns(uint) {
        return buyDeposits[msg.sender]._fxSwap.getMarginAmountInEth();
    }

    function getOwnerAddress() public view returns(address) {
        return buyDeposits[msg.sender]._fxSwap.getOwnerAddress();
    }

    // Buyer can settle the swap
    function settleBuyerSwap() public {
        buyDeposits[msg.sender]._fxSwap.settle();
    }

    // LP can send deposit with FX rate and maturity
    function depositToLP (int256 _gbpDaiRateInBaseMultiple, uint256 _expiryTimestamp) external payable {
        lpInstance.depositToLP.value(msg.value)(msg.sender, _gbpDaiRateInBaseMultiple, _expiryTimestamp);
    }

    // Let LP withdraw
    function withdrawLP(address payable _sender) public {
        require(_sender == msg.sender, "Can only withdraw to sender address");
        lpInstance.withdraw(_sender);
    }

    // Let LP settle
    function settleLpSwap(uint _index) public {
        address fxSwapContractAddresses = getFXSwapAddress(_index);
    }

    // LP Functions
    function getDepositorAmountUnused() public view returns(uint256) {
        return lpInstance.getDepositorAmountUnused(msg.sender);
    }
    function getDepositorAmountUsed() public view returns(uint256) {
        return lpInstance.getDepositorAmountUsed(msg.sender);
    }
    function getDepositorGbpDaiRate() public view returns(int256) {
        return lpInstance.getDepositorGbpDaiRate(msg.sender);
    }
    function getDepositorExpiryTimestamp() public view returns(uint256) {
        return lpInstance.getDepositorExpiryTimestamp(msg.sender);
    }
    function getNumberOfSwaps() public view returns(uint) {
        return lpInstance.getNumberOfSwaps(msg.sender);
    }
    function getFXSwapAddress(uint _index) public view returns(address) {
        return lpInstance.getFXSwapAddress(msg.sender, _index);
    }

    // Helper Functions
    function getLastMsgSender() public view returns(address) {
        return lpInstance.getLastMsgSender();
    }

    function tempReleaseBalance() public {
        buyDeposits[msg.sender]._fxSwap.tempReleaseBalance();
    }
}
