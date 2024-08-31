// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract NTPair is IERC721Receiver, ReentrancyGuard {
    // Constants for ERC20 and ERC721 transfer methods
    bytes4 private constant ERC20_TRANSFER_FROM_SELECTOR = bytes4(keccak256("transferFrom(address,address,uint256)"));
    bytes4 private constant ERC721_SAFE_TRANSFER_FROM_SELECTOR = bytes4(keccak256("safeTransferFrom(address,address,uint256)"));

    struct Pair {
        address ERC721ContractAddress;
        address ERC20ContractAddress;
        address ERC721TokenOwner;
        uint256 ERC721TokenId;
        uint256 ERC20SettedTokenValue;
    }

    // Mappings for storing pairs and associations
    mapping(bytes32 => Pair) public pairs; // Maps a unique ID to each Pair
    mapping(address => mapping(uint256 => address)) public ERC721ToERC20; // Maps ERC721 token to its paired ERC20 address

    event TokenReceived(address operator, address from, uint256 tokenId, bytes data);
    event TokenRetrieved(address owner, address ERC721ContractAddress, uint256 ERC721TokenId);
    event PairCreated(address ERC721ContractAddress, uint256 ERC721TokenId, address ERC20ContractAddress, uint256 ERC20TokenValue, address pair);
    event Swapped(address ERC721ContractAddress, address ERC20ContractAddress, address from, address to, uint256 ERC721TokenId, uint256 ERC20TokenValue);
    event ERC20TokenPriceChanged(address ERC721ContractAddress, address ERC20ContractAddress, uint256 ERC721TokenId, uint256 oldPrice, uint256 newPrice);

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        emit TokenReceived(operator, from, tokenId, data);
        return this.onERC721Received.selector;
    }

    function createPair(
        address _ERC721ContractAddress,
        address _ERC20ContractAddress,
        uint256 _ERC721TokenId,
        uint256 _ERC20TokenValue
    ) external nonReentrant {
        bytes32 pairId = keccak256(abi.encodePacked(_ERC721ContractAddress, _ERC721TokenId, _ERC20ContractAddress));
        require(pairs[pairId].ERC721ContractAddress == address(0), "Pair already exists");
        require(IERC721(_ERC721ContractAddress).ownerOf(_ERC721TokenId) == address(this), "Token hasn't been sent to this contract");

        pairs[pairId] = Pair({
            ERC721ContractAddress: _ERC721ContractAddress,
            ERC20ContractAddress: _ERC20ContractAddress,
            ERC721TokenOwner: msg.sender,
            ERC721TokenId: _ERC721TokenId,
            ERC20SettedTokenValue: _ERC20TokenValue
        });

        ERC721ToERC20[_ERC721ContractAddress][_ERC721TokenId] = _ERC20ContractAddress;

        emit PairCreated(_ERC721ContractAddress, _ERC721TokenId, _ERC20ContractAddress, _ERC20TokenValue, address(this));
    }

    function retrieveERC721Token(
        address _ERC721ContractAddress,
        uint256 _ERC721TokenId
    ) external nonReentrant {
        address _ERC20ContractAddress = ERC721ToERC20[_ERC721ContractAddress][_ERC721TokenId];
        bytes32 pairId = keccak256(abi.encodePacked(_ERC721ContractAddress, _ERC721TokenId, _ERC20ContractAddress));
        Pair memory pairInfo = pairs[pairId];

        require(pairInfo.ERC721TokenOwner == msg.sender, "Not the owner of ERC721 Token");

        delete pairs[pairId];
        delete ERC721ToERC20[_ERC721ContractAddress][_ERC721TokenId];

        emit TokenRetrieved(pairInfo.ERC721TokenOwner, _ERC721ContractAddress, _ERC721TokenId);
        _safeTransferERC721(pairInfo.ERC721ContractAddress, pairInfo.ERC721TokenOwner, pairInfo.ERC721TokenId);
    }

    function swap(
        address _ERC721ContractAddress,
        uint256 _ERC721TokenId
    ) external nonReentrant {
        address _ERC20ContractAddress = ERC721ToERC20[_ERC721ContractAddress][_ERC721TokenId];
        bytes32 pairId = keccak256(abi.encodePacked(_ERC721ContractAddress, _ERC721TokenId, _ERC20ContractAddress));
        Pair memory pairInfo = pairs[pairId];

        require(pairInfo.ERC721ContractAddress != address(0), "Pair hasn't been created");
        require(
            pairInfo.ERC20SettedTokenValue == IERC20(_ERC20ContractAddress).allowance(msg.sender, address(this)),
            "Contract hasn't been allowed to make this transfer on ERC20 owner's behalf"
        );

        delete pairs[pairId];
        delete ERC721ToERC20[_ERC721ContractAddress][_ERC721TokenId];

        emit Swapped(_ERC721ContractAddress, _ERC20ContractAddress, msg.sender, pairInfo.ERC721TokenOwner, _ERC721TokenId, pairInfo.ERC20SettedTokenValue);
        _safeTransferERC20(msg.sender, pairInfo.ERC721TokenOwner, pairInfo.ERC20ContractAddress, pairInfo.ERC20SettedTokenValue);
        _safeTransferERC721(pairInfo.ERC721ContractAddress, msg.sender, pairInfo.ERC721TokenId);
    }

    function changeERC20TokenPrice(
        address _ERC721ContractAddress,
        uint256 _ERC721TokenId,
        uint256 _newERC20TokenPrice
    ) external nonReentrant {
        address _ERC20ContractAddress = ERC721ToERC20[_ERC721ContractAddress][_ERC721TokenId];
        bytes32 pairId = keccak256(abi.encodePacked(_ERC721ContractAddress, _ERC721TokenId, _ERC20ContractAddress));
        Pair storage pairInfo = pairs[pairId];

        require(pairInfo.ERC721ContractAddress != address(0), "Pair hasn't been created");
        require(pairInfo.ERC721TokenOwner == msg.sender, "Not the owner of ERC721 token");

        uint256 oldPrice = pairInfo.ERC20SettedTokenValue;
        pairInfo.ERC20SettedTokenValue = _newERC20TokenPrice;

        emit ERC20TokenPriceChanged(_ERC721ContractAddress, _ERC20ContractAddress, _ERC721TokenId, oldPrice, _newERC20TokenPrice);
    }

    function _safeTransferERC721(
        address _ERC721ContractAddress,
        address to,
        uint256 _ERC721TokenId
    ) private {
        IERC721(_ERC721ContractAddress).safeTransferFrom(address(this), to, _ERC721TokenId);
    }

    function _safeTransferERC20(
        address from,
        address to,
        address _ERC20ContractAddress,
        uint256 amount
    ) private {
        IERC20(_ERC20ContractAddress).transferFrom(from, to, amount);
    }
}
