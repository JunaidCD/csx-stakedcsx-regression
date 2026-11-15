// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

contract MockKeepers {
    mapping(address => bool) public councilMap;
    mapping(address => bool) public keeperNodeMap;

    function setCouncil(address account, bool value) external {
        councilMap[account] = value;
    }

    function setKeeperNode(address account, bool value) external {
        keeperNodeMap[account] = value;
    }

    function isCouncil(address _address) external view returns (bool) {
        return councilMap[_address];
    }

    function isKeeperNode(address _address) external view returns (bool) {
        return keeperNodeMap[_address];
    }

    // Additional methods present in some IKeepers versions
    function isKeeper(address) external pure returns (bool) { return false; }
    function council() external pure returns (address) { return address(0); }
    function isVesterUnderCouncilControl(address) external pure returns (bool) { return false; }
    function indexOf(address) external pure returns (uint256) { return 0; }
}
