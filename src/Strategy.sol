// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ITermRepoToken} from "./interfaces/term/ITermRepoToken.sol";
import {ITermRepoServicer} from "./interfaces/term/ITermRepoServicer.sol";
import {ITermController} from "./interfaces/term/ITermController.sol";
import {ITermVaultEvents} from "./interfaces/term/ITermVaultEvents.sol";
import {ITermAuctionOfferLocker} from "./interfaces/term/ITermAuctionOfferLocker.sol";
import {ITermRepoCollateralManager} from "./interfaces/term/ITermRepoCollateralManager.sol";
import {ITermAuction} from "./interfaces/term/ITermAuction.sol";
import {RepoTokenList, RepoTokenListData} from "./RepoTokenList.sol";
import {TermAuctionList, TermAuctionListData, PendingOffer} from "./TermAuctionList.sol";
import {RepoTokenUtils} from "./RepoTokenUtils.sol";

/**
 * The `TokenizedStrategy` variable can be used to retrieve the strategies
 * specific storage data your contract.
 *
 *       i.e. uint256 totalAssets = TokenizedStrategy.totalAssets()
 *
 * This can not be used for write functions. Any TokenizedStrategy
 * variables that need to be updated post deployment will need to
 * come from an external call from the strategies specific `management`.
 */

// NOTE: To implement permissioned functions you can use the onlyManagement, onlyEmergencyAuthorized and onlyKeepers modifiers

contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using RepoTokenList for RepoTokenListData;
    using TermAuctionList for TermAuctionListData;

    error InvalidTermAuction(address auction);
    error TimeToMaturityAboveThreshold();
    error BalanceBelowLiquidityThreshold();
    
    ITermVaultEvents public immutable TERM_VAULT_EVENT_EMITTER;
    uint256 public immutable PURCHASE_TOKEN_PRECISION;
    IERC4626 public immutable YEARN_VAULT;

    ITermController public termController;
    RepoTokenListData public repoTokenListData;
    TermAuctionListData public termAuctionListData;
    uint256 public timeToMaturityThreshold; // seconds
    uint256 public liquidityThreshold;      // purchase token precision (underlying)
    uint256 public auctionRateMarkup;       // 1e18 (TODO: check this)

    function setTermController(address newTermController) external onlyManagement {
        TERM_VAULT_EVENT_EMITTER.emitTermControllerUpdated(address(termController), newTermController);
        termController = ITermController(newTermController);
    }

    function setTimeToMaturityThreshold(uint256 newTimeToMaturityThreshold) external onlyManagement {
        TERM_VAULT_EVENT_EMITTER.emitTimeToMaturityThresholdUpdated(timeToMaturityThreshold, newTimeToMaturityThreshold);
        timeToMaturityThreshold = newTimeToMaturityThreshold;
    }

    function setLiquidityThreshold(uint256 newLiquidityThreshold) external onlyManagement {
        TERM_VAULT_EVENT_EMITTER.emitLiquidityThresholdUpdated(liquidityThreshold, newLiquidityThreshold);
        liquidityThreshold = newLiquidityThreshold;
    }

    function setAuctionRateMarkup(uint256 newAuctionRateMarkup) external onlyManagement {
        TERM_VAULT_EVENT_EMITTER.emitAuctionRateMarkupUpdated(auctionRateMarkup, newAuctionRateMarkup);
        auctionRateMarkup = newAuctionRateMarkup;
    }

    function _removeRedeemAndCalculateWeightedMaturity(address repoToken, uint256 amount) private returns (uint256) {
        uint256 weightedTimeToMaturity = repoTokenListData.getWeightedTimeToMaturity(
            repoToken, amount, PURCHASE_TOKEN_PRECISION, _assetBalance()
        );
        repoTokenListData.removeAndRedeemMaturedTokens(repoToken, amount);
        return weightedTimeToMaturity;
    }

    function getWeightedTimeToMaturity(address repoToken, uint256 amount) external view returns (uint256) {
        return repoTokenListData.getWeightedTimeToMaturity(
            repoToken, amount, PURCHASE_TOKEN_PRECISION, _assetBalance()
        );
    }

    function _totalLiquidBalance(address addr) private view returns (uint256) {
        uint256 underlyingBalance = IERC20(asset).balanceOf(address(this));
        return _assetBalance() + underlyingBalance;
    }

    function _sweepAsset() private {
        uint256 underlyingBalance = IERC20(asset).balanceOf(address(this));
        if (underlyingBalance > 0) {
            YEARN_VAULT.deposit(underlyingBalance, address(this));
        }
    }

    function _withdrawAsset(uint256 amount) private {
        YEARN_VAULT.withdraw(YEARN_VAULT.convertToShares(amount), address(this), address(this));
    }

    function _assetBalance() private view returns (uint256) {
        return YEARN_VAULT.convertToAssets(YEARN_VAULT.balanceOf(address(this)));
    }

    // TODO: reentrancy check
    function sellRepoToken(address repoToken, uint256 repoTokenAmount) external {
        (uint256 auctionRate, uint256 redemptionTimestamp) = repoTokenListData.validateAndInsertRepoToken(
            ITermRepoToken(repoToken),
            termController,
            address(asset)
        );

        _sweepAsset();

        uint256 resultingTimeToMaturity = _removeRedeemAndCalculateWeightedMaturity(repoToken, repoTokenAmount);

        if (resultingTimeToMaturity > timeToMaturityThreshold) {
            revert TimeToMaturityAboveThreshold();
        }

        uint256 liquidBalance = _totalLiquidBalance(address(this));
        uint256 repoTokenPrecision = 10**ERC20(repoToken).decimals();
        uint256 proceeds = RepoTokenUtils.calculateProceeds(
            repoTokenAmount, redemptionTimestamp, repoTokenPrecision, PURCHASE_TOKEN_PRECISION, auctionRate
        );

        liquidBalance -= proceeds;

        if (liquidBalance < liquidityThreshold) {
            revert BalanceBelowLiquidityThreshold();
        }

        _withdrawAsset(proceeds);
        
        IERC20(repoToken).safeTransferFrom(msg.sender, address(this), repoTokenAmount);
        IERC20(asset).safeTransfer(msg.sender, proceeds);
    }

    function offerOnNewAuction(
        address termAuction,
        address repoToken,
        bytes32 idHash,
        bytes32 offerPriceHash,
        uint256 purchaseTokenAmount
    ) external onlyManagement returns (bytes32[] memory offerIds) {
        require(purchaseTokenAmount > 0);

        if (!termController.isTermDeployed(termAuction)) {
            revert InvalidTermAuction(termAuction);
        }

        ITermAuction auction = ITermAuction(termAuction);

        require(auction.termRepoId() == ITermRepoToken(repoToken).termRepoId());

        _sweepAsset();

        uint256 repoTokenPrecision = 10**ERC20(repoToken).decimals();
        uint256 resultingTimeToMaturity = _removeRedeemAndCalculateWeightedMaturity(
            repoToken, 
            RepoTokenUtils.purchaseToRepoPrecision(repoTokenPrecision, PURCHASE_TOKEN_PRECISION, purchaseTokenAmount)
        );

        if (resultingTimeToMaturity > timeToMaturityThreshold) {
            revert TimeToMaturityAboveThreshold();
        }

        ITermAuctionOfferLocker offerLocker = ITermAuctionOfferLocker(auction.termAuctionOfferLocker());
        require(offerLocker.purchaseToken() == address(asset), "Wrong purchase token");
        require(
            block.timestamp > offerLocker.auctionStartTime()
                || block.timestamp < auction.auctionEndTime(),
            "Auction not open"
        );

        uint256 liquidBalance = _totalLiquidBalance(address(this));

        if ((liquidBalance - purchaseTokenAmount) < liquidityThreshold) {
            revert BalanceBelowLiquidityThreshold();
        }

        ITermRepoServicer repoServicer = ITermRepoServicer(offerLocker.termRepoServicer());
        ITermAuctionOfferLocker.TermAuctionOfferSubmission memory offer;

        offer.id = idHash;
        offer.offeror = address(this);
        offer.offerPriceHash = offerPriceHash;
        offer.amount = purchaseTokenAmount;
        offer.purchaseToken = address(asset);

        ITermAuctionOfferLocker.TermAuctionOfferSubmission[] memory offerSubmissions = 
            new ITermAuctionOfferLocker.TermAuctionOfferSubmission[](1);
        offerSubmissions[0] = offer;

        _withdrawAsset(purchaseTokenAmount);

        ERC20(asset).approve(address(repoServicer.termRepoLocker()), purchaseTokenAmount);

        offerIds = offerLocker.lockOffers(offerSubmissions);

        require(offerIds.length > 0);

        termAuctionListData.insertPending(PendingOffer({
            offerId: offerIds[0],
            repoToken: repoToken,
            offerAmount: purchaseTokenAmount,
            termAuction: auction,
            offerLocker: offerLocker
        }));
    }

    function auctionClosed() external {
        termAuctionListData.removeCompleted(repoTokenListData, termController, address(asset));

        _sweepAsset();
    }

    function totalAssetValue() internal view returns (uint256 totalValue) {
        return _totalLiquidBalance(address(this)) + 
            repoTokenListData.getPresentValue(PURCHASE_TOKEN_PRECISION) + 
            termAuctionListData.getPresentValue(repoTokenListData);
    }

    constructor(
        address _asset,
        string memory _name,
        address _yearnVault,
        address _eventEmitter
    ) BaseStrategy(_asset, _name) {
        YEARN_VAULT = IERC4626(_yearnVault);
        TERM_VAULT_EVENT_EMITTER = ITermVaultEvents(_eventEmitter);
        PURCHASE_TOKEN_PRECISION = 10**ERC20(asset).decimals();

        IERC20(_asset).safeApprove(_yearnVault, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Can deploy up to '_amount' of 'asset' in the yield source.
     *
     * This function is called at the end of a {deposit} or {mint}
     * call. Meaning that unless a whitelist is implemented it will
     * be entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * @param _amount The amount of 'asset' that the strategy can attempt
     * to deposit in the yield source.
     */
    function _deployFunds(uint256 _amount) internal override {
        // TODO: implement deposit logic EX:
        //
        //      lendingPool.deposit(address(asset), _amount ,0);
    }

    /**
     * @dev Should attempt to free the '_amount' of 'asset'.
     *
     * NOTE: The amount of 'asset' that is already loose has already
     * been accounted for.
     *
     * This function is called during {withdraw} and {redeem} calls.
     * Meaning that unless a whitelist is implemented it will be
     * entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * Should not rely on asset.balanceOf(address(this)) calls other than
     * for diff accounting purposes.
     *
     * Any difference between `_amount` and what is actually freed will be
     * counted as a loss and passed on to the withdrawer. This means
     * care should be taken in times of illiquidity. It may be better to revert
     * if withdraws are simply illiquid so not to realize incorrect losses.
     *
     * @param _amount, The amount of 'asset' to be freed.
     */
    function _freeFunds(uint256 _amount) internal override {
        // TODO: implement withdraw logic EX:
        //
        //      lendingPool.withdraw(address(asset), _amount);
    }

    /**
     * @dev Internal function to harvest all rewards, redeploy any idle
     * funds and return an accurate accounting of all funds currently
     * held by the Strategy.
     *
     * This should do any needed harvesting, rewards selling, accrual,
     * redepositing etc. to get the most accurate view of current assets.
     *
     * NOTE: All applicable assets including loose assets should be
     * accounted for in this function.
     *
     * Care should be taken when relying on oracles or swap values rather
     * than actual amounts as all Strategy profit/loss accounting will
     * be done based on this returned value.
     *
     * This can still be called post a shutdown, a strategist can check
     * `TokenizedStrategy.isShutdown()` to decide if funds should be
     * redeployed or simply realize any profits/losses.
     *
     * @return _totalAssets A trusted and accurate account for the total
     * amount of 'asset' the strategy currently holds including idle funds.
     */
    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        // TODO: Implement harvesting logic and accurate accounting EX:
        //
        //      if(!TokenizedStrategy.isShutdown()) {
        //          _claimAndSellRewards();
        //      }
        //      _totalAssets = aToken.balanceOf(address(this)) + asset.balanceOf(address(this));
        //
        _totalAssets = asset.balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                    OPTIONAL TO OVERRIDE BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the max amount of `asset` that can be withdrawn.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overridden by strategists.
     *
     * This function will be called before any withdraw or redeem to enforce
     * any limits desired by the strategist. This can be used for illiquid
     * or sandwichable strategies.
     *
     *   EX:
     *       return asset.balanceOf(yieldSource);
     *
     * This does not need to take into account the `_owner`'s share balance
     * or conversion rates from shares to assets.
     *
     * @param . The address that is withdrawing from the strategy.
     * @return . The available amount that can be withdrawn in terms of `asset`
     */
    function availableWithdrawLimit(
        address /*_owner*/
    ) public view override returns (uint256) {
        // NOTE: Withdraw limitations such as liquidity constraints should be accounted for HERE
        //  rather than _freeFunds in order to not count them as losses on withdraws.

        // TODO: If desired implement withdraw limit logic and any needed state variables.

        // EX:
        // if(yieldSource.notShutdown()) {
        //    return asset.balanceOf(address(this)) + asset.balanceOf(yieldSource);
        // }
        return asset.balanceOf(address(this));
    }

    /**
     * @notice Gets the max amount of `asset` that an address can deposit.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overridden by strategists.
     *
     * This function will be called before any deposit or mints to enforce
     * any limits desired by the strategist. This can be used for either a
     * traditional deposit limit or for implementing a whitelist etc.
     *
     *   EX:
     *      if(isAllowed[_owner]) return super.availableDepositLimit(_owner);
     *
     * This does not need to take into account any conversion rates
     * from shares to assets. But should know that any non max uint256
     * amounts may be converted to shares. So it is recommended to keep
     * custom amounts low enough as not to cause overflow when multiplied
     * by `totalSupply`.
     *
     * @param . The address that is depositing into the strategy.
     * @return . The available amount the `_owner` can deposit in terms of `asset`
     *
    function availableDepositLimit(
        address _owner
    ) public view override returns (uint256) {
        TODO: If desired Implement deposit limit logic and any needed state variables .
        
        EX:    
            uint256 totalAssets = TokenizedStrategy.totalAssets();
            return totalAssets >= depositLimit ? 0 : depositLimit - totalAssets;
    }
    */

    /**
     * @dev Optional function for strategist to override that can
     *  be called in between reports.
     *
     * If '_tend' is used tendTrigger() will also need to be overridden.
     *
     * This call can only be called by a permissioned role so may be
     * through protected relays.
     *
     * This can be used to harvest and compound rewards, deposit idle funds,
     * perform needed position maintenance or anything else that doesn't need
     * a full report for.
     *
     *   EX: A strategy that can not deposit funds without getting
     *       sandwiched can use the tend when a certain threshold
     *       of idle to totalAssets has been reached.
     *
     * This will have no effect on PPS of the strategy till report() is called.
     *
     * @param _totalIdle The current amount of idle funds that are available to deploy.
     *
    function _tend(uint256 _totalIdle) internal override {}
    */

    /**
     * @dev Optional trigger to override if tend() will be used by the strategy.
     * This must be implemented if the strategy hopes to invoke _tend().
     *
     * @return . Should return true if tend() should be called by keeper or false if not.
     *
    function _tendTrigger() internal view override returns (bool) {}
    */

    /**
     * @dev Optional function for a strategist to override that will
     * allow management to manually withdraw deployed funds from the
     * yield source if a strategy is shutdown.
     *
     * This should attempt to free `_amount`, noting that `_amount` may
     * be more than is currently deployed.
     *
     * NOTE: This will not realize any profits or losses. A separate
     * {report} will be needed in order to record any profit/loss. If
     * a report may need to be called after a shutdown it is important
     * to check if the strategy is shutdown during {_harvestAndReport}
     * so that it does not simply re-deploy all funds that had been freed.
     *
     * EX:
     *   if(freeAsset > 0 && !TokenizedStrategy.isShutdown()) {
     *       depositFunds...
     *    }
     *
     * @param _amount The amount of asset to attempt to free.
     *
    function _emergencyWithdraw(uint256 _amount) internal override {
        TODO: If desired implement simple logic to free deployed funds.

        EX:
            _amount = min(_amount, aToken.balanceOf(address(this)));
            _freeFunds(_amount);
    }

    */
}
