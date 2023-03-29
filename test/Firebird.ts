import { expect } from "chai";
import { Contract } from "ethers";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import compiledUniswapFactory from "@uniswap/v2-core/build/UniswapV2Factory.json";
import compiledUniswapRouter from "@uniswap/v2-periphery/build/UniswapV2Router02.json";
import compiledWeth from "@uniswap/v2-periphery/build/WETH9.json";
const { provider } = ethers;

describe("Firebird Token Contract", function () {
	let firebird: any,
		owner: SignerWithAddress,
		alice: SignerWithAddress,
		bob: SignerWithAddress,
		dummyOracle: SignerWithAddress,
		marketingWallet: SignerWithAddress,
		oracleWallet: SignerWithAddress,
		linkToken: Contract;

	before(async function () {
		// Get list of available accounts
		[owner, alice, bob, dummyOracle, marketingWallet, oracleWallet] =
			await ethers.getSigners();

		const uniswapFactory = await new ethers.ContractFactory(
			compiledUniswapFactory.interface,
			compiledUniswapFactory.bytecode,
			owner
		).deploy(await owner.address);

		const weth = await new ethers.ContractFactory(
			compiledWeth.interface,
			compiledWeth.bytecode,
			owner
		).deploy();

		const uniswapRouter = await new ethers.ContractFactory(
			compiledUniswapRouter.interface,
			compiledUniswapRouter.bytecode,
			owner
		).deploy(uniswapFactory.address, weth.address);

		// Deploy Link Token Contract
		const Link = await ethers.getContractFactory("LinkToken");
		const link = await Link.deploy();

		// Deploy Firebird Token Contract
		const Firebird = await ethers.getContractFactory("Firebird");
		firebird = await Firebird.deploy(
			10000000,
			marketingWallet.address,
			oracleWallet.address,
			uniswapRouter.address,
			link.address,
			dummyOracle.address,
			ethers.utils.formatBytes32String("dummyJobId"),
			1
		);
	});

	it("should have the correct name and symbol", async function () {
		const name = await firebird.name();
		expect(name).to.equal("Firebird");

		const symbol = await firebird.symbol();
		expect(symbol).to.equal("FBRD");
	});

	it("should mint intial supply to owner", async function () {
		const ownerBalance = await firebird.balanceOf(owner.address);
		expect(ownerBalance).to.equal(1000000000000000000000000000);
	});

	it("should burn tokens based on tweet count", async function () {
		// Set up oracle request and fulfilment
		// Get link token address
		await linkToken.transfer(dummyOracle, 1000000000000000000); // Transfer some LINK to oracle

		const jobId = ethers.utils.formatBytes32String("dummyJobId");
		const tweetCount = 500;
		const requestTx = await firebird.requestTweetCount(jobId, 0);
		const requestReceipt = await requestTx.wait();
		const requestId = requestReceipt.events[0].args[0];
		await firebird.fulfill(requestId, tweetCount);

		// Check burned tokens
		const burnAmount = tweetCount > 100000 ? 100000 : tweetCount;
		const burnTx = await firebird.connect(alice).burn(burnAmount);
		const burnReceipt = await burnTx.wait();
		const transferEvent = burnReceipt.events[0];
		expect(transferEvent.event).to.equal("Transfer");
		expect(transferEvent.args.from).to.equal(alice.address);
		expect(transferEvent.args.to).to.equal(
			"0x000000000000000000000000000000000000dEaD"
		);
		expect(transferEvent.args.value).to.equal(
			burnAmount * 1000000000000000000
		);
	});

	it("should update marketing wallet", async function () {
		await firebird.updateWalletMarketing(bob.address);
		const newMarketingWallet = await firebird.marketingWallet();
		expect(newMarketingWallet).to.equal(bob.address);
	});

	it("should update oracle wallet", async function () {
		await firebird.updateWalletOracle(bob.address);
		const newOracleWallet = await firebird.oracleWallet();
		expect(newOracleWallet).to.equal(bob.address);
	});

	it("should exclude and include an account from fees", async function () {
		// Exclude account
		await firebird.setExcludedFromFee(alice.address, true);
		const excluded = await firebird.isExcludedFromFee(alice.address);
		expect(excluded).to.equal(true);

		// Include account
		await firebird.setExcludedFromFee(alice.address, false);
		const included = await firebird.isExcludedFromFee(alice.address);
		expect(included).to.equal(false);
	});

	it("should transfer tokens from Alice to Bob with fees", async function () {
		const aliceBalanceBefore = await firebird.balanceOf(alice.address);
		const bobBalanceBefore = await firebird.balanceOf(bob.address);

		// Transfer tokens
		const transaction = await firebird
			.connect(alice)
			.transfer(bob.address, 1000000000000000000);
		const receipt = await transaction.wait();

		const aliceBalanceAfter = await firebird.balanceOf(alice);
		const bobBalanceAfter = await firebird.balanceOf(bob);

		// Check alice balance
		expect(aliceBalanceAfter).to.equal(
			aliceBalanceBefore - 1100000000000000000
		);

		// Check bob balance
		expect(bobBalanceAfter).to.equal(
			bobBalanceBefore + 1000000000000000000
		);
	});
});
