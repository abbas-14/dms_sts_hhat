//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

struct PaymentDetail {
    address sender;
    address receiver;
    uint256 amount;
    bytes32 otpHash;
    uint256 startTime;
}

contract STS {
    bool public locked;
    address public owner;
    uint256 public otpExpiry;
    uint256 public thresholdAmount;
    mapping(bytes32 => PaymentDetail) public payments;
    
    // params: sender, receiver, amount, payment ID
    event PaymentSyn(address, address, uint256, bytes32);
    // params: receiver, sender, amount, payment ID
    event PaymentAck(address, address, uint256, bytes32);
    // params: caller, refund-amount
    event PaymentRefunded(address, uint256, bytes32);
    
    constructor(uint256 expiry_, uint256 thAmt_) {
        otpExpiry = expiry_;
        thresholdAmount = thAmt_;
        owner = msg.sender;
    }

    // reeive otp in hash
    function sendAmount(address recvr_, bytes32 otpHash_) external payable withMutex() {
        require(recvr_ != address(0), "0 addr!");
        uint _val = msg.value;
        require(_val >= thresholdAmount, "less than TH");
        address _caller = msg.sender;
        bytes32 _paymentID = sha256(abi.encodePacked(_caller, recvr_, _val, otpHash_, block.timestamp));
        payments[_paymentID] = PaymentDetail(_caller, recvr_, _val, otpHash_, block.timestamp);
        emit PaymentSyn(_caller, recvr_, _val, _paymentID);
    }

    // receive otp in plain
    function receiveAmount(bytes32 paymentID_, string memory otp_) external withMutex() {
        address _caller = msg.sender;
        PaymentDetail memory _pd = payments[paymentID_];

        require(_pd.receiver == _caller, "payment not found!");
        // require(address(this).balance >= _pd.amount, "low bal!");
        require(!isOtpExpired(_pd.startTime), "OTP expired!");
        require(_pd.otpHash == sha256HashOf(otp_), "Invalid OTP!");

        // transfer the amount to the _caller
        payable(_caller).transfer(_pd.amount);
        emit PaymentAck(msg.sender, _caller, _pd.amount, paymentID_);
        // finally delete the entry
        delete payments[paymentID_];
    }

    function refund(bytes32 paymentID_) external withMutex() {
        address _caller = msg.sender;
        PaymentDetail memory _pd = payments[paymentID_];
        require(_caller == _pd.sender, "claimer not found!");
         // transfer the amount to the _caller
        payable(_caller).transfer(_pd.amount);
        emit PaymentRefunded(_caller, _pd.amount, paymentID_);
         // finally delete the entry
        delete payments[paymentID_];
    }

    function setOtpExpiry(uint256 expiry_) external onlyOwner() {
        otpExpiry = expiry_;
    }

    function setTHAmount(uint256 thAmt_) external onlyOwner() {
        thresholdAmount = thAmt_;
    }

    function isOtpExpired(uint256 startTime_) public view returns(bool) {
        return block.timestamp > startTime_ + otpExpiry;
    }

    function generateOtp(uint256 guessNum_) public view returns(string memory) {
        return num2str(uint(keccak256(abi.encodePacked(block.timestamp, guessNum_))) % 900000000 + 100000000);
    }

    function num2str(uint num_) public pure returns(string memory) {
        uint _tmp = num_;
        uint _digits;
        while (_tmp > 0) {
            _digits++;
            _tmp /= 10;
        }
        bytes memory _buffer = new bytes(_digits);
        while (num_ > 0) {
            _buffer[--_digits] = bytes1(uint8(48 + uint(num_ % 10)));
            num_ /= 10;
        }
        return string(_buffer);
    }

    function sha256HashOf(string memory v_) public pure returns(bytes32){
        return sha256(abi.encodePacked(v_));
    }

    function currTime() public view returns(uint256) {
        return block.timestamp;
    }

    modifier withMutex() {
        require(!locked, "Mutex: Locked!");
        locked = true;
        _;
        locked = false;
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "must b owner!");
        _;
    }
}