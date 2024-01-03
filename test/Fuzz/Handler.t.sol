//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {Test, console} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    ERC20Mock weth;
    ERC20Mock wbtc;
    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;
    uint256 public timesMintDscCalled;
    address[] public users;

    constructor(DecentralizedStableCoin _dsc, DSCEngine _dsce) {
        dsc = _dsc;
        dscEngine = _dsce;

        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    ///////////// Mint Dsc ////////////////////////
    function mintDsc(uint256 amountDscToMint, uint256 addressSeed) public {
        if (users.length == 0) {
            return;
        }
        address sender = users[addressSeed % users.length];

        (uint256 totalDscMinted, uint256 collateralValueInUSD) = dscEngine.getAccountInformation(sender);

        int256 maxDscToMint = (int256(collateralValueInUSD) / 2) - int256(totalDscMinted);

        if (maxDscToMint < 0) {
            return;
        }
        amountDscToMint = bound(amountDscToMint, 0, uint256(maxDscToMint));
        if (amountDscToMint == 0) {
            return;
        }

        vm.startPrank(sender);
        dscEngine.mintDsc(amountDscToMint);
        vm.stopPrank();
        timesMintDscCalled++;
    }

    ////////// depositCollateral Handler-Based fuzz testing////////////

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateralToken = _getCollateralTokenFromSeed(collateralSeed);

        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateralToken.mint(msg.sender, amountCollateral);
        collateralToken.approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(address(collateralToken), amountCollateral);
        vm.stopPrank();

        users.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateralToken = _getCollateralTokenFromSeed(collateralSeed);

        uint256 maxRedeemCollateral = dscEngine.getCollateralDeposited(msg.sender, address(collateralToken));

        if (amountCollateral == 0) {
            return;
        }
        if (maxRedeemCollateral < amountCollateral) {
            return;
        }
        amountCollateral = bound(amountCollateral, 0, maxRedeemCollateral);

        dscEngine.redeemCollateral(address(collateralToken), amountCollateral);
    }

    //  This function fluctuate the price of eth/btc so if our price goes down than it reverts over failure of executing other functions.

    // function updateCollateralPrice(uint96 newPrice, uint256 collateralSeed) public {
    //     ERC20Mock collateralToken = _getCollateralTokenFromSeed(collateralSeed);
    //     MockV3Aggregator priceFeed = MockV3Aggregator(dscEngine.getPriceFeeds(address(collateralToken)));
    //     priceFeed.updateAnswer(int256(uint256(newPrice)));
    // }

    /////////////////// Helper Functions/////////////////////////

    function _getCollateralTokenFromSeed(uint256 collateralSeed) public view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
