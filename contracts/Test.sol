//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;


import "./Common.sol";
import "./DMSAccount.sol";
import "./DMSManager.sol";

import "./DMSFToken.sol";
import "./DMSNFToken.sol";
import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";


interface IDMSAcc {
    function challenge() external;
    function claimAssets() external;
    function disburseAssets() external;
    function removeNominee(address) external; 
    function sendFT(address, uint256) external;
    function withdrawNative(uint256, address) external;
    function sendNFT(address, uint256, address) external;
    function totalClaims() external view returns(uint32);
    function withdrawFT(address, uint256, address) external;
    function withdrawNFT(address, uint256, address) external;
    function viewBalanceFT(address) external view returns(uint256);
    function addNominees(address[] memory, Common.AssetShare[] memory) external;
}
// gas: 6054113
contract Test is Common, IERC721Receiver {
    uint256 public curNftID;
    address public ft;
    address public nft;
    address public dms;

    event TestAccRegistered(address, bool);
    event TestNFTReceived(address, address, uint256, bytes);
    
    constructor() {
        ft = address(new DMSFToken());
        nft = address(new DMSNFToken());
        console.log("constructor");
    }

    // after registration, call test_addNominees
    function test_registration(address[] memory nominees_) external  {
        // address[] memory nominees = new address[](1);
        // nominees[0] = address(0);
        uint _len = nominees_.length;
        require(_len == 2, "nominees must be 2");
        AssetShare[] memory _assetShares = new AssetShare[](_len);
        // native share: 30%
        // ft share: 30%
        for(uint i=0; i<_len; ++i) _assetShares[i] = AssetShare (30, 30, new address[](0), new uint256[](0));
        //assetShares[0] = AssetShare (10, 20, address(0), 0);
        NomineeDetails memory _nd = NomineeDetails (nominees_, _assetShares);

        address _cAddr = address(new DMSManager());
        bytes memory data = abi.encodeWithSignature(
            "registerAccount((address[],(uint8,uint8,address[],uint256[])[]))",
            _nd
        );

        (bool success, ) = _cAddr.call(data);
        require(success, "Function call to registerAccount, failed");
        emit TestAccRegistered(_cAddr, success);
        console.log("registered");
    }

    function test_sendNative() external payable  {
        payable(address(dms)).transfer(msg.value);
    }

    function test_sendFT(uint256 amt_) external {
        IFT(ft).mint(address(this), amt_);
        IFT(ft).approve(dms, amt_);
        IDMSAcc(dms).sendFT(ft, amt_);
    }

    function test_sendNFT(address nominee_) external {
        INFT(nft).safeMint(address(this));
        INFT(nft).approve(dms, curNftID);
        IDMSAcc(dms).sendNFT(nft, curNftID, nominee_);
        curNftID += 1;
    }

    function test_withdrawNative(uint256 amt_) external {
        IDMSAcc(dms).withdrawNative(amt_, address(this));
    }

    function test_withdrawFT(uint256 amt_) external {
        IDMSAcc(dms).withdrawFT(ft, amt_, address(this));
    }

    function test_withdrawNFT(uint256 id_) external {
        IDMSAcc(dms).withdrawNFT(nft, id_, address(this));
    }

    function test_claimAssets_by_non_claimer() external {
        uint32 _oldTotalClaims = IDMSAcc(dms).totalClaims();
        IDMSAcc(dms).claimAssets();
        require(IDMSAcc(dms).totalClaims() == _oldTotalClaims, "test_claimAssets_by_non_claimer works not");
    }

    function test_disburseAssets_by_owner() external {
        IDMSAcc(dms).disburseAssets();
    }

    // add only 2 more nominees
    function test_addNominees(address[] memory nominees_) external {
        uint _len = nominees_.length;
        require(_len == 2, "nominees must be 2");
        AssetShare[] memory _assetShares = new AssetShare[](_len);
        // native share: 20%
        // ft share: 20%
        for(uint i=0; i<_len; ++i) _assetShares[i] = AssetShare (20, 20, new address[](0), new uint256[](0));
        IDMSAcc(dms).addNominees(nominees_, _assetShares);
    }
    
    function test_removeNominee(address nominee_) external {
        IDMSAcc(dms).removeNominee(nominee_);
    }

    // helper functions
    
    // to be called after successful testing of dms registration 
    function setDmsContract(address dms_) external {
        dms = dms_;
    }

    function onERC721Received(
        address op_,
        address frm_,
        uint256 tid_,
        bytes memory data_
    ) public override returns (bytes4) {
        emit TestNFTReceived(op_, frm_, tid_, data_);

        return this.onERC721Received.selector;
    }
}