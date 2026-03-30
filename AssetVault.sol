// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

// AssetVault registers real-world assets (e.g. EV charging stations) as NFTs.
// Each asset gets a unique token ID. The NFT owner is the operator of that asset.
contract AssetVault is ERC721 {

    // Auto-incrementing ID for each new asset registered
    uint256 public nextTokenId;

    // Metadata stored on-chain for each asset
    struct Asset {
        string model;        // e.g. "ABB Terra 184"
        string operatorName; // e.g. "Charge Holdings Pte Ltd"
        string location;     // e.g. "Orchard Road, Singapore"
        uint256 registeredAt; // block timestamp of registration
    }

    // Maps each token ID to its asset metadata
    mapping(uint256 => Asset) public assets;

    // Emitted when a new asset is registered
    event AssetRegistered(uint256 indexed tokenId, string model, address indexed owner);

    constructor() ERC721("YieldLayer Asset", "YLA") {}

    // Operator calls this to register their physical asset and receive an NFT.
    // Returns the new token ID.
    function registerAsset(
        string memory model,
        string memory operatorName,
        string memory location
    ) external returns (uint256 tokenId) {
        tokenId = nextTokenId++;

        // Mint the NFT to whoever is calling (the operator)
        _mint(msg.sender, tokenId);

        // Store the asset metadata on-chain
        assets[tokenId] = Asset({
            model: model,
            operatorName: operatorName,
            location: location,
            registeredAt: block.timestamp
        });

        emit AssetRegistered(tokenId, model, msg.sender);
    }

    // Read the metadata for any registered asset
    function getAsset(uint256 tokenId) external view returns (Asset memory) {
        require(tokenId < nextTokenId, "Asset does not exist");
        return assets[tokenId];
    }
}
