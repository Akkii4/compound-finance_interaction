// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ICompound.sol";

/**
 * @title CompoundLiquidator
 * @dev This contract allows for the liquidation of collateralized loans on the Compound protocol.
 */
contract CompoundLiquidator {
    Comptroller public comptrollerContract =
        Comptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);

    IERC20 public borrowedToken;
    CERC20 public cTokenBorrowed;

    event Log(string message, uint val);

    /**
     * @dev Constructor function
     * @param _borrowedTokenAddress Address of the token to be borrowed
     * @param _cTokenBorrowedAddress Address of the cToken to be borrowed
     */
    constructor(address _borrowedTokenAddress, address _cTokenBorrowedAddress) {
        borrowedToken = IERC20(_borrowedTokenAddress);
        cTokenBorrowed = CERC20(_cTokenBorrowedAddress);
    }

    /**
     * @dev Returns the close factor (repayment portion percentage) of the Comptroller contract
     * @return The close factor
     */
    function getCloseFactor() external view returns (uint) {
        return comptrollerContract.closeFactorMantissa();
    }

    /**
     * @dev Returns the liquidation incentive of the Comptroller contract.
     * @return The liquidation incentive
     */
    function getLiquidationIncentive() external view returns (uint) {
        return comptrollerContract.liquidationIncentiveMantissa();
    }

    /**
     * @dev Calculates the amount of collateral to be liquidated.
     * @param _cTokenBorrowedAddress The address of the cToken to be borrowed
     * @param _cTokenCollateralAddress The address of the cToken collateral
     * @param _actualRepayAmount The amount to be repaid
     * @return The amount of collateral to be liquidated
     */
    function getAmountToBeLiquidated(
        address _cTokenBorrowedAddress,
        address _cTokenCollateralAddress,
        uint _actualRepayAmount
    ) external view returns (uint) {
        /*
         * Get the exchange rate and calculate the number of collateral tokens to seize:
         *  seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
         *  seizeTokens = seizeAmount / exchangeRate
         *   = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
         */
        (uint error, uint cTokenCollateralAmount) = comptrollerContract
            .liquidateCalculateSeizeTokens(
                _cTokenBorrowedAddress,
                _cTokenCollateralAddress,
                _actualRepayAmount
            );

        require(error == 0, "Error calculating seize tokens");

        return cTokenCollateralAmount;
    }

    /**
     * @dev Liquidates a borrower's position.
     * @param _borrowerAddress The address of the borrower's position to be liquidated
     * @param _repayAmount The amount to be repaid
     * @param _cTokenCollateralAddress The address of the cToken collateral
     */
    function liquidate(
        address _borrowerAddress,
        uint _repayAmount,
        address _cTokenCollateralAddress
    ) external {
        borrowedToken.transferFrom(msg.sender, address(this), _repayAmount);
        borrowedToken.approve(address(cTokenBorrowed), _repayAmount);

        require(
            cTokenBorrowed.liquidateBorrow(
                _borrowerAddress,
                _repayAmount,
                _cTokenCollateralAddress
            ) == 0,
            "Liquidation failed"
        );
    }

    /**
     * @dev Returns the amount of collateral that has been liquidated.
     * @param _cTokenCollateralAddress The address of the cToken collateral
     * @return The amount of collateral that has been liquidated
     */
    function getSupplyBalance(
        address _cTokenCollateralAddress
    ) external returns (uint) {
        return
            CERC20(_cTokenCollateralAddress).balanceOfUnderlying(address(this));
    }
}
