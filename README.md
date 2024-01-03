## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

Foundry DeFi Stablecoin
.

DSCEngine Example Decentralized Stablecoin Example

About
This project is meant to be a stablecoin where users can deposit WETH and WBTC in exchange for a token that will be pegged to the USD.

Foundry DeFi Stablecoin
About
Getting Started
Requirements
Quickstart
Optional Gitpod
Updates
Usage
Start a local node
Deploy
Deploy - Other Network
Testing
Test Coverage
Deployment to a testnet or mainnet
Scripts
Estimate gas
Formatting
Slither
Thank you!
Getting Started
Requirements
git
You'll know you did it right if you can run git --version and you see a response like git version x.x.x
foundry
You'll know you did it right if you can run forge --version and you see a response like forge 0.2.0 (816e00b 2023-03-16T00:05:26.396218Z)
Quickstart
git clone https://github.com/Cyfrin/foundry-defi-stablecoin-f23
cd foundry-defi-stablecoin-f23
forge build

Updates
The latest version of openzeppelin-contracts has changes in the ERC20Mock file. To follow along with the course, you need to install version 4.8.3 which can be done by forge install openzeppelin/openzeppelin-contracts@v4.8.3 --no-commit instead of forge install openzeppelin/openzeppelin-contracts --no-commit
Usage
Start a local node
make anvil
Deploy
This will default to your local node. You need to have it running in another terminal in order for it to deploy.

make deploy
Deploy - Other Network
See below

Testing
We talk about 4 test tiers in the video.

Unit
Integration
Forked
Staging
In this repo we cover #1 and Fuzzing.

forge test
Test Coverage
forge coverage
and for coverage based testing:

forge coverage --report debug
Deployment to a testnet or mainnet
Setup environment variables
You'll want to set your SEPOLIA_RPC_URL and PRIVATE_KEY as environment variables. You can add them to a .env file, similar to what you see in .env.example.

PRIVATE_KEY: The private key of your account (like from metamask). NOTE: FOR DEVELOPMENT, PLEASE USE A KEY THAT DOESN'T HAVE ANY REAL FUNDS ASSOCIATED WITH IT.
You can learn how to export it here.
SEPOLIA_RPC_URL: This is url of the sepolia testnet node you're working with. You can get setup with one for free from Alchemy
Optionally, add your ETHERSCAN_API_KEY if you want to verify your contract on Etherscan.

Get testnet ETH
Head over to faucets.chain.link and get some testnet ETH. You should see the ETH show up in your metamask.

Deploy
make deploy ARGS="--network sepolia"
Scripts
Instead of scripts, we can directly use the cast command to interact with the contract.

For example, on Sepolia:

Get some WETH
cast send 0xdd13E55209Fd76AfE204dBda4007C227904f0a81 "deposit()" --value 0.1ether --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
Approve the WETH
cast send 0xdd13E55209Fd76AfE204dBda4007C227904f0a81 "approve(address,uint256)" 0x091EA0838eBD5b7ddA2F2A641B068d6D59639b98 1000000000000000000 --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
Deposit and Mint DSC
cast send 0x091EA0838eBD5b7ddA2F2A641B068d6D59639b98 "depositCollateralAndMintDsc(address,uint256,uint256)" 0xdd13E55209Fd76AfE204dBda4007C227904f0a81 100000000000000000 10000000000000000 --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
Estimate gas
You can estimate how much gas things cost by running:

forge snapshot
And you'll see an output file called .gas-snapshot

Formatting
To run code formatting:

forge fmt
