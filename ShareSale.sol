// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./FractionToken.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// ShareSale manages the on-chain primary sale of one asset's fraction token.
contract ShareSale is ReentrancyGuard {
    FractionToken public immutable token;
    address public immutable operator;
    uint256 public immutable assetId;

    uint256 public pricePerShareWei;
    bool public isActive;
    bool public saleConfigured;
    uint256 public pendingProceeds;

    event SaleConfigured(uint256 indexed assetId, address indexed operator, uint256 pricePerShareWei, bool isActive);
    event SharesPurchased(
        uint256 indexed assetId,
        address indexed buyer,
        uint256 shares,
        uint256 totalCostWei,
        address indexed operator
    );
    event ProceedsWithdrawn(uint256 indexed assetId, address indexed operator, uint256 amountWei);

    modifier onlyOperator() {
        require(msg.sender == operator, "Only operator");
        _;
    }

    constructor(address _token, address _operator, uint256 _assetId) {
        // Basic deployment sanity checks for token and operator addresses.
        require(_token != address(0), "Invalid token");
        require(_operator != address(0), "Invalid operator");

        token = FractionToken(_token);
        operator = _operator;
        assetId = _assetId;
    }

    function configureSale(uint256 _pricePerShareWei, bool _isActive) external onlyOperator {
        // Sale settings are intentionally one-time to avoid mutable terms.
        require(!saleConfigured, "Sale already configured");
        if (_isActive) {
            require(_pricePerShareWei > 0, "Price must be > 0");
        }

        pricePerShareWei = _pricePerShareWei;
        isActive = _isActive;
        saleConfigured = true;

        emit SaleConfigured(assetId, msg.sender, _pricePerShareWei, _isActive);
    }

    function quote(uint256 shareAmount) public view returns (uint256 totalCostWei) {
        // Price quote is deterministic: shareAmount multiplied by configured price.
        require(shareAmount > 0, "Shares must be > 0");
        return pricePerShareWei * shareAmount;
    }

    function buyShares(uint256 shareAmount) external payable nonReentrant {
        // Enforce exact payment and available approved inventory from operator.
        require(isActive, "Sale is not active");
        require(pricePerShareWei > 0, "Invalid share price");
        require(shareAmount > 0, "Shares must be > 0");

        uint256 totalCostWei = pricePerShareWei * shareAmount;
        require(msg.value == totalCostWei, "Incorrect ETH amount");

        require(token.balanceOf(operator) >= shareAmount, "Insufficient operator shares");
        require(token.allowance(operator, address(this)) >= shareAmount, "Sale not approved");

        bool transferred = token.transferFrom(operator, msg.sender, shareAmount);
        require(transferred, "Share transfer failed");

        pendingProceeds += totalCostWei;

        emit SharesPurchased(assetId, msg.sender, shareAmount, totalCostWei, operator);
    }

    function withdrawProceeds() external onlyOperator nonReentrant {
        // Pull-pattern withdrawal sends accumulated proceeds to operator.
        uint256 amount = pendingProceeds;
        require(amount > 0, "No proceeds");

        pendingProceeds = 0;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "ETH transfer failed");

        emit ProceedsWithdrawn(assetId, msg.sender, amount);
    }
}
