
pragma solidity >=0.5.0 <0.7.0;


interface IBtswapToken {
    function swap(address account, address input, uint256 amount, address output) external returns (bool);

    function liquidity(address account, address pair) external returns (bool);

}