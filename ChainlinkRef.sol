pragma solidity ^0.5.9;

import "https://github.com/smartcontractkit/chainlink/blob/master/evm-contracts/src/v0.5/interfaces/AggregatorInterface.sol";

contract ChainlinkRef {
    AggregatorInterface internal ref;

    constructor(address _aggregator) public {
        ref = AggregatorInterface(_aggregator);
    }

    function getLatestAnswer() public view returns (int256) {
        return ref.latestAnswer();
    }

    function getLatestTimestamp() public view returns (uint256) {
        return ref.latestTimestamp();
    }

    function getPreviousAnswer(uint256 _back) public view returns (int256) {
        uint256 latest = ref.latestRound();
        require(_back <= latest, "Not enough history");
        return ref.getAnswer(latest - _back);
    }

    function getPreviousTimestamp(uint256 _back) public view returns (uint256) {
        uint256 latest = ref.latestRound();
        require(_back <= latest, "Not enough history");
        return ref.getTimestamp(latest - _back);
    }

    function getLatestRound() public view returns (uint256) {
        return ref.latestRound();
    }
}
