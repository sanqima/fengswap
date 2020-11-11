pragma solidity >=0.5.0 <0.7.0;

import "./PauserRole.sol";

/**
 * 紧急暂停机制
 */
contract Pausable is PauserRole {
    bool private _paused;               // 系统暂停标识

    constructor () internal {
        _paused = false;
    }

    // 暂停标识 true-禁用, false-启用
    function paused() public view returns (bool) {
        return _paused;
    }

    // 授权的访客在系统启用时，变更系统为禁用
    function pause() public onlyPauser whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }

    // 授权的访客在系统禁用时，变更系统为启用
    function unpause() public onlyPauser whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }


    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }

    modifier whenPaused() {
        require(_paused, "Pausable: not paused");
        _;
    }


    event Paused(address indexed pauser);
    event Unpaused(address indexed pauser);
}