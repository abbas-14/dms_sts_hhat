//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "./IFT.sol";
import "./INFT.sol";
import "./Common.sol";

import "hardhat/console.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract DMSAccount is Common, IERC721Receiver {
    uint256 public constant DUR = 0; // blocks
    
    bool public locked;
    bool public disbursed;
    uint32 public totalClaims;
    
    uint256 public duration;
    uint256 public startTime;
    address public owner;
    mapping(address => bool) public claimed;
    mapping(address => bool) public ftHold;
    mapping(address => bool) public nftHold;
    
    address[] public fTokens;
    address[] public nfTokens;


    NomineeDetails details;

    // params:
    event AssetsDisbursed(uint256);
    // params: token addr, amount
    event FTReceived(address, uint256);
    // params: token addr, nft id, target nominee
    event NFTReceived(address, uint256, address);
    // params: caller, amount
    event WithdrawnNative(address, uint256);
    // params: caller, token addr, amount
    event WithdrawnFT(address, address, uint256);
    // params: caller, token addr, nft id
    event WithdrawnNFT(address, address, uint256);
    // params: claimer, totalClaims unitl now
    event Claimed(address, uint256);
    // params: start, end
    event ChallengeStarted(uint256, uint256);
    // params: challenger, time
    event ChallengeAccepted(address, uint256);
    // params: operator, from, tokenId, data
    event NFTReceived(address, address, uint256, bytes);

    constructor(NomineeDetails memory nomineeDetails_, address owner_) {
        uint _len = nomineeDetails_.nominees.length;
        require(_len == nomineeDetails_.shares.length, "l(shares) != l(nominees)");
        uint8 _sumFtShare = 0;
        uint8 _sumNativeShare = 0;

        for (uint i; i<_len; ++i) {
            _sumFtShare += nomineeDetails_.shares[i].ftShare;
            _sumNativeShare += nomineeDetails_.shares[i].nativeShare;
            // require(nomineeDetails_.shares[i].nft > 0, "Invalid NFT ID");
            details.shares.push(nomineeDetails_.shares[i]);
            details.nominees.push(nomineeDetails_.nominees[i]);
        }

        require(_sumFtShare <= 100, "Total FT shares exceed 100");
        require(_sumNativeShare <= 100, "Total Native shares exceed 100");

        owner = owner_;
        duration = DUR;
    }

    function _withdrawNative(address recvr_, uint256 amt_) internal {
        require(address(this).balance >= amt_, "Not enough native balance");
        payable(recvr_).transfer(amt_);
    }

    function _withdrawFT(address token_, address recvr_, uint256 amt_) internal {
        require(IFT(token_).balanceOf(address(this)) >= amt_, "Not enough balance");
        IFT(token_).transfer(recvr_, amt_);
    }

     function _withdrawNFT(address token_, address recvr_, uint id_) internal {
        console.log("_withdrawNFT begin");
        require(INFT(token_).ownerOf(id_) == address(this), "id not owned by contract");
        console.log("_withdrawNFT mid");
        INFT(token_).transferFrom(address(this), recvr_, id_);
        console.log("_withdrawNFT end");
    }


    function withdrawFT(address token_, uint256 amount_, address recvr_) external withMutex() onlyOwner() {
        _withdrawFT(token_, recvr_, amount_);
        emit WithdrawnFT(recvr_, token_, amount_);
    }

    function withdrawNFT(address token_, uint256 id_, address recvr_) external withMutex() onlyOwner() {
        _withdrawNFT(token_, recvr_, id_);
        emit WithdrawnNFT(recvr_, token_, id_);
    }

    function withdrawNative(uint256 amount_, address recvr_) external withMutex() onlyOwner() {
        _withdrawNative(recvr_, amount_);
        emit WithdrawnNative(recvr_, amount_);
    }

    // needs approval for the token amount
    function sendFT(address token_, uint256 amount_) external withMutex() {
        address _caller = msg.sender;
        require(IFT(token_).allowance(_caller, address(this)) >= amount_, "allowance too low");
        IFT(token_).transferFrom(_caller, address(this), amount_);
        
        if(!ftHold[token_]) {
            fTokens.push(token_);
            ftHold[token_] = true;
        }
        
        emit FTReceived(token_, amount_);
    }

    // needs approval for the nft id
    function sendNFT(address token_, uint256 id_, address targetNominee_) external withMutex() {
        address _caller = msg.sender;
        require(INFT(token_).getApproved(id_) == address(this), "nft id not approved");
        INFT(token_).transferFrom(_caller, address(this), id_);
        
        if(!nftHold[token_]) {
            nfTokens.push(token_);
            nftHold[token_] = true;
        }

        address[] memory _nominees = details.nominees;
        uint _len = _nominees.length;

        for(uint i; i<_len; ++i) if(_nominees[i] == targetNominee_) {
            details.shares[i].nfToken.push(token_);
            details.shares[i].nftid.push(id_);
            emit NFTReceived(token_, id_, targetNominee_);
            break;
        }
    }

    function _startChallengePeriod() internal {
        startTime = block.timestamp;
        emit ChallengeStarted(startTime, duration + startTime);
    }

    function _resetAll() internal {
        startTime = 0;
        totalClaims = 0;

        address[] memory _nominees = details.nominees;
        uint _len = _nominees.length;
        for(uint i; i<_len; claimed[_nominees[i++]] = false){}
    }

    function challengeEnded() public view returns(bool) {
        return block.timestamp > startTime + duration;
    }

    function challenge() external withMutex() onlyOwner() {
        require(inChallenge(), "No Challenge");
        // if owner is alive and challenge is accepted
        // what will happend
        _resetAll();
        emit ChallengeAccepted(owner, block.timestamp);
    }

    function claimAssets() external withMutex() {
        require(!disbursed, "already disbursed!");
        require(!inChallenge(), "in challenge period");

        address[] memory _nominees = details.nominees;
        uint _len = _nominees.length;
        uint32 _tc = totalClaims;
        require(_tc != _len, "all claims done");
        
        address _caller = msg.sender;

        for(uint i; i<_len; ++i) if(_nominees[i] == _caller && !claimed[_caller]) {
            _tc += 1;
            claimed[_caller] = true;
            totalClaims = _tc;
            emit Claimed(_caller, _tc);
            break;
        }
        if(_tc == _len) {
            _startChallengePeriod();
        }
    }

    function updateDuration(uint256 _dur) external withMutex() onlyOwner() {
        duration = _dur;
    }

    function _disburseFTs() internal {
        // disbursing FTs
        NomineeDetails memory _nd = details;
        address[] memory _ftokens = fTokens;
        uint _len = _ftokens.length;
        uint _nlen = _nd.nominees.length;

        for(uint i; i<_len; ++i) {
            uint __ftBal = IFT(_ftokens[i]).balanceOf(address(this));
            for(uint j; j<_nlen; ++j) {
                uint __share = _nd.shares[j].ftShare;
                __share = (__ftBal * __share) / 100;
                console.log("Share of FTs: ", __share);
                _withdrawFT(_ftokens[i], _nd.nominees[j], __share);
            }
        } 
    }

    function disburseAssets() external {
        require(!disbursed, "already disbursed!");
        if(msg.sender != owner) {
            require(totalClaims == details.nominees.length, "not all claims acheived");
            require(challengeEnded(), "challenge still in progress");
        }
        disbursed = true;
        _resetAll();
        // disburse all assets to claimers / nominees

        address[] memory _nftokens = nfTokens;
        NomineeDetails memory _details = details;
        uint _len = _details.nominees.length;
        require(_len > 0, "no nominees!");
        uint _share;
        address _thisAddr = address(this);
        uint _balNative = _thisAddr.balance;
        
        for(uint i; i<_len; ++i) {
            // disbursing Native
            _share = _details.shares[i].nativeShare;
            console.log("Disbursing Native, %: ", _share);
            _share = (_balNative * _share) / 100;
            console.log("Share: ", _share);
            _withdrawNative(_details.nominees[i], _share);
            
            // disbursing NFTs  
            console.log("Disbursing NFTs: ", _nftokens.length);
            for(uint j; j<_nftokens.length; ++j) {
                uint __nftslen = _details.shares[i].nfToken.length;
                for(uint k; k<__nftslen; ++k)
                    if(_details.shares[i].nfToken[k] == _nftokens[j]) {
                        console.log("NFT: ", _nftokens[j]);
                        console.log("NFT ID: ", _details.shares[i].nftid[k]);
                        _withdrawNFT(_nftokens[j], _details.nominees[i], _details.shares[i].nftid[k]);
                    }    
            }
        }
        _disburseFTs();
        emit AssetsDisbursed(_len);
    }

    function addNominees(address[] memory nominees_, AssetShare[] memory assetShares_) external withMutex() onlyOwner() {
        uint _len1 = nominees_.length;
        uint _len2 = details.nominees.length;
        AssetShare[] memory _assetShares = details.shares;
        uint8 _sumFtShare = 0;
        uint8 _sumNativeShare = 0;

        for (uint i; i<_len1; ++i) {
            _sumFtShare += assetShares_[i].ftShare;
            _sumNativeShare += assetShares_[i].nativeShare;
            // require(nomineeDetails_.shares[i].nft > 0, "Invalid NFT ID");
            details.nominees.push(nominees_[i]);
            details.shares.push(assetShares_[i]);
        }

        for(uint i=0; i<_len2; ++i) {
            _sumFtShare += _assetShares[i].ftShare;
            _sumNativeShare += _assetShares[i].nativeShare;
        }

        require(_sumFtShare <= 100, "Total FT shares exceed 100");
        require(_sumNativeShare <= 100, "Total Native shares exceed 100");
    }

    function removeNominee(address nominee_) external withMutex() onlyOwner() {
        address[] memory _nominees = details.nominees;
        uint _len = _nominees.length;
        for(uint i=0; i<_len; ++i)
            if(_nominees[i] == nominee_) {
                // swap with last element
                details.shares[i] = details.shares[_len - 1];
                details.nominees[i] = details.nominees[_len - 1];
                // remove last element
                details.shares.pop();
                details.nominees.pop();
                break;
            }
    }

    function setDisbursed(bool disb_) external {
        disbursed = disb_;
    }

    function viewBalanceFT(address ft_) public view returns(uint256) {
        return IFT(ft_).balanceOf(address(this));
    }

    function viewBalanceNFT(address nft_) public view returns(uint256) {
        return INFT(nft_).balanceOf(address(this));
    }

    function viewBalanceNative() public view returns(uint256) {
        return address(this).balance;
    }

    function inChallenge() public view returns(bool) {
        return startTime != 0;
    }

    modifier onlyOwner {
        require(msg.sender == owner, "must be owner");
        _;
    }

    modifier withMutex {
        require(locked == false, "Mutex: lock not released");
        locked = true;
        _;
        locked = false;
    }

    function onERC721Received(
        address op_,
        address frm_,
        uint256 tid_,
        bytes memory data_
    ) public override returns (bytes4) {
        emit NFTReceived(op_, frm_, tid_, data_);

        return this.onERC721Received.selector;
    }

    receive() external payable {}
    fallback() external payable {}
}