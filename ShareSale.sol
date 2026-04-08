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
        require(_token != address(0), "Invalid token");
        require(_operator != address(0), "Invalid operator");

        token = FractionToken(_token);
        operator = _operator;
        assetId = _assetId;
    }

    function configureSale(uint256 _pricePerShareWei, bool _isActive) external onlyOperator {
        if (_isActive) {
            require(_pricePerShareWei > 0, "Price must be > 0");
        }

        pricePerShareWei = _pricePerShareWei;
        isActive = _isActive;

        emit SaleConfigured(assetId, msg.sender, _pricePerShareWei, _isActive);
    }

    function quote(uint256 shareAmount) public view returns (uint256 totalCostWei) {
        require(shareAmount > 0, "Shares must be > 0");
        return pricePerShareWei * shareAmount;
    }

    function buyShares(uint256 shareAmount) external payable nonReentrant {
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
        uint256 amount = pendingProceeds;
        require(amount > 0, "No proceeds");

        pendingProceeds = 0;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "ETH transfer failed");

        emit ProceedsWithdrawn(assetId, msg.sender, amount);
    }
}
