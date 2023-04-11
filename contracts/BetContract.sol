// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';

interface AggregatorV3Interface {

    function decimals() external view returns (uint8);

    // latestRoundData should raise "No data present" if it does not have data to report,
    // instead of returning unset values which could be misinterpreted as actual reported values.

    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}

contract BetContract {
    using SafeMath for uint256;

    address immutable owner;
    address[] forAddresses;
    address[] againstAddresses;
    address[] _forAddresses;
    address[] _againstAddresses;

    IERC20 immutable WBTC;
    IERC20 immutable USDC;
    AggregatorV3Interface immutable priceFeed;
    AggregatorV3Interface immutable usdcPriceFeed;

    uint256 constant betThreshold = (3 * (10**10)); //30,000 USDC

    uint256 public lockTime = 1681516800; //Timestamp as of 15th April, 2023.
    uint256 public endTime = 1684065599; //Timestamp for 15th May, 2023.
    uint256 public totalBalanceFor;
    uint256 public totalBalanceAgainst;
    
    bool usdcDeposited;
    bool betInitiated;
    bool betLocked;
    bool for_;

    mapping(address => bool) public isDepositor;
    mapping(bool => mapping(address => uint256)) public depositorBalance;
    //User Betting For = 1, User Betting Against = 2, User with no bet = 0
    mapping(address => uint256) private isUserBettingFor;

    event BetInitiated(bool _betInitiated, address indexed balaji, address indexed anon, uint64 dueTime);
    event BetSettled(bool _betSettled, address indexed _betWinner, uint64 _time, uint256 settlementPrice);
    event BetCancelled(bool _betCancelled);

    constructor(
        address _wbtc, address _usdc, address _btcPriceFeed, address _usdcPriceFeed
    ) {

        priceFeed = AggregatorV3Interface(_btcPriceFeed);
        usdcPriceFeed = AggregatorV3Interface(_usdcPriceFeed);
        owner = msg.sender;

        WBTC = IERC20(_wbtc);
        USDC = IERC20(_usdc);
    }

    modifier onlyDeployer() {
        require(msg.sender == owner, "Must be Owner's Eth address!");
        _;
    }

    /**
     * @dev Deposit USDC.
     * An approve from the user must be called to allow this smart contract spend the token.
     *
     * Requirements:
     *
     * - `betInitiated` must be false.
     * - `amount` can not be zero.
     * - Approval must be gotten from user to spend USDC tokens.
     *
     * @notice Balaji deposits USDC, and the bet is initiated if Anon has deposited WBTC.
     *
     * Emits a {BetInitiated} event if both has deposited.
     */
    function depositUSDC(uint256 _amount, bool _for) external payable {
        if (block.timestamp > lockTime) {
            betLocked = true;
        }
        require(betLocked == false, "Betting has been locked up");
        require(_amount > 0, "The amount must be greater than zero");
        
        // Approve the transfer of USDC from Sender's wallet.
        USDC.transferFrom(msg.sender, address(this), _amount);
        depositorBalance[_for][msg.sender] += _amount;
        bool addressAlreadyIn;
        if (_for == true) {
            totalBalanceFor += _amount;
            for (uint256 i = 0; i < forAddresses.length; i++) {
                if (forAddresses[i] == msg.sender) {addressAlreadyIn = true;}
            }
            if (addressAlreadyIn == true) {} else {forAddresses.push(msg.sender);}
        } else {
            totalBalanceAgainst += _amount;
            for (uint256 i = 0; i < againstAddresses.length; i++) {
                if (againstAddresses[i] == msg.sender) {addressAlreadyIn = true;}
            }
            if (addressAlreadyIn == true) {} else {againstAddresses.push(msg.sender);}
        }
        usdcDeposited = true;
        isDepositor[msg.sender] = true;
        if (_for == true) {
            isUserBettingFor[msg.sender] = 1;
        } else {
            isUserBettingFor[msg.sender] = 2;
        }
    }

    /// @notice Bet can be cancelled if only one party has deposited and any of them decides to opt out.
    /// @notice Emits {BetCancelled} event.
    function cancelBeforeInitiation() external {
        if (block.timestamp > lockTime) {
            betLocked = true;
        }
        require(isDepositor[msg.sender] == true, "This address is not a valid depositor!");
        require(betLocked == false, "Cannot cancel, bet already locked in!");

        isDepositor[msg.sender] = false;
        bool isBetAddrFor;
        
        if (isUserBettingFor[msg.sender] == 1) {
            isBetAddrFor = true;
            
            for (uint256 i = 0; i < forAddresses.length; i++) {
                if (forAddresses[i] != msg.sender) {
                    _forAddresses.push(forAddresses[i]);
                }
            }
            forAddresses = _forAddresses;
            delete _forAddresses;
            totalBalanceFor -= depositorBalance[true][msg.sender];
        } else {
            isBetAddrFor = false;

            for (uint256 i = 0; i < againstAddresses.length; i++) {
                if (againstAddresses[i] != msg.sender) {
                    _againstAddresses.push(againstAddresses[i]);
                }
            }
            againstAddresses = _againstAddresses;
            delete _againstAddresses;
            totalBalanceAgainst -= depositorBalance[false][msg.sender];
        }
        USDC.transfer(msg.sender, depositorBalance[isBetAddrFor][msg.sender]);
        depositorBalance[isBetAddrFor][msg.sender] = 0;
        // Turn user back to a non-bet address
        isUserBettingFor[msg.sender] = 0;
        emit BetCancelled(true);
    }
    
    /**
     * @dev Transfer the funds to the winner of the bet.
     *
     * Requirements:
     *
     * - `betInitiated` must be true.
     * - Must be the due date or after.
     *
     * @notice If WBTC > 1000000, Balaji wins, else, Anon wins the bet.
     *
     * Emits a {BetSettled} event with the winner address.
     */
    function settleBet() external payable {
        //require(betInitiated == true, "There is no valid bet");
        require(isUserBettingFor[msg.sender] != 0, "This user is not a bet address");
        require(block.timestamp >= endTime, "Bet duration not elapsed");

        betInitiated = false;
        uint256 wbtcPrice = btcPriceInUSDC();

        if (wbtcPrice >= betThreshold) {
            for (uint256 i = 0; i < forAddresses.length; i++) {
                uint256 amountWon = totalBalanceAgainst.mul(
                    (depositorBalance[true][forAddresses[i]]).div(totalBalanceFor));
                USDC.transfer(forAddresses[i], (amountWon.add(depositorBalance[true][forAddresses[i]])));
                resetUser(forAddresses[i], true);
            }
            totalBalanceFor = 0;
            totalBalanceAgainst = 0;
            delete forAddresses;
            delete againstAddresses;
        } else {
            for (uint256 i = 0; i < againstAddresses.length; i++) {
                uint256 amountWon = totalBalanceFor.mul(
                    (depositorBalance[false][againstAddresses[i]]).div(totalBalanceAgainst));
                USDC.transfer(
                    againstAddresses[i], (amountWon.add(depositorBalance[false][againstAddresses[i]]))
                );
                resetUser(againstAddresses[i], false);    
            }
            totalBalanceFor = 0;
            totalBalanceAgainst = 0;
            delete againstAddresses;
            delete forAddresses;
        }

        emit BetSettled(true, msg.sender, uint64(block.timestamp), wbtcPrice);
    }

    /// @notice reset user after settling his/her debt.
    function resetUser(address _sender, bool _isFor) private {
        isDepositor[_sender] = false;
        depositorBalance[_isFor][_sender] = 0;
        isUserBettingFor[_sender] = 0;
    }

    /// @notice Get BTC price relative to USD from ChainLink oracle.
    function getBTCPriceFeed() public view returns(uint256) {
        (,int256 price,,,) = priceFeed.latestRoundData();
        return uint256(price);
    }

    /// @notice Get USDC price relatve to USD from ChainLink oracle.
    function getUSDCPriceFeed() public view returns(uint256) {
        (,int256 usdcPrice,,,) = usdcPriceFeed.latestRoundData();
        return uint256(usdcPrice);
    }

    /// @notice Calculate BTC price relatve to USDC.
    function btcPriceInUSDC() public view returns(uint256) {
        uint256 btcPriceFeed = getBTCPriceFeed();
        uint256 btcPrice = btcPriceFeed.div(getUSDCPriceFeed());
        return btcPrice;
    }

    fallback() external payable {
        if (totalBalanceFor > 0 && totalBalanceAgainst > 0) {
            if (block.timestamp >= lockTime) {
                betLocked = true;
            }
        } else {
            betLocked = false;
        }
    }
}