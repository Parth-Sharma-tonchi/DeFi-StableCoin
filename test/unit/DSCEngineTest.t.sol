//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {MockFailedMintDsc} from "../mocks/MockFailedMintDsc.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";

contract DSCEngineTest is Test {
    //Event
    event CollateralDeposited(address indexed user, address indexed tokenAddress, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed from, address indexed to, address indexed tokenCollateralAddress, uint256 amountToRedeemed
    );

    // State variables.
    DSCEngine public dscEngine;
    DecentralizedStableCoin public dsc;
    DeployDSC public deployer;
    HelperConfig public config;
    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;

    address public USER = makeAddr("user");
    uint256 public constant STARTING_USER_BALANCE = 100 ether;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_TO_MINT = 100;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        // if(block.chainid == 31337){
        vm.deal(USER, STARTING_USER_BALANCE);
        // }
    }

    //////////////////////
    //test constructor////
    //////////////////////

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testconstructor() public {
        //test both have same length or not.
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

        // Check state variables are updated or not.
        assert(dscEngine.getPriceFeeds(weth) != address(0));
        assertEq(dscEngine.getCollateralToken(0), weth);
    }

    //////////////////
    // Price tests ///
    //////////////////

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedValue = 30000e18;
        uint256 actualValue = dscEngine.getUSDValue(weth, ethAmount);
        assertEq(expectedValue, actualValue);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        // $2000/ETH => 100/2000 => 0.05
        uint256 expectedValue = 0.05 ether;
        uint256 actualValue = dscEngine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedValue, actualValue);
    }

    //////////////////////////////
    /// DepositCollateral tests///
    //////////////////////////////

    function testDepositCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        ////Check token allowed////
        // it reverts because address of collateral is not allowed.
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dscEngine.depositCollateral(address(0), 1 ether);

        ////Check amount////
        //it should revert because amount of collateral is zero.
        vm.expectRevert(DSCEngine.DSCEngine__ShouldBeMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
    }

    function testRevertsWithUnapprovedTokenCollateral() public {
        vm.startPrank(USER);
        ERC20Mock ranToken = new ERC20Mock();
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dscEngine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
        uint256 expectedDeposit = dscEngine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        console.log(expectedDeposit);
        assertEq(totalDscMinted, 0);
        assertEq(expectedDeposit, AMOUNT_COLLATERAL);
    }

    function testDepositCollateralEventEmitted() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, true, false);
        emit CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRevertsIfTransferFails() public {
        //Arrange - SetUp
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransferFrom mockDsc = new MockFailedTransferFrom();
        tokenAddresses = [address(mockDsc)];
        priceFeedAddresses = [ethUsdPriceFeed];
        vm.prank(owner);
        DSCEngine mockDscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));

        mockDsc.mint(USER, AMOUNT_COLLATERAL);

        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDscEngine));

        //Arrange - User
        vm.startPrank(USER);
        ERC20Mock(address(mockDsc)).approve(address(mockDscEngine), AMOUNT_COLLATERAL);

        // Assert
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDscEngine.depositCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    //////////////////////
    ///test mintDSC    ///
    //////////////////////

    modifier depositCollateralAndMintDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }

    function testDscAmountMoreThanZero() public depositCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__ShouldBeMoreThanZero.selector);
        dscEngine.mintDsc(0);
        vm.stopPrank();
    }

    function testDscMintedUpdated() public depositCollateralAndMintDsc {
        vm.startPrank(USER);
        (uint256 totalDscMinted,) = dscEngine.getAccountInformation(USER);
        assertEq(totalDscMinted, 100);
    }

    function testRevertsIfHealthFactorBrokenInMintDsc() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);

        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();

        uint256 amountToMint =
            (AMOUNT_COLLATERAL * (uint256(price) * dscEngine.getAdditionalFeedPrecision())) / dscEngine.getPrecision();

        console.log("AMOUNT TO MINT ", amountToMint);

        uint256 amountCollateralInUSD = dscEngine.getUSDValue(weth, AMOUNT_COLLATERAL);
        uint256 expectedHealthFactor = dscEngine.calculateHealthFactor(amountToMint, amountCollateralInUSD);
        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorIsBroken.selector, expectedHealthFactor)
        );
        dscEngine.mintDsc(amountToMint);
        vm.stopPrank();
    }

    function testRevertsIfMintFailed() public {
        // Arrange - SetUp
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedMintDsc mockDsc = new MockFailedMintDsc();
        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPriceFeed];

        vm.prank(owner);
        DSCEngine mockDscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));

        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDscEngine));

        // Arrange - User
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockDscEngine), AMOUNT_COLLATERAL);
        mockDscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        mockDscEngine.mintDsc(100);
        vm.stopPrank();
    }

    //////////////////////////////////////////
    //// test depositCollateralAndMintDSC ////
    ///////////////////////////////////// ////

    /**
     * @notice In above functions, we test each and every line of depositCollateral and * mintDsc function. So, here we only make sure that these functions are functioning * well in this combine test.
     */
    function testDepositCollateralAndMintDsc() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        uint256 amountToMintDSC = 100;
        dscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMintDSC);
        vm.stopPrank();
    }

    ///////////////////////////////
    ////Test Redeem Collateral/////
    ///////////////////////////////

    function testRedeemCollateralMoreThanZero() public depositCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__ShouldBeMoreThanZero.selector);
        dscEngine.redeemCollateral(weth, 0);
    }

    function testCollateralDepositedStateUpdatedOnRedeemCollateral() public depositCollateralAndMintDsc {
        vm.startPrank(USER);
        // Here if no DSC Minted than, in revertIfHealthFactorBroken It divides dscminted to collateral to find health factor and it throws an modulo error.
        dscEngine.redeemCollateral(weth, 100);
        assertEq(dscEngine.getCollateralDeposited(USER, weth), AMOUNT_COLLATERAL - 100);
        vm.stopPrank();
    }

    function testEventEmittedOnRedeemCollateral() public depositCollateralAndMintDsc {
        vm.startPrank(USER);
        // Here if no DSC Minted than, in revertIfHealthFactorBroken It divides dscminted to collateral to find health factor and it throws an modulo error.

        uint256 amountRedeemed = 100;

        vm.expectEmit(true, true, true, true);
        emit CollateralRedeemed(USER, USER, weth, amountRedeemed);
        dscEngine.redeemCollateral(weth, amountRedeemed);
    }

    function testRevertsIfTransferFailed() public depositCollateral {
        address owner = msg.sender;
        vm.startPrank(owner);
        MockFailedTransfer mockDsc = new MockFailedTransfer();
        tokenAddresses = [address(mockDsc)];
        priceFeedAddresses = [ethUsdPriceFeed];

        // vm.prank(owner);
        DSCEngine mockDscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));

        mockDsc.mint(USER, AMOUNT_COLLATERAL);

        // vm.prank(owner);
        mockDsc.transferOwnership(address(mockDscEngine));
        vm.stopPrank();

        vm.startPrank(USER);
        ERC20Mock(address(mockDsc)).approve(address(mockDscEngine), AMOUNT_COLLATERAL);
        mockDscEngine.depositCollateral(address(mockDsc), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDscEngine.redeemCollateral(address(mockDsc), AMOUNT_COLLATERAL);

        vm.stopPrank();
    }

    ////////////////////////////////
    //// test burn DSC function ////
    ////////////////////////////////

    function testCantBurnMoreThanUserHas() public {
        vm.startPrank(USER);
        vm.expectRevert();
        dscEngine.burnDsc(1);
        vm.stopPrank();
    }

    function testAmountShouldBeMoreThanZero() public depositCollateralAndMintDsc {
        // Arrange
        vm.startPrank(USER);
        // Act and Assert
        vm.expectRevert(DSCEngine.DSCEngine__ShouldBeMoreThanZero.selector);
        dscEngine.burnDsc(0);
        vm.stopPrank();
    }

    function testCanBurnDsc() public depositCollateralAndMintDsc {
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), 100);
        dscEngine.burnDsc(10);
        assertEq(dscEngine.getDscMinted(USER), 90);
        vm.stopPrank();
    }

    ////////////////////////////////////////
    ///// Test Liquidate Function //////////
    ////////////////////////////////////////

    function testRevertsIfDebtToCoverIsZero() public {
        address liquidator = address(1);
        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__ShouldBeMoreThanZero.selector);
        dscEngine.liquidate(weth, USER, 0);
        vm.stopPrank();
    }

    function testRevertIfUserHealthFactorNotOk() public depositCollateral {
        // uint256 collateralAmount = 1000;
        // vm.startPrank(USER);
        // ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        // dscEngine.depositCollateral(weth, collateralAmount);
        // vm.stopPrank();

        // (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        // uint256 amountCollateralInUSD =
        // (AMOUNT_COLLATERAL * (uint256(price) * dscEngine.getAdditionalFeedPrecision())) / dscEngine.getPrecision();

        uint256 dscToMint = 1000;
        vm.prank(USER);
        dscEngine.mintDsc(dscToMint);

        uint256 userHealthFactor = dscEngine.getHealthFactor(USER);
        address liquidator = address(1);
        vm.startPrank(liquidator);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorOk.selector, userHealthFactor));
        dscEngine.liquidate(weth, USER, 100);
        vm.stopPrank();
    }

    function testProperlyReportsHealthFactor() public depositCollateralAndMintDsc {
        uint256 expectedHealthFactor = 100 * 1e36; // Multiply by precision because in healthFactor function collateral value is calculated and given in precision form so we have to add precision here also.
        uint256 healthFactor = (dscEngine.getHealthFactor(USER));
        // $100 minted with $20,000 collateral at 50% liquidation threshold
        // means that we must have $200 collatareral at all times.
        // 20,000 * 0.5 = 10,000
        // 10,000 / 100 = 100 health factor
        assertEq(healthFactor, expectedHealthFactor);
    }

    function testGettokenAmountFromUsd() public depositCollateral {
        uint256 usdAmount = 2000;
        uint256 expectedValue = 1 ether;
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();

        uint256 actualValue = (usdAmount * 1e18) / (uint256(price) * 1e10) * 1e18;
        assertEq(actualValue, expectedValue);
    }
}
