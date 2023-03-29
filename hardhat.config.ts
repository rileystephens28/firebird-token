import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-ignore-warnings";

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
