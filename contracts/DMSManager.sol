//SPDX-License-Identifier: MIT


pragma solidity ^0.8.24;

import "./Common.sol";
import "./DMSAccount.sol";

contract DMSManager is Common {
    
    mapping(address => address) ownerToDmsAccMap;
   

    event Registered(address, address);


    constructor() {}

    function registerAccount(NomineeDetails memory nomineeDetails) external {
        address _owner = msg.sender;
        
        address _dmsAcc = address(new DMSAccount(nomineeDetails, _owner));
        require(_dmsAcc != address(0), "Failed to register");
        ownerToDmsAccMap[_owner] = _dmsAcc;

        emit Registered(_owner, _dmsAcc);
    } 
}