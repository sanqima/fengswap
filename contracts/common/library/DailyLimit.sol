
pragma solidity >=0.5.0 <0.7.0;

import "./Ownable.sol";
import "./SafeMath.sol";

/**
 * 代币每日转账额度控制机制
 */
contract DailyLimit is Ownable {
    using SafeMath for uint256;

    mapping(address => UserDailyLimit) public dailyLimits;      // 用户额度信息

    struct UserDailyLimit {
        uint256 spent;                                          // 今日已用额度
        uint256 today;                                          // 今日开始时间
        uint256 limit;                                          // 今日总共额度
    }

    constructor () internal {}

    /**
     * 查询用户每日额度信息
     */
    function getDailyLimit(address account) public view returns (uint256, uint256, uint256){
        UserDailyLimit memory dailyLimit = dailyLimits[account];
        return (dailyLimit.spent, dailyLimit.today, dailyLimit.limit);
    }

    /**
     * 设置用户每日总共额度
     */
    function _setDailyLimit(address account, uint256 limit) internal {
        require(account != address(0), "DailyLimit: account is the zero address");
        require(limit != 0, "DailyLimit: limit can not be zero");

        dailyLimits[account].limit = limit;
    }

    function setDailyLimit(address[] memory accounts, uint256[] memory limits) public onlyOwner {
        require(accounts.length == limits.length, "DailyLimit: accounts and limits length mismatched");

        for (uint256 index = 0; index < accounts.length; index++) {
            _setDailyLimit(accounts[index], limits[index]);
        }
    }

    /**
     * 今日开始时间
     */
    function today() public view returns (uint256){
        return now - (now % 1 days);
    }

    /**
     * 是否小于限制
     */
    function isUnderLimit(address account, uint256 amount) internal returns (bool){
        UserDailyLimit storage dailyLimit = dailyLimits[account];

        if (today() > dailyLimit.today) {
            dailyLimit.today = today();
            dailyLimit.spent = 0;
        }

        // A).limit为0，不用做限制 B).limit非0，需满足限制
        return (dailyLimit.limit == 0 || dailyLimit.spent.add(amount) <= dailyLimit.limit);
    }


    modifier onlyUnderLimit(address account, uint256 amount){
        require(isUnderLimit(account, amount), "DailyLimit: user's spent exceeds daily limit");
        _;
    }
}
