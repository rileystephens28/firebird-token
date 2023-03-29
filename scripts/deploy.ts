import { ethers } from "hardhat";

async function main() {
  const Firebird = await ethers.getContractFactory("Firebird");
  const fb = await Firebird.deploy();

  await fb.deployed();

  console.log(`Firebird was deployed to ${fb.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
