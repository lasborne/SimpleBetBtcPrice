const {expect} = require('chai');
const {ethers} = require('hardhat');
const IERC20 = require("../artifacts/@openzeppelin/contracts/token/ERC20/IERC20.sol/IERC20.json")

describe('BetContract', () => {
    let deployer, for1, against1, against2, wbtcAddress, usdcAddress, btcPriceFeed, usdcPriceFeed
    let betContract, wbtcContract, usdcContract
    // WBTC & USDC addresses on Polygon
    wbtcAddress = '0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6'
    usdcAddress = '0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174'
    // ChainLink price feeds for the prices of BTC & USDC against the real-world fiat dollar
    btcPriceFeed = '0xc907E116054Ad103354f2D350FD2514433D57F6f'
    usdcPriceFeed = '0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7'
    
    beforeEach(async() => {
        [deployer, for1, against1, against2] = await ethers.getSigners()
        const BetContract = await ethers.getContractFactory('BetContract', deployer)

        // Deploy the betContract with arguments (Balaji's address, Anon's address, token addresses and pricefeed addresses).
        betContract = await BetContract.deploy(wbtcAddress, usdcAddress, btcPriceFeed, usdcPriceFeed)
        await betContract.deployed()
        console.log(betContract.address)

        // After contract has beeen deployed, attach the contract address and interact
        //betContract = BetContract.attach('0xCE5A8670F146010920874e3154984d5af75864d5')

        provider = ethers.provider
        wbtcContract = new ethers.Contract(wbtcAddress, IERC20.abi, provider)
        usdcContract = new ethers.Contract(usdcAddress, IERC20.abi, provider)
    })

    describe('Enables both parties to place their bets', () => {
        it('permits deposits of USDC', async() => {
            console.log(betContract.address)
            console.log(wbtcContract.address)
            console.log(usdcContract.address)

            // Approve the spending of 1 USDC token by for1, against1 and against2 addresses.
            await usdcContract.connect(for1).functions.approve(
                betContract.address, ethers.utils.parseEther('1')
            )
            expect(Number(
                await usdcContract.connect(for1).functions.allowance(for1.address, betContract.address)
            )).to.equal(Number(ethers.utils.parseEther('1')))
            await usdcContract.connect(against1).functions.approve(
                betContract.address, ethers.utils.parseEther('1')
            )
            expect(Number(await usdcContract.connect(against1).functions.allowance(
                    against1.address, betContract.address))).to.equal(Number(ethers.utils.parseEther('1')
                )
            )
            await usdcContract.connect(against2).functions.approve(
                betContract.address, ethers.utils.parseEther('1')
            )
            expect(Number(await usdcContract.connect(against2).functions.allowance(
                    against2.address, betContract.address))).to.equal(Number(ethers.utils.parseEther('1')
                )
            )
            
            // Deposit funds (0.01 USDC) into the smart contract
            await betContract.connect(for1).functions.depositUSDC(
                ethers.utils.parseEther('0.00000000000001'), true,
                {gasLimit: 300000, gasPrice: Number(await ethers.provider.getGasPrice())}
            )
            await betContract.connect(against1).functions.depositUSDC(
                ethers.utils.parseEther('0.00000000000001'), false,
                {gasLimit: 300000, gasPrice: Number(await ethers.provider.getGasPrice())}
            )
            await betContract.connect(against2).functions.depositUSDC(
                ethers.utils.parseEther('0.00000000000001'), false,
                {gasLimit: 300000, gasPrice: Number(await ethers.provider.getGasPrice())}
            )
            expect(await usdcContract.functions.balanceOf(betContract.address)).to.equal(
                ethers.utils.parseEther('0.00000000000001')
            )
            
            console.log(await betContract.getBTCPriceFeed())
            console.log(Number(await betContract.getUSDCPriceFeed()))
            console.log(Number(await betContract.btcPriceInUSDC()))

            // Cancel the bet if one party has not committed funds yet
            await betContract.connect(against1).functions.cancelBeforeInitiation({
                gasLimit: 300000, gasPrice: Number(ethers.utils.parseUnits('200', 'gwei'))
            })

            // Settle the debt after the time has elapsed.
            await betContract.connect(for1).functions.settleBet(
                {gasLimit: 300000, gasPrice: Number(await ethers.provider.getGasPrice())}
            )
            console.log(await usdcContract.functions.balanceOf(for1.address))
            console.log(await usdcContract.functions.balanceOf(against1.address))
            console.log(await usdcContract.functions.balanceOf(against2.address))
        })
    })
})