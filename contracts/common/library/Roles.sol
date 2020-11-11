
pragma solidity >=0.5.0 <0.7.0;


/**
 * 多角色管理逻辑
 */
library Roles {
    // 存储角色授权数据
    struct Role {
        mapping(address => bool) bearer;
    }

    // 增加一个不存在的地址
    function add(Role storage role, address account) internal {
        require(account != address(0), "Roles: account is the zero address");
        require(!has(role, account), "Roles: account already has role");
        role.bearer[account] = true;
    }

    // 删除一个存在的地址
    function remove(Role storage role, address account) internal {
        require(has(role, account), "Roles: account does not have role");
        role.bearer[account] = false;
    }

    // 判断地址是否有权限
    function has(Role storage role, address account) internal view returns (bool) {
        require(account != address(0), "Roles: account is the zero address");
        return role.bearer[account];
    }
}