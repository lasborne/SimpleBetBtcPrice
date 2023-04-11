# SimpleBetBtcPrice

This is a simple, modified version of Balajis smart contract (deployed to the polygon mainnet) where users are allowed to bet for or against the price of BTC on a future date (here, 15 May, 2023). Those who won at the expiration are all automatically paid back if any depositor calls the `settleBet` function. (Note, however, there is a minor bug detected in the contract which doesn't allow payment of gains, debugging was discontinued because of low gas). This will be corrected soon.

Try running some of the following tasks:

```shell
npx hardhat help
npx hardhat test
REPORT_GAS=true npx hardhat test
npx hardhat node
npx hardhat run scripts/deploy.js
```
