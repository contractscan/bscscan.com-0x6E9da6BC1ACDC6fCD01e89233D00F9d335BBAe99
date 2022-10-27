// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;
interface IFifaSportDao {
    function distribution(address _to, uint256 _totalAmount) external;

    function getParents(address _wallet) external view returns (address[10] memory);

    function referral(address _from, address _to) external;

    function relations(address, uint256) external view returns (address);

    function setIsRecevicedAddress(address _to) external;
    
}