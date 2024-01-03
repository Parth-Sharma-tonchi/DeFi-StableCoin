//SPDX-License-Identifier:MIT

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/**
 * @title DSCEngine
 * @author Parth Sharma
 * @notice This contract is the core of DSC system. It handles all the logic for mining and redeeming DSC. This contract is very loosely based on the MakerDao DSS(DAI) System.
 *
 * This system is designed to have the token maintain a 1 token == $1.
 *
 * This stable coin have the properties:
 * -Exogenous Collateral
 * -Dollar Pegged
 * -Algorithmically Stable
 *
 * @notice This contract is the core of the DSC system. It handles all the logic for mining and redeeming DSC.
 * @notice This contract is loosely based on the MakerDAO DAI system.
 */

contract DSCEngine is ReentrancyGuard {
    /////////////////
    // Errors      //
    /////////////////
    error DSCEngine__ShouldBeMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorIsBroken(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk(uint256 healthFactor);
    error DSCEngine__HealthFactorNotImproved();

    /////////////////
    // types      //
    /////////////////
    using OracleLib for AggregatorV3Interface;

    ////////////////////
    // State Variables//
    ////////////////////
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DscMinted;
    address[] private s_collateralTokens;
    DecentralizedStableCoin private immutable i_dsc;

    uint256 private constant LIQUIDATION_THRESHOLD = 50; //it means the collateral should 200% overcollateralized;
    uint256 private constant LIOUIDATION_PRECISION = 100;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;

    /////////////////
    // Events      //
    /////////////////
    event CollateralDeposited(address indexed user, address indexed tokenAddress, uint256 indexed amount);
    event CollateralRedeemed(address indexed user, address indexed to, address indexed tokenAddress, uint256 amount);

    /////////////////
    // Modifier    //
    /////////////////
    modifier moreThanZero(uint256 collateralAmount) {
        if (collateralAmount == 0) {
            revert DSCEngine__ShouldBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    /////////////////
    // Functions   //
    /////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; ++i) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    //////////////////////////
    // External And public Function    //
    //////////////////////////
    /**
     * cd
     * @param tokenCollateralAddress The address of the token to deposit as collateral.
     * @param amountCollateral  The amount of collateral deposited by user.
     * @param amountDscToMint  The amount of decentralized stablecoin to mint
     * @notice This function allows user to deposit collateral and mint dsc in a single transaction.
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @param tokenCollateralAddress The address of the token to deposit as collateral.
     * @param amountCollateral  The amount of collateral to deposit
     */

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @param tokenCollateralAddress The address of collateral token to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @param amountDscToBurn The amount DSC to burn
     * @notice This function burns DSC and redeems underlying collateral in one transaction.
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    //In order to redeem collateral:
    // 1. Health factor must be over 1 After collateral pulled.
    // DRY: don't repeat yourself
    // CEI: checks, effects, interactions
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Follows CEI (Check, effects, Interactions).
     * @param amountDscMint The amount of Decentralized Stable coin to mint.
     * @notice They should have more collateral value than the minimum threshold.
     */
    function mintDsc(uint256 amountDscMint) public moreThanZero(amountDscMint) nonReentrant {
        s_DscMinted[msg.sender] += amountDscMint;

        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amountDscToBurn) public moreThanZero(amountDscToBurn) {
        _burnDsc(msg.sender, msg.sender, amountDscToBurn);
        _revertIfHealthFactorIsBroken(msg.sender); // don't think this would ever hit...
    }

    /**
     * @param collateralToken The erc20 collateral address to liquidate from the user
     * @param user Who broke the health factor. // is below MIN_HEALTH_FACTOR
     * @param debtToCover The amount of DSC you want to burn to improve the users health factor
     * @notice You can partially liquidate a user
     * @notice You will get a liquidation bonus for taking the users funds
     * @notice This function working assumes the protocol will be roughly 200% overcollateralized in order for this to work.
     * @notice A known bug would be if the protocol were 100% or less collateralized, then we wouldn't be able to incentive the liquidators.
     */
    function liquidate(address collateralToken, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        // need to check _healthFactor() of the user.
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk(startingUserHealthFactor);
        }

        // we want to burn their DSC "debt"
        // And take their collateral
        // USER: $140 ETH, $100 DSC
        // debt to cover: $100
        // $100 DSC == ?? ETH

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateralToken, debtToCover);

        //And give them a 10% bonus
        //so we are giving 110 WETH for 100 DSC to the liquidator.
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweep extra amount in treasury.

        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIOUIDATION_PRECISION;
        uint256 totalLiquidatorAmount = tokenAmountFromDebtCovered + bonusCollateral;

        _redeemCollateral(user, msg.sender, collateralToken, totalLiquidatorAmount);
        // We need to burn DSC here
        _burnDsc(msg.sender, user, debtToCover);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    ///////////////////////////////////////////
    // Internal and private view Function    //
    ///////////////////////////////////////////

    /**
     * @dev Low-Level internal function do not call unless the function calling it is checking
     * for health factor being broken.
     */
    function _burnDsc(address dscFrom, address onBehalfOf, uint256 amountDscToBurn) private {
        s_DscMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUSD)
    {
        totalDscMinted = s_DscMinted[user];
        collateralValueInUSD = getAccountCollateralValue(user);
    }

    /**
     * returns how close to liquidation a user is
     * If a user goes below 1, it can be liquidated.
     */
    function _healthFactor(address user) private view returns (uint256) {
        //total Dsc minted
        //total collateral value in USD.
        (uint256 totalDscMinted, uint256 collateralValueInUSD) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIOUIDATION_PRECISION;
        // $1000 ETH - $100 DSC
        // 1000*50 = 50000/100 = 500/100 > 1
        // So, here LIQUIDATION_THRESHOLD is 50 means 50 percent of collateral should more than total DSC minted.

        return ((collateralAdjustedForThreshold * PRECISION) / totalDscMinted);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // 1. Check Health Factor (do they have enough collateral value?)
        // 2. Revert If they don't have the good health factor
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsBroken(userHealthFactor);
        }
    }

    ////////////////////////////////////////
    // Public And External view functions //
    ////////////////////////////////////////

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUSD) {
        // loop through all collateral token, get amount they have deposited, and map it to
        // the price, to get USD value
        for (uint256 i = 0; i < s_collateralTokens.length; ++i) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUSD += getUSDValue(token, amount);
        }
        return totalCollateralValueInUSD;
    }

    function getUSDValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getTokenAmountFromUsd(address collateralToken, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[collateralToken]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountInformation(address user)
        public
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUSD)
    {
        (totalDscMinted, collateralValueInUSD) = _getAccountInformation(user);
    }

    function getPriceFeeds(address tokenAddress) public view returns (address) {
        return s_priceFeeds[tokenAddress];
    }

    function getCollateralTokens() public view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralToken(uint256 index) public view returns (address) {
        return s_collateralTokens[index];
    }

    function getCollateralDeposited(address owner, address tokenCollateralAddress) public view returns (uint256) {
        return s_collateralDeposited[owner][tokenCollateralAddress];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function calculateHealthFactor(uint256 amountDSC, uint256 amountCollateralInUSD) public pure returns (uint256) {
        uint256 collateralAdjustedForThreshold = (amountCollateralInUSD * LIQUIDATION_THRESHOLD) / LIOUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / amountDSC;
    }

    function getAdditionalFeedPrecision() public pure returns (uint256) {
        return 1e10;
    }

    function getPrecision() public pure returns (uint256) {
        return 1e18;
    }

    function getDscMinted(address user) public view returns (uint256) {
        return s_DscMinted[user];
    }
}
