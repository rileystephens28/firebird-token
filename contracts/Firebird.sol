// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "./TwitterClient.sol";

contract Firebird is ERC20, Ownable, ERC20Burnable, TwitterClient {
	uint256 public constant MAX_BURN_LIMIT = 100000; // 1% of total supply

	// Tax Percentages
	uint256 public immutable marketingFee = 10;
	uint256 public immutable liquidityFee = 10;
	uint256 public immutable oracleFee = 10;

	// Tax Wallets
	address public marketingWallet;
	address public oracleWallet;

	// Tracks addresses that are excluded from buy/sell fees
	mapping(address => bool) private _excludedFromFee;
	uint256 private _tokenThreshold;
	bool private _inSwapAndLiquify;
	bool private _sendFeeEnabled;

	IUniswapV2Router02 public uniswapV2Router;
	address public uniswapV2Pair;

	modifier lockSwap() {
		_inSwapAndLiquify = true;
		_;
		_inSwapAndLiquify = false;
	}

	constructor(
		uint256 initialSupply,
		address _marketingWallet,
		address _oracleWallet,
		address _uniswapV2Router,
		address _linkToken,
		address _oracle,
		bytes32 _jobId,
		uint256 _fee
	)
		ERC20("Firebird", "FBRD")
		TwitterClient(_linkToken, _oracle, _jobId, _fee)
	{
		// Configure Uniswap router and token pair
		uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
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
	function _onFulfill(uint256 _tweetCount) internal override {
		if (_tweetCount > 0) {
			uint256 burnAmount = _tweetCount > MAX_BURN_LIMIT
				? MAX_BURN_LIMIT
				: _tweetCount;
			_burn(msg.sender, burnAmount * 10 ** decimals());
		}
	}

	/**
	 * @dev Check if buy/sell fees are enabled
	 */
	function isSendFeeEnabled() external view returns (bool) {
		return _sendFeeEnabled;
	}

	/**
	 * @dev Check if an address is excluded from buy/sell fees
	 * @param _address Address to check
	 */
	function isExcludedFromFee(address _address) external view returns (bool) {
		return _excludedFromFee[_address];
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
	 * @dev Set whether buy/sell fees are enabled
	 */
	function setFeeEnabled(bool enabled) external onlyOwner {
		_sendFeeEnabled = enabled;
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
	 * @dev Override ERC20 transfer function to apply buy/sell taxes
	 */
	function _transfer(
		address _from,
		address _to,
		uint256 _amount
	) internal override {
		require(_from != address(0), "ERC20: transfer from the zero address");
		require(_to != address(0), "ERC20: transfer to the zero address");
		require(
			_amount > 0,
			"ERC20: Transfer amount must be greater than zero"
		);

		bool overThreshold = balanceOf(address(this)) >= _tokenThreshold;
		if (
			overThreshold &&
			_sendFeeEnabled &&
			!_inSwapAndLiquify &&
			_from != uniswapV2Pair
		) {
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
			uint256 totalFeesPercent = marketingFee + liquidityFee + oracleFee;
			uint256 fees = (_amount * totalFeesPercent) / 1000;
			finalTransferAmount = _amount - fees;
			super._transfer(_from, address(this), fees);
		}

		super._transfer(_from, _to, finalTransferAmount);
	}

	function swapAndSendFees() private lockSwap {
		uint256 contractTokenBalance = balanceOf(address(this));
		require(contractTokenBalance > _tokenThreshold);
		uint256 thirdTokenBalance = contractTokenBalance / 3;

		// Swap a 1/3 of tokens for LINK and send to oracle wallet
		swapTokensForLink(thirdTokenBalance);
		IERC20 link = IERC20(getLinkAddress());
		uint256 linkBalance = link.balanceOf(address(this));
		link.transfer(oracleWallet, linkBalance);

		contractTokenBalance -= thirdTokenBalance;

		// Swap 3/4 tokens to ETH
		uint256 tokensToSwapToEth = (contractTokenBalance / 4) * 3;
		swapTokensForEth(tokensToSwapToEth);

		// Send to 2/3 of ETH to marketing wallet
		uint256 marketingEthToTransfer = (address(this).balance / 3) * 2;
		payable(marketingWallet).transfer(marketingEthToTransfer);

		// Add remaining token and ETH balance to uniswap liquidity
		addLiquidity(balanceOf(address(this)), address(this).balance);
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

	/**
	 * @dev Add liquidity to uniswap pool
	 */
	function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
		// approve token transfer to cover all possible scenarios
		_approve(address(this), address(uniswapV2Router), tokenAmount);

		// add the liquidity
		uniswapV2Router.addLiquidityETH{ value: ethAmount }(
			address(this),
			tokenAmount,
			0, // slippage is unavoidable
			0, // slippage is unavoidable
			owner(),
			block.timestamp
		);
	}
}
