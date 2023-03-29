// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "./TwitterClient.sol";

contract Firebird is ERC20, Ownable, ERC20Burnable, TwitterClient {
	uint256 public constant MAX_BURN_LIMIT = 100000; // 1% of total supply

	// Tax Percentages
	// uint256 public immutable buyTaxPercentage = 40;
	// uint256 public immutable sellTaxPercentage = 40;
	uint256 public immutable marketingFee = 20;
	uint256 public immutable liquidityFee = 20;
	uint256 public immutable oracleFee = 20;
	uint256 public immutable reflectionFee = 20;

	// Tax Wallets
	address public marketingWallet;
	address public oracleWallet;

	// Tracks addresses that are excluded from buy/sell fees
	mapping(address => bool) private _excludedFromFee;
	uint256 public _tokenThreshold;
	bool inSwapAndLiquify;

	IUniswapV2Router02 public uniswapV2Router;
	address public uniswapV2Pair;

	modifier lockSwap() {
		inSwapAndLiquify = true;
		_;
		inSwapAndLiquify = false;
	}

	constructor(
		uint256 initialSupply,
		address _marketingWallet,
		address _oracleWallet,
		address _oracle,
		bytes32 _jobId,
		uint256 _fee
	) ERC20("Firebird", "FBRD") TwitterClient(_oracle, _jobId, _fee) {
		// Configure Uniswap router and token pair
		uniswapV2Router = IUniswapV2Router02(
			0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
		);
		uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(
			address(this),
			uniswapV2Router.WETH()
		);

		// Set marketing and oracle fund wallets
		marketingWallet = _marketingWallet;
		oracleWallet = _oracleWallet;

		// Exclude owner, contract address, and marketing wallet from fees
		_excludedFromFee[msg.sender] = true;
		_excludedFromFee[address(this)] = true;
		_excludedFromFee[marketingWallet] = true;

		// Mint intial token supply
		_mint(msg.sender, initialSupply * 10 ** decimals());
	}

	/**
	 * @dev Callback function for Chainlink oracle to update tweet count
	 */
	function onFulfill(uint256 _tweetCount) internal {
		if (_tweetCount > 0) {
			uint256 burnAmount = _tweetCount > MAX_BURN_LIMIT
				? MAX_BURN_LIMIT
				: _tweetCount;
			_burn(msg.sender, burnAmount * 10 ** decimals());
		}
	}

	/**
	 * @dev Allow contract owner to update marketing wallet
	 */
	function updateWalletMarketing(
		address _marketingWallet
	) external onlyOwner {
		marketingWallet = _marketingWallet;
	}

	/**
	 * @dev Allow contract owner to update oracle fund wallet
	 */
	function updateWalletOracle(address _oracleWallet) external onlyOwner {
		oracleWallet = _oracleWallet;
	}

	/**
	 * @dev Exclude or include an account from buy/sell fees
	 */
	function setExcludedFromFee(
		address account,
		bool excluded
	) external onlyOwner {
		_excludedFromFee[account] = excluded;
	}

	/**
	 * @dev Override ERC20 transfer function to apply buy/sell taxes
	 */
	function _transfer(
		address _from,
		address _to,
		uint256 _amount
	) internal override {
		require(_from != address(0), "ERC20: transfer from the zero address");
		require(_to != address(0), "ERC20: transfer to the zero address");
		require(_amount > 0, "Transfer amount must be greater than zero");

		bool overThreshold = balanceOf(address(this)) >= _tokenThreshold;
		if (overThreshold && !inSwapAndLiquify && _from != uniswapV2Pair) {
			swapAndSendFees();
		}

		bool takeFee = true;
		if (
			_excludedFromFee[_from] ||
			_excludedFromFee[_to] ||
			(_from != uniswapV2Pair && _to != uniswapV2Pair)
		) {
			takeFee = false;
		}

		uint256 finalTransferAmount = _amount;
		if (takeFee) {
			uint256 totalFeesPercent = marketingFee +
				liquidityFee +
				oracleFee +
				reflectionFee;
			uint256 fees = (_amount * totalFeesPercent) / 1000;
			finalTransferAmount = _amount - fees;
			super._transfer(_from, address(this), fees);
		}

		super._transfer(_from, _to, finalTransferAmount);
	}

	function swapAndSendFees() private lockSwap {
		uint256 contractBalance = balanceOf(address(this));
		require(contractBalance > _tokenThreshold);
		uint256 quarterBalance = contractBalance / 4;

		//Send out fees
		// Swap a 1/4 of tokens for LINK
		swapTokensForLink(quarterBalance);
		// Send to oracle wallet

		// Swap 3/4 tokens to ETH
		swapTokensForEth(quarterBalance * 3);
		// Send to marketing, liquidity, and reflection wallet
		// payable(marketingWallet).transfer();
	}

	/**
	 * @dev Swap tokens for LINK
	 */
	function swapTokensForLink(uint256 _tokenAmount) private {
		// generate the uniswap pair path of token -> WETH -> LINK
		address[] memory path = new address[](3);
		path[0] = address(this);
		path[1] = uniswapV2Router.WETH();
		path[2] = getLinkAddress();

		_approve(address(this), address(uniswapV2Router), _tokenAmount);

		// make the swap
		uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
			_tokenAmount,
			0,
			path,
			address(this),
			block.timestamp
		);
	}

	/**
	 * @dev Swap tokens for ETH
	 */
	function swapTokensForEth(uint256 _tokenAmount) private {
		// generate the uniswap pair path of token -> WETH
		address[] memory path = new address[](2);
		path[0] = address(this);
		path[1] = uniswapV2Router.WETH();

		_approve(address(this), address(uniswapV2Router), _tokenAmount);

		// execute swap
		uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
			_tokenAmount,
			0, // accept any amount of ETH
			path,
			address(this),
			block.timestamp
		);
	}
}
