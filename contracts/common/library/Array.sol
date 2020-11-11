
pragma solidity >=0.5.0 <0.7.0;


/**
 * 数组工具包
 */
library Array {
    // 从字节数组array中删除指定的bytes32
    function remove(bytes32[] storage array, bytes32 element) internal returns (bool) {
        for (uint256 index = 0; index < array.length; index++) {
            if (array[index] == element) {
                delete array[index];
                array[index] = array[array.length - 1];
                array.length--;
                return true;
            }
        }
        return false;
    }

    // 从地址数组array中删除指定的address
    function remove(address[] storage array, address element) internal returns (bool) {
        for (uint256 index = 0; index < array.length; index++) {
            if (array[index] == element) {
                delete array[index];
                array[index] = array[array.length - 1];
                array.length--;
                return true;
            }
        }
        return false;
    }
}
