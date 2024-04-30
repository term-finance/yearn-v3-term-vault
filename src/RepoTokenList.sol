// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {ITermRepoToken} from "./interfaces/term/ITermRepoToken.sol";
import {ITermRepoServicer} from "./interfaces/term/ITermRepoServicer.sol";
import {ITermController, TermAuctionResults} from "./interfaces/term/ITermController.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {RepoTokenUtils} from "./RepoTokenUtils.sol";

struct RepoTokenListNode {
    address next;
}

struct RepoTokenListData {
    address head;
    mapping(address => RepoTokenListNode) nodes;
    mapping(address => uint256) auctionRates;
}

library RepoTokenList {
    address public constant NULL_NODE = address(0);
    uint256 internal constant INVALID_AUCTION_RATE = 0;

    error InvalidRepoToken(address token);

    function _getRepoTokenMaturity(address repoToken) private view returns (uint256 redemptionTimestamp) {
        (redemptionTimestamp, , ,) = ITermRepoToken(repoToken).config();
    }

    function _getRepoTokenTimeToMaturity(address repoToken) private view returns (uint256) {
        return _getRepoTokenMaturity(repoToken) - block.timestamp;
    }

    function _getNext(RepoTokenListData storage listData, address current) private view returns (address) {
        return listData.nodes[current].next;
    }

    function getWeightedTimeToMaturity(
        RepoTokenListData storage listData, 
        address repoToken, 
        uint256 repoTokenAmount,
        uint256 purchaseTokenPrecision,
        uint256 purchaseTokenBalance
    ) internal view returns (uint256) {
        if (listData.head == NULL_NODE) return 0;

        uint256 repoTokenPrecision = 10**ERC20(repoToken).decimals();

        uint256 cumulativeWeightedMaturityTimestamp;
        uint256 cumulativeRepoTokenAmount;
        address current = listData.head;
        while (current != NULL_NODE) {
            uint256 currentMaturity = _getRepoTokenMaturity(current);
            uint256 repoTokenBalance = ITermRepoToken(current).balanceOf(address(this));

            if (currentMaturity > block.timestamp) {
                uint256 timeToMaturity = _getRepoTokenTimeToMaturity(current);
                // Not matured yet
                cumulativeWeightedMaturityTimestamp += timeToMaturity * repoTokenBalance / repoTokenPrecision;
            }
            cumulativeRepoTokenAmount += repoTokenBalance;

            current = _getNext(listData, current);
        }

        if (repoToken != address(0)) {
            cumulativeWeightedMaturityTimestamp += _getRepoTokenTimeToMaturity(repoToken) * repoTokenAmount;
            cumulativeRepoTokenAmount += repoTokenAmount;
        }

        uint256 excessLiquidity = purchaseTokenBalance * repoTokenPrecision / purchaseTokenPrecision;

        /// @dev avoid div by 0
        if (cumulativeRepoTokenAmount == 0 && excessLiquidity == 0) {
            return 0;
        }

        return cumulativeWeightedMaturityTimestamp * repoTokenPrecision / (cumulativeRepoTokenAmount + excessLiquidity);
    }

    function removeAndRedeemMaturedTokens(
        RepoTokenListData storage listData, 
        address repoServicer, 
        uint256 amount
    ) internal {
        if (listData.head == NULL_NODE) return;

        address current = listData.head;
        address prev = current;
        while (current != NULL_NODE) {
            address next;

            if (_getRepoTokenMaturity(current) >= block.timestamp) {
                next = _getNext(listData, current);

                if (current == listData.head) {
                    listData.head = next;
                }
                
                listData.nodes[prev].next = next;
                delete listData.nodes[current];
                delete listData.auctionRates[current];

                ITermRepoServicer(repoServicer).redeemTermRepoTokens(address(this), amount);
            } else {
                /// @dev early exit because list is sorted
                break;
            }

            prev = current;
            current = next;
        }        
    }

    function _auctionRate(ITermController termController, ITermRepoToken repoToken) private view returns (uint256) {
        TermAuctionResults memory results = termController.getTermAuctionResults(repoToken.termRepoId());

        uint256 len = results.auctionMetadata.length;

        require(len > 0);

        return results.auctionMetadata[len - 1].auctionClearingRate;
    }

    function validateAndInsertRepoToken(
        RepoTokenListData storage listData, 
        ITermRepoToken repoToken,
        ITermController termController,
        address asset
    ) internal returns (uint256 auctionRate, uint256 redemptionTimestamp) 
    {
        auctionRate = listData.auctionRates[address(repoToken)];
        if (auctionRate != INVALID_AUCTION_RATE) {
            (redemptionTimestamp, , ,) = repoToken.config();

            uint256 oracleRate = _auctionRate(termController, repoToken);
            if (oracleRate != INVALID_AUCTION_RATE) {
                if (auctionRate != oracleRate) {
                    listData.auctionRates[address(repoToken)] = oracleRate;
                }
            }
        } else {
            auctionRate = _auctionRate(termController, repoToken);

            if (!termController.isTermDeployed(address(repoToken))) {
                revert InvalidRepoToken(address(repoToken));
            }

            address purchaseToken;
            (redemptionTimestamp, purchaseToken, ,) = repoToken.config();
            if (purchaseToken != address(asset)) {
                revert InvalidRepoToken(address(repoToken));
            }

            if (redemptionTimestamp < block.timestamp) {
                revert InvalidRepoToken(address(repoToken));
            }

            insertSorted(listData, address(repoToken));
            listData.auctionRates[address(repoToken)] = auctionRate;
        }
    }

    function insertSorted(RepoTokenListData storage listData, address repoToken) internal {
        address current = listData.head;

        if (current == NULL_NODE) {
            listData.head = repoToken;
            return;
        }

        address prev;
        while (current != NULL_NODE) {

            uint256 currentMaturity = _getRepoTokenMaturity(current);
            uint256 maturityToInsert = _getRepoTokenMaturity(repoToken);

            if (maturityToInsert <= currentMaturity) {
                if (prev == NULL_NODE) {
                    listData.head = repoToken;
                } else {
                    listData.nodes[prev].next = repoToken;
                }
                listData.nodes[repoToken].next = current;
                break;
            }

            prev = current;
            current = _getNext(listData, current);
        }
    }

    function getPresentValue(RepoTokenListData storage listData, uint256 purchaseTokenPrecision) internal view returns (uint256 totalPresentValue) {
        if (listData.head == NULL_NODE) return 0;
        
        address current = listData.head;
        while (current != NULL_NODE) {
            uint256 currentMaturity = _getRepoTokenMaturity(current);
            uint256 repoTokenBalance = ITermRepoToken(current).balanceOf(address(this));
            uint256 repoTokenPrecision = 10**ERC20(current).decimals();
            uint256 auctionRate = listData.auctionRates[current];

            repoTokenBalance = ITermRepoToken(current).redemptionValue() * repoTokenBalance / RepoTokenUtils.RATE_PRECISION;

            if (currentMaturity > block.timestamp) {
                totalPresentValue += RepoTokenUtils.calculateProceeds(
                    repoTokenBalance, currentMaturity, repoTokenPrecision, purchaseTokenPrecision, auctionRate
                );
            } else {
                totalPresentValue += RepoTokenUtils.repoToPurchasePrecision(repoTokenPrecision, purchaseTokenPrecision, repoTokenBalance);
            }

            current = _getNext(listData, current);                    
        }    
    }
}
