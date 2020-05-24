pragma solidity ^0.5.9;

import "./LiquidityPool.sol";

contract FXSwap {
    FXSwapManager public fxSwapManager;
    
    address lpAddress;
    address buyerAddress;
    
    int256 public gbpDaiRate;
    uint public expiryTimestamp;
    uint public localAmount;
    
    uint public buyerAmountinWei;
    uint public lpAmountinWei;
    
    bool public isBuyerReady;
    bool public isLpReady;
    
    uint marginAmountInEth;
    
    constructor(FXSwapManager _parentContract, address _lpAddress, address _buyerAddress, int256 _gbpDaiRate, uint _expiryTimestamp, uint256 _localAmount, uint256 _marginAmountInEth) public {
        fxSwapManager = _parentContract;
        gbpDaiRate = _gbpDaiRate;
        expiryTimestamp = _expiryTimestamp;
        localAmount = _localAmount;

        lpAddress = _lpAddress;
        buyerAddress = _buyerAddress;
        isBuyerReady = false;
        isLpReady = false;
    }
    
    function () external payable {
        // Payment trigger, now transfer from LP to here
    }
    
    // Anyone can settle this
    function settle() external payable {
        require(block.timestamp > expiryTimestamp, "Contract cannot be settled before expiry");

        
        
        // transfer from swap to addresses
        // calculate payment due from latest FX rate
        int256 latestGbpDaiRate = fxSwapManager.calculateGbpDaiRate();
    }
    
    function getBalance() external view returns(uint) {
        return address(this).balance;
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
        FXSwap[] _fxSwaps;
    }
    
    // Map of deposits of hedge buyers
    mapping(address => S_Deposit) private buyDeposits;
    mapping(uint => address) private depositsIndex;
    
    // Margin requirement in percent
    uint margin = 25;
    
    // LP
    LiquidityPool public lpInstance;
    
    // All Chainlink USD reference data values are multipled by this
    int256 public chainlinkUsdMultiplier;
    
    constructor(address _daiUsdChainlinkContract, address _gbpUsdChainlinkContract, address _ethUsdChainlinkContract, int256 _chainlinkUsdMultiplier) public {
        owner = msg.sender;
        chainlinkUsdMultiplier = _chainlinkUsdMultiplier;
        
        lpInstance = new LiquidityPool(_daiUsdChainlinkContract, _gbpUsdChainlinkContract, _ethUsdChainlinkContract, _chainlinkUsdMultiplier);
    }
    

    // Hedge buyer deposits collateral amount needed to protect `daiAmount` for a certain gbp/dai rate and maturity timestamp
    function buyProtection (int256 _gbpDaiRate, uint256 _expiryTimestamp, uint256 _localAmount) external payable {
        
        // Local amount in DAI
        uint daiAmount = _localAmount * uint(lpInstance.calculateGbpDaiRate());
        
        // Local amount in Eth
        uint ethAmount = _localAmount * uint(lpInstance.calculateGbpEthRate());
        
        // Margin is provided in eth!
        // Calculate margin or amount needed as collateral to protect local amount
        uint marginAmountInEth = ethAmount * margin;
        
        // Can only buy protection if buyer has deposited enough ethAmount
        require(buyDeposits[msg.sender]._amountUnusedInWei >= marginAmountInEth);
        
        // Match swap with LP
        (bool isFound, address addressOfLP) = lpInstance.getFirstAvailableLP (_gbpDaiRate, _expiryTimestamp, marginAmountInEth);
        if (isFound) {
            createSwap(this, addressOfLP, _gbpDaiRate, _expiryTimestamp, _localAmount, marginAmountInEth);
        }
    }
    
    // Buyer deposits eth as collateral
    function () external payable {
         buyDeposits[msg.sender]._amountUnusedInWei += msg.value;
    }
    
    function createSwap(FXSwapManager _parentContract, address _lpAddress, int256 _gbpDaiRate, uint256 _expiryTimestamp, uint256 _localAmount, uint256 _marginAmountInEth) private {
        FXSwap fxswap = new FXSwap(_parentContract, _lpAddress, msg.sender, _gbpDaiRate, _expiryTimestamp, _localAmount, _marginAmountInEth);
        buyDeposits[msg.sender]._amountUnusedInWei -= _marginAmountInEth;
        buyDeposits[msg.sender]._amountUsedInWei += _marginAmountInEth;
        
        // Move margin amounts from buyer and seller
        address(fxswap).transfer(_marginAmountInEth);
        lpInstance.transferFromLpToSwap(_lpAddress, address(fxswap), _marginAmountInEth);
        
        buyDeposits[msg.sender]._fxSwaps.push(fxswap);
        
    }
    
    // Buyers can withdraw amount not in use
    function withdraw() public {
        uint _amountToWithdraw = buyDeposits[msg.sender]._amountUnusedInWei;
        buyDeposits[msg.sender]._amountUnusedInWei = 0;
        
        address(msg.sender).transfer(_amountToWithdraw);
    }
    
    // FX Calculation
    function calculateGbpDaiRate() public view returns(int256) {
         return lpInstance.calculateGbpDaiRate();
    }
    function calculateGbpEthRate() public view returns(int256) {
        return lpInstance.calculateGbpEthRate();
    }
    
    // Get depositor info
    function getBuyerAmountUnused() public view returns(uint256) {
        return buyDeposits[msg.sender]._amountUnusedInWei;
    }
    function getBuyerAmountUsed() public view returns(uint256) {
        return buyDeposits[msg.sender]._amountUsedInWei;
    }
    function getBuyerNumberOfSwap() public view returns(uint) {
        return buyDeposits[msg.sender]._fxSwaps.length;
    }
    function getBuyerSwapBalance(uint _index) public view returns(uint) {
        return buyDeposits[msg.sender]._fxSwaps[_index].getBalance();
    }
}
