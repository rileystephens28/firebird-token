// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";

/**
 * @title TwitterClient
 * @dev A contract that uses Chainlink to query the Twitter API for the daily tweet count of a specific phrase.
 */
contract TwitterClient is ChainlinkClient {
	using Chainlink for Chainlink.Request;

	// Constants
	string public constant TARGET_PHRASE = "#firebirdistheword";

	// Chainlink variables
	address private oracle;
	bytes32 private jobId;
	uint256 private fee;

	// State variables
	uint256 public tweetCount;

	/**
	 * @dev Constructor function
	 */
	constructor(
		address _linkToken,
		address _oracle,
		bytes32 _jobId,
		uint256 _fee
	) {
		setChainlinkToken(_linkToken);
		oracle = _oracle; // Set your Chainlink oracle address here
		jobId = _jobId; // Set your Chainlink jobID here
		fee = _fee * 10 ** 18; // 0.1 LINK
	}

	/**
	 * @dev Internal function to get LINK address
	 */
	function getLinkAddress() public view returns (address) {
		return chainlinkTokenAddress();
	}

	/**
	 * @dev Sends a Chainlink request to query the Twitter API for the daily tweet count of the target phrase.
	 */
	function requestTweetCount() public virtual {
		Chainlink.Request memory req = buildChainlinkRequest(
			jobId,
			address(this),
			this.fulfillTweetCount.selector
		);
		req.add("targetPhrase", TARGET_PHRASE);
		sendChainlinkRequestTo(oracle, req, fee);
	}

	/**
	 * @dev Callback function that is called by Chainlink when a tweet count response is received.
	 * @param _requestId The ID of the Chainlink request.
	 * @param _tweetCount The tweet count returned by the Twitter API.
	 */
	function fulfillTweetCount(
		bytes32 _requestId,
		uint256 _tweetCount
	) public recordChainlinkFulfillment(_requestId) {
		_onFulfill(_tweetCount);
	}

	/**
	 * @dev Internal function that is called when a tweet count response is received.
	 * @param _tweetCount The tweet count returned by the Twitter API.
	 */
	function _onFulfill(uint256 _tweetCount) internal virtual {}
}
