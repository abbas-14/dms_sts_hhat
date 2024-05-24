//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "./IFT.sol";
import "./INFT.sol";

abstract contract Common {
    struct AssetShare {
        uint8 nativeShare; // 0 - 100
        // IFT fToken;
        uint8 ftShare; // 0 - 100
        address nfToken;
        uint256 nftid; // id
    }
     struct NomineeDetails {
        address[] nominees;
        AssetShare[] shares;
    }
}