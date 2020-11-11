
pragma solidity >=0.5.0 <0.7.0;

import "./Ownable.sol";
import "./Roles.sol";
import "./Array.sol";

/**
 *  由owner控制，具备动态矿工的合约
 */
contract MinterRole is Ownable {
    using Roles for Roles.Role;
    using Array for address[];

    Roles.Role private _minters;
    address[] public minters;

    constructor () internal {}

    function _addMinter(address account) internal {
        _minters.add(account);
        minters.push(account);
        emit MinterAdded(account);
    }

    function addMinter(address account) public onlyOwner {
        _addMinter(account);
    }

    function addMinter(address[] memory accounts) public onlyOwner {
        for (uint256 index = 0; index < accounts.length; index++) {
            _addMinter(accounts[index]);
        }
    }

    function _delMinter(address account) internal {
        _minters.remove(account);

        if (minters.remove(account)) {
            emit MinterRemoved(account);
        }
    }

    function renounceMinter() public {
        _delMinter(msg.sender);
    }

    function delMinter(address account) public onlyOwner {
        _delMinter(account);
    }

    function getMintersLength() public view returns (uint256) {
        return minters.length;
    }

    function isMinter(address account) public view returns (bool) {
        return _minters.has(account);
    }


    modifier onlyMinter() {
        require(isMinter(msg.sender), "MinterRole: caller does not have the Minter role");
        _;
    }


    event MinterAdded(address indexed account);
    event MinterRemoved(address indexed account);
}