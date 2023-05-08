// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ICompound.sol";

/**
 * @title CompoundInteraction
 * @dev This contract interacts with the Compound protocol to lend and borrow tokens.
 */
contract CompoundInteraction {
    IERC20 public baseToken; // lending token
    CERC20 public cTokenInstance; // token lender gets back for lending
    CETH public cETHTokenInstance;

    event LogAction(string message, uint val);

    receive() external payable {}

    function depositETH() external payable {
        cETHTokenInstance.mint{value: msg.value}();
    }

    constructor(address _baseToken, address _cTokenInstance) {
        baseToken = IERC20(_baseToken);
        cTokenInstance = CERC20(_cTokenInstance);
        cETHTokenInstance = CETH(_cTokenInstance);
    }

    /**
     * @dev Lend token to the Compound protocol and mint cTokens in return.
     * @param _amount The amount of token to lend.
     */
    function depositToken(uint _amount) external {
        baseToken.transferFrom(msg.sender, address(this), _amount);
        baseToken.approve(address(cTokenInstance), _amount);
        require(cTokenInstance.mint(_amount) == 0, "Mint failed");
    }

    /**
     * @dev Get the balance of cTokens held by this contract.
     */
    function getCTokenBalance() external view returns (uint) {
        return cTokenInstance.balanceOf(address(this));
    }

    /**
     * @dev Get the current exchange rate and supply rate per block of the cTokens held by this contract.
     * @return exchangeRate The current exchange rate from cToken to underlying token.
     * @return depositRate The current Interest supply rate per block of the cTokens.
     */
    function getDetails()
        external
        returns (uint exchangeRate, uint depositRate)
    {
        exchangeRate = cTokenInstance.exchangeRateCurrent();
        depositRate = cTokenInstance.supplyRatePerBlock();
    }

    /**
     * @dev Calculated and return the amount of underlying token this contract has supplied to the Compound
     * @return The balance of underlying tokens.
     */
    function underlyingTokenBalance() external returns (uint) {
        return cTokenInstance.balanceOfUnderlying(address(this));
    }

    /**
     * @dev Redeem cTokens and get back underlying tokens.
     * @param _cTokenAmount The amount of cToken to redeem.
     */
    function redeem(uint _cTokenAmount) external {
        require(cTokenInstance.redeem(_cTokenAmount) == 0, "redeem failed");
    }

    Comptroller public comptrollerInterface =
        Comptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);

    PriceFeed public feedInterface =
        PriceFeed(0x922018674c12a7F0D394ebEEf9B58F186CdE13c1);

    /**
     * @dev Get the collateral factor percentage(18 decimal format) of the cToken held by this contract.
     * @return The collateral factor.
     */
    function getCollateralFactor() external view returns (uint) {
        (, uint colFactor, ) = comptrollerInterface.markets(
            address(cTokenInstance)
        );
        return colFactor;
    }

    /**
     * @dev Get the account liquidity of this contract.
     * @return liquidity in USD that we can borrow upto.
     * @return shortfall The shortfall of the account, if any.
     */
    function getAccountLiquidity()
        external
        view
        returns (uint liquidity, uint shortfall)
    {
        (uint error, uint _liquidity, uint _shortfall) = comptrollerInterface
            .getAccountLiquidity(address(this));
        require(error == 0, "error");
        // normal circumstance - liquidity > 0 and shortfall == 0
        // liquidity > 0 means account can borrow up to `liquidity`
        // shortfall > 0 you borrowed over limit and can be liquidated,
        return (_liquidity, _shortfall);
    }

    /**
     * @dev Gets the price of the token of the token borrowing given the cToken.
     * @param _cToken The cToken address.
     * @return The price of the underlying token.
     */
    function getTokenPrice(address _cToken) external view returns (uint) {
        return feedInterface.getUnderlyingPrice(_cToken);
    }

    /**
     * @dev Borrow tokens from the Compound protocol.
     * @param _cTokenToBorrow The cToken to borrow.
     * @param _decimals The decimals of the token to borrow.
     */
    function takeLoan(address _cTokenToBorrow, uint _decimals) external {
        address[] memory cTokensList = new address[](1);
        cTokensList[0] = address(cTokenInstance);
        // entering the market for borrowing multiple asset type
        uint[] memory errors = comptrollerInterface.enterMarkets(cTokensList);
        require(errors[0] == 0, "Entering Markets failed");

        // check liquidity
        (uint error, uint liquidity, uint shortfall) = comptrollerInterface
            .getAccountLiquidity(address(this));
        require(error == 0, "error");
        require(shortfall == 0, "Borrowed over limit");
        require(liquidity > 0, "No liquidity");

        uint price = feedInterface.getUnderlyingPrice(_cTokenToBorrow);

        //calculating max loan
        uint maxBorrow = (liquidity * (10 ** _decimals)) / price;
        require(maxBorrow > 0, "No token to borrow");

        uint amount = (maxBorrow * 70) / 100; // borrowing 70% of max borrow
        require(CERC20(_cTokenToBorrow).borrow(amount) == 0, "borrow failed");
    }

    /**
     * @dev Get the total borrowed balance by the borrower(here this address) of the given cToken
     * @param _cTokenBorrowed The cToken from which the balance is to be retrieved.
     * @return The total borrowed token balance including the interest accumulated
     */
    function getLoanBalance(address _cTokenBorrowed) public returns (uint) {
        return CERC20(_cTokenBorrowed).borrowBalanceCurrent(address(this));
    }

    /**
     * @dev Get the current borrow rate per block of the given cToken.
     * @param _cTokenBorrowed The cToken from which the borrow rate is to be retrieved.
     * @return The current borrow rate per block.
     */
    function getLoanRatePerBlock(
        address _cTokenBorrowed
    ) external view returns (uint) {
        // scaled up by 1e18
        return CERC20(_cTokenBorrowed).borrowRatePerBlock();
    }

    /**
     * @dev Repay borrowed tokens.
     * @param _tokenBorrowed The borrowed token to be repaid.
     * @param _cTokenBorrowed The cToken from which the token was borrowed.
     * @param _amount The amount to repay. Use 2 ** 256 - 1 to repay all.
     */
    function repayLoan(
        address _tokenBorrowed,
        address _cTokenBorrowed,
        uint _amount
    ) external {
        IERC20(_tokenBorrowed).approve(_cTokenBorrowed, _amount);
        // _amount = 2 ** 256 - 1 means repay all
        require(
            CERC20(_cTokenBorrowed).repayBorrow(_amount) == 0,
            "Loan repayment failed"
        );
    }
}
