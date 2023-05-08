// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

/**
 * @title CompoundLong
 * @notice A smart contract that allows users to open and close leveraged long positions on ETH
 * @dev The contract interacts with Compound Finance and Uniswap to manage the long position
 */

/*Open ETH long position
1. Fund smart contract 
2. Borrow stablecoin 
3. Buy ETH

Close position when price increases
4. Sell ETH
5. Repay borrowed stablecoin
*/

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ICompound.sol";

interface IUniswapV2Router {
    function swapExactTokensForETH(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);
}

contract CompoundLong {
    CETH public cEth;
    CERC20 public cTokenBorrowAsset;
    IERC20 public stablecoin;
    uint public decimalPlaces;

    Comptroller public comptroller =
        Comptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);

    PriceFeed public priceOracle =
        PriceFeed(0x922018674c12a7F0D394ebEEf9B58F186CdE13c1);

    IUniswapV2Router private constant UNI_DEX =
        IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IERC20 private constant WETH =
        IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    /**
     * @notice Constructor initializes the contract with necessary addresses
     * @param _asset The address of the cETH token
     * @param _cTokenBorrowAsset The address of the cToken for the stablecoin being borrowed
     * @param _stablecoin The address of the stablecoin being borrowed
     * @param _decimalPlaces The number of decimal places for the stablecoin
     */
    constructor(
        address _asset,
        address _cTokenBorrowAsset,
        address _stablecoin,
        uint _decimalPlaces
    ) {
        cEth = CETH(_asset);
        cTokenBorrowAsset = CERC20(_cTokenBorrowAsset);
        stablecoin = IERC20(_stablecoin);
        decimalPlaces = _decimalPlaces;

        address[] memory supportedAssets = new address[](1);
        supportedAssets[0] = address(cEth);
        uint[] memory errors = comptroller.enterMarkets(supportedAssets);
        require(errors[0] == 0, "Entering market failed");
    }

    /// @notice Fallback function to receive Ether
    receive() external payable {}

    /**
     * @notice Fund the contract with ETH and mint cETH tokens
     */
    function fund() external payable {
        cEth.mint{value: msg.value}();
    }

    /**
     * @notice Get the maximum amount of stablecoin that can be borrowed
     * @return maxBorrow The maximum amount of stablecoin that can be borrowed
     */
    function getMaxBorrow() external view returns (uint) {
        (uint err, uint liquidity, uint shortfall) = comptroller
            .getAccountLiquidity(address(this));

        require(err == 0, "Error");
        require(shortfall == 0, "Shortfall>0");
        require(liquidity > 0, "Liquidity=0");

        uint price = priceOracle.getUnderlyingPrice(address(cTokenBorrowAsset));
        uint maxBorrow = (liquidity * (10 ** decimalPlaces)) / price;

        return maxBorrow;
    }

    /**
     * @notice Open a leveraged long position on ETH
     * @param _amountBorrowed The amount of stablecoin to borrow
     */
    function openPosition(uint _amountBorrowed) external {
        require(
            cTokenBorrowAsset.borrow(_amountBorrowed) == 0,
            "Borrow failed"
        );
        uint balance = stablecoin.balanceOf(address(this));
        stablecoin.approve(address(UNI_DEX), balance);

        address[] memory path = new address[](2);
        path[0] = address(stablecoin);
        path[1] = address(WETH);
        UNI_DEX.swapExactTokensForETH(
            balance,
            1,
            path,
            address(this),
            block.timestamp
        );
    }

    /**
     * @notice Close the leveraged long position on ETH
     */
    function closePosition() external {
        // Sell ETH
        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(stablecoin);
        UNI_DEX.swapExactETHForTokens{value: address(this).balance}(
            1,
            path,
            address(this),
            block.timestamp
        );

        // Repay borrowed amount
        uint borrowedAmount = cTokenBorrowAsset.borrowBalanceCurrent(
            address(this)
        );
        stablecoin.approve(address(cTokenBorrowAsset), borrowedAmount);
        require(
            cTokenBorrowAsset.repayBorrow(borrowedAmount) == 0,
            "Repay failed"
        );

        uint supplied = cEth.balanceOfUnderlying(address(this));
        require(cEth.redeemUnderlying(supplied) == 0, "Redeem failed");
    }

    /**
     * @notice Get the supplied balance of ETH in cETH tokens
     * @return The supplied balance of ETH in cETH tokens
     */
    function getSuppliedBalance() external returns (uint) {
        return cEth.balanceOfUnderlying(address(this));
    }

    /**
     * @notice Get the borrowed balance of stablecoin
     * @return The borrowed balance of stablecoin
     */
    function getBorrowedBalance() external returns (uint) {
        return cTokenBorrowAsset.borrowBalanceCurrent(address(this));
    }

    /**
     * @notice Get the account liquidity and shortfall
     * @return liquidity The account liquidity
     * @return shortfall The account shortfall
     */
    function getAccountLiquidity()
        external
        view
        returns (uint liquidity, uint shortfall)
    {
        (uint err, uint _liquidity, uint _shortfall) = comptroller
            .getAccountLiquidity(address(this));
        require(err == 0, "Error");
        return (_liquidity, _shortfall);
    }
}
