import { expect } from "chai";
import { constants } from "ethers";
import { ethers, UniswapV2Deployer } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";

function eth(amount: number) {
	return ethers.utils.parseEther(amount.toString());
}

describe("Firebird Token Contract", function () {
	const INITIAL_TOKEN_SUPPLY = eth(10000000);
	const TOKEN_LIQUIDITY = eth(1000);
	const WETH_LIQUIDITY = eth(500);

	async function deploy() {
		// Get list of available accounts
		const [owner, alice, bob, dummyOracle, marketingWallet, oracleWallet] =
			await ethers.getSigners();

		// deploy the uniswap v2 protocol
		const { factory, router, weth9 } = await UniswapV2Deployer.deploy(
			owner
		);

		// deposit some eth into weth
		await weth9.deposit({
			value: eth(1000)
		});

		// Deploy Link Token Contract
		const Link = await ethers.getContractFactory("LinkToken");
		const link = await Link.deploy();
		await link.deployed();

		// Deploy Firebird Token
		const Firebird = await ethers.getContractFactory("Firebird");
		const firebird = await Firebird.deploy(
			10000000,
			marketingWallet.address,
			oracleWallet.address,
			router.address,
			link.address,
			dummyOracle.address,
			ethers.utils.formatBytes32String("dummyJobId"),
			eth(1)
		);
		await firebird.deployed();

		// approve the spending
		await weth9.approve(router.address, constants.MaxUint256);
		await firebird.approve(router.address, constants.MaxUint256);

		// add liquidity
		await router.addLiquidityETH(
			firebird.address, // token address
			TOKEN_LIQUIDITY, // token amount
			TOKEN_LIQUIDITY, // min token amount
			WETH_LIQUIDITY, // min eth amount
			owner.address, // recipient
			constants.MaxUint256, // deadline
			{ value: eth(10) } // eth amount
		);

		// get our pair
		const pair = new ethers.Contract(
			await firebird.uniswapV2Pair(),
			UniswapV2Deployer.Interface.IUniswapV2Pair.abi
		);

		return {
			firebird,
			owner,
			alice,
			bob,
			dummyOracle,
			marketingWallet,
			oracleWallet,
			factory,
			router,
			weth9,
			pair
		};
	}

	it("should have the correct name", async function () {
		const { firebird } = await loadFixture(deploy);
		const name = await firebird.name();
		expect(name).to.equal("Firebird");
	});

	it("should have the correct symbol", async function () {
		const { firebird } = await loadFixture(deploy);
		const symbol = await firebird.symbol();
		expect(symbol).to.equal("FBRD");
	});

	it("should have the correct decimals", async function () {
		const { firebird } = await loadFixture(deploy);
		const decimals = await firebird.decimals();
		expect(decimals).to.equal(18);
	});

	it("should mint initial supply to owner", async function () {
		const { firebird, owner } = await loadFixture(deploy);
		const expectedBalance = INITIAL_TOKEN_SUPPLY.sub(TOKEN_LIQUIDITY);
		expect((await firebird.balanceOf(owner.address)).toString()).to.equal(
			expectedBalance.toString()
		);
	});

	it("should update marketing wallet", async function () {
		const { firebird, bob } = await loadFixture(deploy);
		await firebird.updateWalletMarketing(bob.address);
		const newMarketingWallet = await firebird.marketingWallet();
		expect(newMarketingWallet).to.equal(bob.address);
	});

	it("should revert when non-owner updates marketing wallet", async function () {
		const { firebird, alice } = await loadFixture(deploy);
		await expect(
			firebird.connect(alice).updateWalletMarketing(alice.address)
		).to.be.revertedWith("Ownable: caller is not the owner");
	});

	it("should update oracle wallet", async function () {
		const { firebird, bob } = await loadFixture(deploy);
		await firebird.updateWalletOracle(bob.address);
		const newOracleWallet = await firebird.oracleWallet();
		expect(newOracleWallet).to.equal(bob.address);
	});

	it("should revert when non-owner updates oracle wallet", async function () {
		const { firebird, alice } = await loadFixture(deploy);
		await expect(
			firebird.connect(alice).updateWalletOracle(alice.address)
		).to.be.revertedWith("Ownable: caller is not the owner");
	});

	it("should update fee dispersion threshold", async function () {
		const { firebird } = await loadFixture(deploy);
		await firebird.updateFeeDispersionThreshold(eth(2));
		const newFeeDispersionThreshold =
			await firebird.feeDispersionThreshold();
		expect(newFeeDispersionThreshold).to.equal(eth(2));
	});

	it("should revert when non-owner updates fee dispersion threshold", async function () {
		const { firebird, alice } = await loadFixture(deploy);
		await expect(
			firebird.connect(alice).updateFeeDispersionThreshold(eth(2))
		).to.be.revertedWith("Ownable: caller is not the owner");
	});

	it("should update tweet burn multiplier", async function () {
		const { firebird } = await loadFixture(deploy);
		await firebird.updateTweetBurnMultiplier(20);
		const newTweetBurnMultiplier = await firebird.tweetBurnMultiplier();
		expect(newTweetBurnMultiplier).to.equal(20);
	});

	it("should revert when non-owner updates tweet burn multiplier", async function () {
		const { firebird, alice } = await loadFixture(deploy);
		await expect(
			firebird.connect(alice).updateTweetBurnMultiplier(20)
		).to.be.revertedWith("Ownable: caller is not the owner");
	});

	it("should exclude and include an account from fees", async function () {
		const { firebird, alice } = await loadFixture(deploy);
		// Exclude account
		await firebird.setExcludedFromFee(alice.address, true);
		const excluded = await firebird.isExcludedFromFee(alice.address);
		expect(excluded).to.equal(true);

		// Include account
		await firebird.setExcludedFromFee(alice.address, false);
		const included = await firebird.isExcludedFromFee(alice.address);
		expect(included).to.equal(false);
	});

	it("should tax on buy", async function () {
		const { router, weth9, firebird, bob, pair } = await loadFixture(
			deploy
		);

		// Expect bob to receive 97 FBRD, firebird contract to receive 3 FBRD and pair to lose 10 WETH
		await expect(
			router
				.connect(bob)
				.swapETHForExactTokens(
					eth(100),
					[weth9.address, firebird.address],
					bob.address,
					constants.MaxUint256,
					{ value: eth(1000) }
				)
		).to.changeTokenBalances(
			firebird,
			[bob, firebird, pair],
			[eth(97), eth(3), eth(100).mul(-1)]
		);
	});
	it("should tax on sell", async function () {
		const { router, weth9, firebird, owner, bob, pair } = await loadFixture(
			deploy
		);

		// Send bob some tokens
		await firebird.transfer(bob.address, eth(100));

		firebird.connect(bob).approve(router.address, constants.MaxUint256);
		// since we have a fee, we must call SupportingFeeOnTransferTokens
		await expect(
			router
				.connect(bob)
				.swapExactTokensForETHSupportingFeeOnTransferTokens(
					eth(100),
					1,
					[firebird.address, weth9.address],
					bob.address,
					constants.MaxUint256
				)
		).to.changeTokenBalances(
			firebird,
			[bob, firebird, pair],
			[eth(100).mul(-1), eth(3), eth(97)]
		);
	});
	it("shouldn't tax on transfer", async function () {
		const { firebird, bob, alice } = await loadFixture(deploy);

		// Send bob some tokens
		await firebird.transfer(bob.address, eth(100));

		await expect(
			firebird.connect(bob).transfer(alice.address, eth(100))
		).to.changeTokenBalances(
			firebird,
			[bob, alice, firebird],
			[eth(100).mul(-1), eth(100), 0]
		);
	});

	it("should revert when transferring to zero address", async function () {
		const { firebird } = await loadFixture(deploy);
		await expect(
			firebird.transfer(constants.AddressZero, eth(1))
		).to.be.revertedWith("ERC20: transfer to the zero address");
	});

	it("should revert when transferring zero tokens", async function () {
		const { firebird, bob } = await loadFixture(deploy);
		await expect(firebird.transfer(bob.address, 0)).to.be.revertedWith(
			"ERC20: Transfer amount must be greater than zero"
		);
	});

	// it("should burn tokens based on tweet count", async function () {
	// 	// Set up oracle request and fulfilment
	// 	// Get link token address
	// 	await linkToken.transfer(dummyOracle, 1000000000000000000); // Transfer some LINK to oracle

	// 	const jobId = ethers.utils.formatBytes32String("dummyJobId");
	// 	const tweetCount = 500;
	// 	const requestTx = await firebird.requestTweetCount(jobId, 0);
	// 	const requestReceipt = await requestTx.wait();
	// 	const requestId = requestReceipt.events[0].args[0];
	// 	await firebird.fulfill(requestId, tweetCount);

	// 	// Check burned tokens
	// 	const burnAmount = tweetCount > 100000 ? 100000 : tweetCount;
	// 	const burnTx = await firebird.connect(alice).burn(burnAmount);
	// 	const burnReceipt = await burnTx.wait();
	// 	const transferEvent = burnReceipt.events[0];
	// 	expect(transferEvent.event).to.equal("Transfer");
	// 	expect(transferEvent.args.from).to.equal(alice.address);
	// 	expect(transferEvent.args.to).to.equal(
	// 		"0x000000000000000000000000000000000000dEaD"
	// 	);
	// 	expect(transferEvent.args.value).to.equal(
	// 		burnAmount * 1000000000000000000
	// 	);
	// });
});
