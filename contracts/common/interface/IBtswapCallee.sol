
pragma solidity >=0.5.0 <0.7.0;


interface IBtswapCallee {
    function bitswapCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;

}