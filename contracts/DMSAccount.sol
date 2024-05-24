//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "./IFT.sol";
import "./INFT.sol";
import "./Common.sol";

contract DMSAccount is Common {
    uint256 public constant DUR = 100; // blocks

    uint32 totalClaims;
    uint256 public duration;
    uint256 public startTime;
    address public owner;
    mapping(address => bool) claimed;
    mapping(address => bool) ftHold;
    mapping(address => bool) nftHold;
    
    address[] fTokens;
    address[] nfTokens;


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

    constructor(NomineeDetails memory nomineeDetails_, address owner_) {
        uint _len = nomineeDetails_.shares.length;

        for (uint i; i<_len; ++i) {
            require(nomineeDetails_.shares[i].ftShare <= 100, "Total FT shares exceed 100");
            require(nomineeDetails_.shares[i].nativeShare <= 100, "Total Native shares exceed 100");
            // require(nomineeDetails_.shares[i].nft > 0, "Invalid NFT ID");
            details.shares.push(nomineeDetails_.shares[i]);
        }

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
        require(INFT(token_).ownerOf(id_) == address(this), "id not owned by contract");
        IFT(token_).transferFrom(address(this), recvr_, id_);
    }


    function withdrawFT(address token_, uint256 amount_) external {
        address _caller = msg.sender;
        require(_caller == owner, "must be owner");
        _withdrawFT(token_, _caller, amount_);
        emit WithdrawnFT(_caller, token_, amount_);
    }

   

    function withdrawNFT(address token_, uint256 id_) external {
        address _caller = msg.sender;
        require(_caller == owner, "must be owner");
        _withdrawNFT(token_, _caller, id_);
        emit WithdrawnNFT(_caller, token_, id_);
    }

    function withdrawNative(uint256 amount_) external {
        address _caller = msg.sender;
        require(_caller == owner, "must be owner");
        _withdrawNative(_caller, amount_);
        emit WithdrawnNative(_caller, amount_);
    }

    // needs approval for the token amount
    function sendFT(address token_, uint256 amount_) external {
        address _caller = msg.sender;
        require(IFT(token_).allowance(_caller, address(this)) >= amount_, "allowance too low");
        IFT(token_).transferFrom(_caller, address(this), amount_);
        
        if(!ftHold[token_]) fTokens.push(token_);
        
        emit FTReceived(token_, amount_);
    }

    // needs approval for the nft id
    function sendNFT(address token_, uint256 id_, address targetNominee_) external {
        address _caller = msg.sender;
        require(INFT(token_).getApproved(id_) == address(this), "nft id not approved");
        INFT(token_).transferFrom(_caller, address(this), id_);
        
        if(!nftHold[token_]) nftHold[token_] = true;

        address[] memory _nominees = details.nominees;
        uint _len = _nominees.length;

        for(uint i; i<_len; ++i) if(_nominees[i] == targetNominee_) {
            details.shares[i].nfToken = token_;
            details.shares[i].nftid = id_;
            break;
        }
        
        emit NFTReceived(token_, id_, targetNominee_);
    }

    function startChallengePeriod() internal {
        startTime = block.timestamp;
        emit ChallengeStarted(startTime, duration + startTime);
    }

    function resetAll() internal {
        startTime = 0;
        totalClaims = 0;

        address[] memory _nominees = details.nominees;
        uint _len = _nominees.length;
        for(uint i; i<_len; claimed[_nominees[i++]] = false){}


    }

    function challengeEnded() public view returns(bool) {
        return block.timestamp > startTime + duration;
    }

    function challenge() external onlyOwner() {
        require(startTime != 0, "No Challenge");
        // if owner is alive and challenge is accepted
        // what will happend
        resetAll();
        emit ChallengeAccepted(owner, block.timestamp);
    }

    function claimAssets() external {
        require(startTime == 0, "in challenge period");

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
            startChallengePeriod();
        }
    }

    function updateDuration(uint256 _dur) external onlyOwner() {
        duration = _dur;
    }

    function disburseAssets() external {
        require(totalClaims == details.nominees.length, "not all claims acheived");
        require(challengeEnded(), "challenge still in progress");
        // disburse all assets to claimers / nominees

        address[] memory _ftokens = fTokens;
        address[] memory _nftokens = nfTokens;
        address[] memory _nominees = details.nominees;
        AssetShare[] memory _assetShares = details.shares;
        uint _len = _nominees.length;
        uint _share;
        uint _ftlen = _ftokens.length;
        uint _nftlen = _nftokens.length;
        address _thisAddr = address(this);
        uint _balNative = _thisAddr.balance;
        
        for(uint i; i<_len; ++i) {
            // disbursing Native
            _share = _assetShares[i].nativeShare;
            _share = (_balNative * _share) / 100;
            _withdrawNative(_nominees[i], _share);
            
            // disbursing FTs
            _share = _assetShares[i].ftShare;
            for(uint j; j<_ftlen; ++j) {
                _share = (IFT(_ftokens[j]).balanceOf(_thisAddr) * _share) / 100;
                _withdrawFT(_ftokens[j], _nominees[i], _share);
            }

            // disbursing NFTs  
            for(uint j; j<_nftlen; ++j)
                if(_assetShares[i].nfToken == _nftokens[j])
                    _withdrawNFT(_nftokens[j], _nominees[i], _assetShares[i].nftid);
            _withdrawNFT(_assetShares[i].nfToken, _nominees[i], _assetShares[i].nftid);    
        }
        emit AssetsDisbursed(_len);
    }

    modifier onlyOwner {
        require(msg.sender == owner, "must be owner");
        _;
    }

    receive() external payable {}
    fallback() external payable {}
}