pragma solidity ^0.5.9;

import "./ChainlinkRef.sol";

// Contract for Liquidity Providers to deposit their Ethereum
contract LiquidityPool {

    address owner;

    struct S_Deposit {
        uint256 _amountUnusedInWei; // Initially 0
        uint256 _amountUsedInWei;   // Initially 0
        int256 _gbpDaiRate;  // Rate that LP will accept at most * baseRateMultiple
        uint256 _expiryTimestamp; // Maturity of longest swap exposure
    }

    struct S_LPSwaps {
       address[] _fxSwapContractAddress;
    }

    // Map of deposits of LPs
    mapping(address => S_Deposit) private deposits;
    mapping(uint => address payable) private depositsIndex;

    // Map of swaps of LPs
    mapping(address => S_LPSwaps) private lpSwaps;

    // Total number of depositors (unique address)
    uint public totalDeposits;

    // Store latest Chainlink values and timestamp
    struct S_ChainlinkData {
        int256 _gbpUsdRate;
        uint256 _gbpUsdTimestamp;
        uint256 _gbpUsdRound;
        int256 _daiUsdRate;
        uint256 _daiUsdTimestamp;
        uint256 _daiUsdRound;
        int256 _ethUsdRate;
        uint256 _ethUsdTimestamp;
        uint256 _ethUsdRound;
    }
    ChainlinkRef private gbpUsdInstance;
    ChainlinkRef private daiUsdInstance;
    ChainlinkRef private ethUsdInstance;
    S_ChainlinkData public chainlinkData;

    // All Chainlink USD reference data values are multipled by this
    int256 public chainlinkUsdMultiplier;

    modifier onlyOwner {
		require(msg.sender == owner, "Only the contract owner can call this function");
		_;
	}

	event lpDeposit(address indexed _from, uint _amount, int256 _gbpDaiRate, uint _expiryTimestamp, uint _amountUnusedInWei, uint _amountUsedInWei);
	event lpWithdraw(address indexed _from, uint _amount);

	// temp
	address public lastMsgSender;

    constructor(address _daiUsdChainlinkContract, address _gbpUsdChainlinkContract, address _ethUsdChainlinkContract, int256 _chainlinkUsdMultiplier) public {
		owner = msg.sender;
	    totalDeposits = 0;
        chainlinkUsdMultiplier = _chainlinkUsdMultiplier;

        // Set oracles
        daiUsdInstance = ChainlinkRef(_daiUsdChainlinkContract);
        gbpUsdInstance = ChainlinkRef(_gbpUsdChainlinkContract);
        ethUsdInstance = ChainlinkRef(_ethUsdChainlinkContract);
    }

    // LP can send deposit with FX rate and maturity
    function depositToLP (address payable _sender, int256 _gbpDaiRateInBaseMultiple, uint256 _expiryTimestamp) external payable {
        lastMsgSender = msg.sender;
        // Additional deposits just add to existing account, cannot change params, unless withdrawws
        if(deposits[_sender]._expiryTimestamp == 0) {
            deposits[_sender]._expiryTimestamp = _expiryTimestamp;
            deposits[_sender]._gbpDaiRate = _gbpDaiRateInBaseMultiple;
        }
        totalDeposits++;
        depositsIndex[totalDeposits] = _sender;

        // Receive ether as deposit
        deposits[_sender]._amountUnusedInWei += msg.value;

        emit lpDeposit(_sender, msg.value, deposits[_sender]._gbpDaiRate, deposits[_sender]._expiryTimestamp, deposits[_sender]._amountUnusedInWei,  deposits[_sender]._amountUsedInWei);
    }

    // LP can send deposit with default FX rate at current fx and maturity + 24hr
    function () external payable {
        if(deposits[msg.sender]._expiryTimestamp == 0) {
            deposits[msg.sender]._expiryTimestamp = block.timestamp + 86400;
            deposits[msg.sender]._gbpDaiRate = calculateGbpDaiRate();
        }
        totalDeposits++;
        depositsIndex[totalDeposits] = msg.sender;
        
        // Receive ether as deposit
        deposits[msg.sender]._amountUnusedInWei += msg.value;

        // Emit deposit event
        emit lpDeposit(msg.sender, msg.value, deposits[msg.sender]._gbpDaiRate, deposits[msg.sender]._expiryTimestamp, deposits[msg.sender]._amountUnusedInWei,  deposits[msg.sender]._amountUsedInWei);
    }


    // Get depositor info
    function getDepositorAmountUnused(address _sender) public view returns(uint256) {
        return deposits[_sender]._amountUnusedInWei;
    }
    function getDepositorAmountUsed(address _sender) public view returns(uint256) {
        return deposits[_sender]._amountUsedInWei;
    }
    function getDepositorGbpDaiRate(address _sender) public view returns(int256) {
        return deposits[_sender]._gbpDaiRate;
    }
    function getDepositorExpiryTimestamp(address _sender) public view returns(uint256) {
        return deposits[_sender]._expiryTimestamp;
    }

    // FX Calculation
    function calculateGbpDaiRate() public view returns(int256) {
         return (getGbpUsdRate() * chainlinkUsdMultiplier) / getDaiUsdRate();
    }
    function calculateGbpEthRate() public view returns(int256) {
        return (getGbpUsdRate() * chainlinkUsdMultiplier) / getEthUsdRate();
    }


    // LP can withdraw amount that is unused
    function withdraw(address payable _sender) public {
        lastMsgSender = msg.sender;
        uint _amountToWithdraw = deposits[_sender]._amountUnusedInWei;
        deposits[_sender]._amountUnusedInWei = 0;

        address(_sender).transfer(_amountToWithdraw);
    }

    // Get GBPUSD from Chainlink
    function getGbpUsdRate() public view returns(int256) {
        return gbpUsdInstance.getLatestAnswer();
    }
    function getGbpUsdTimestamp() public view returns(uint256) {
        return gbpUsdInstance.getLatestTimestamp();
    }
    function getGbpUsdRound() public view returns(uint256) {
        return gbpUsdInstance.getLatestRound();
    }
    // Get DAIUSD from Chainlink
    function getDaiUsdRate() public view returns(int256) {
        return daiUsdInstance.getLatestAnswer();
    }
    function getDaiUsdTimestamp() public view returns(uint256) {
        return daiUsdInstance.getLatestTimestamp();
    }
    function getDaiUsdRound() public view returns(uint256) {
        return daiUsdInstance.getLatestRound();
    }
    // Get ETHUSD from Chainlink
    function getEthUsdRate() public view returns(int256) {
        return ethUsdInstance.getLatestAnswer();
    }
    function getEthUsdTimestamp() public view returns(uint256) {
        return ethUsdInstance.getLatestTimestamp();
    }
    function getEthUsdRound() public view returns(uint256) {
        return ethUsdInstance.getLatestRound();
    }

    // Set GBP and DAI data
    function setGbpAndDaiData() public onlyOwner {
        setGbpUsdRate();
        setGbpUsdTimestamp();
        setGbpUsdRound();
        setDaiUsdRate();
        setDaiUsdTimestamp();
        setDaiUsdRound();
        setEthUsdRate();
        setEthUsdTimestamp();
        setEthUsdRound();
    }

    // Set GBPUSD
    function setGbpUsdRate() private onlyOwner {
        chainlinkData._gbpUsdRate = getGbpUsdRate();
    }
    function setGbpUsdTimestamp() private onlyOwner {
         chainlinkData._gbpUsdTimestamp = getGbpUsdTimestamp();
    }
    function setGbpUsdRound() private onlyOwner {
        chainlinkData._gbpUsdRound = getGbpUsdRound();
    }
    // Set DAIUSD
    function setDaiUsdRate() private onlyOwner {
        chainlinkData._daiUsdRate = getDaiUsdRate();
    }
    function setDaiUsdTimestamp() private onlyOwner  {
        chainlinkData._daiUsdTimestamp = getDaiUsdTimestamp();
    }
    function setDaiUsdRound() private onlyOwner {
        chainlinkData._daiUsdRound = getDaiUsdRound();
    }
    // Set ETHUSD
    function setEthUsdRate() private onlyOwner {
        chainlinkData._ethUsdRate = getEthUsdRate();
    }
    function setEthUsdTimestamp() private onlyOwner  {
        chainlinkData._ethUsdTimestamp = getEthUsdTimestamp();
    }
    function setEthUsdRound() private onlyOwner {
        chainlinkData._ethUsdRound = getEthUsdRound();
    }

    // Filtering functions

    // Get the first LP which has unused margin available to make swap matching requirement
    function getFirstAvailableLP (int256 _gbpDaiRate, uint256 _expiryTimestamp, uint _marginNeeded) public view returns(bool, address payable) {
        uint index = 1;
        bool isFound = false;
        address payable addressOfDeposit;

        while (index <= totalDeposits) {
            addressOfDeposit = depositsIndex[index];
            if (deposits[addressOfDeposit]._amountUnusedInWei >= _marginNeeded && deposits[addressOfDeposit]._gbpDaiRate >= _gbpDaiRate && deposits[addressOfDeposit]._expiryTimestamp >= _expiryTimestamp) {
                isFound = true;
                break;
            }
        }

        return(isFound, addressOfDeposit);
    }

    function transferFromLpToSwap(address _lpAddress, address payable _fxswapAddress, uint _amount) public onlyOwner {
        // Update amounts of lp
        deposits[_lpAddress]._amountUnusedInWei -= _amount;
        deposits[_lpAddress]._amountUsedInWei += _amount;

        // Adding swap to mapping
        address[] storage fxSwapContractAddresses = lpSwaps[_lpAddress]._fxSwapContractAddress;
        fxSwapContractAddresses.push(_fxswapAddress);
        lpSwaps[_lpAddress]._fxSwapContractAddress = fxSwapContractAddresses;

        address(_fxswapAddress).transfer(_amount);
    }

    function getNumberOfSwaps(address _lpAddress) public view returns(uint) {
        return lpSwaps[_lpAddress]._fxSwapContractAddress.length;
    }

    function getFXSwapAddress(address _lpAddress, uint _index) public view returns(address) {
        return lpSwaps[_lpAddress]._fxSwapContractAddress[_index];
    }

    // Helper Functions
    function getLastMsgSender() public view returns(address) {
        return lastMsgSender;
    }
}
