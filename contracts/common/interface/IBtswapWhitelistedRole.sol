
pragma solidity >=0.5.0 <0.7.0;


interface IBtswapWhitelistedRole {
    function getWhitelistedsLength() external view returns (uint256);

    function isWhitelisted(address) external view returns (bool);

    function whitelisteds(uint256) external view returns (address);

}