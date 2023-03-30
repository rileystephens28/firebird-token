import { HardhatUserConfig } from "hardhat/config";
import "hardhat-ignore-warnings";
import "@nomicfoundation/hardhat-toolbox";
import "@onmychain/hardhat-uniswap-v2-deploy-plugin";

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.4.24",
      },
      {
        version: "0.8.18",
      },
    ],
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
    },
    localhost: {
      allowUnlimitedContractSize: true,
    },
  },
  warnings: "off",
};

export default config;
