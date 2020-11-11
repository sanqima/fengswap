pragma solidity >=0.5.0 <0.7.0;

import "./common/library/SafeMath.sol";
import "./common/library/Array.sol";
import "./common/library/Roles.sol";
import "./common/library/Ownable.sol";
import "./common/library/UQ112x112.sol";
import "./common/library/WhitelistedRole.sol";
import "./common/interface/IBtswapCallee.sol";
import "./common/interface/IBtswapPairToken.sol";
import "./common/interface/IBtswapRouter02.sol";
import "./common/interface/IBtswapERC20.sol";
import "./common/interface/IBtswapFactory.sol";
import "./common/utility/BtswapERC20.sol";
import "./BtswapPairToken.sol";

contract BtswapFactory is IBtswapFactory, WhitelistedRole {
    using SafeMath for uint256;

    uint256 public constant FEE_RATE_DENOMINATOR = 1e4;

    address public router;
    address public feeTo;
    address public feeToSetter;
    uint256 public feeRateNumerator = 25;
    bytes32 public initCodeHash;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;


    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        require(isWhitelisted(token0) || isWhitelisted(token1), "BtswapFactory: TOKEN_UNAUTHORIZED");
        // single check is sufficient
        require(getPair[token0][token1] == address(0), "BtswapFactory: PAIR_EXISTS");
        bytes memory bytecode = type(BtswapPairToken).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IBtswapPairToken(pair).initialize(router, token0, token1);
        getPair[token0][token1] = pair;
        // populate mapping in the reverse direction
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setRouter(address _router) public onlyOwner {
        router = _router;
    }

    function setFeeTo(address _feeTo) external onlyOwner {
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external onlyOwner {
        feeToSetter = _feeToSetter;
    }

    function setFeeRateNumerator(uint256 _feeRateNumerator) external onlyOwner {
        require(_feeRateNumerator < FEE_RATE_DENOMINATOR, "BtswapFactory: EXCEEDS_FEE_RATE_DENOMINATOR");
        feeRateNumerator = _feeRateNumerator;
    }

    function setInitCodeHash(bytes32 _initCodeHash) external onlyOwner {
        initCodeHash = _initCodeHash;
    }

    function getInitCodeHash() public pure returns (bytes32) {
        return keccak256(abi.encodePacked(type(BtswapPairToken).creationCode));
    }

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) public pure returns (address token0, address token1) {
        require(tokenA != tokenB, "BtswapFactory: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "BtswapFactory: ZERO_ADDRESS");
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, address tokenA, address tokenB) public view returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint256(keccak256(abi.encodePacked(
                hex"ff",
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                initCodeHash
            ))));
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address factory, address tokenA, address tokenB) public view returns (uint256 reserveA, uint256 reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1,) = IBtswapPairToken(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) public pure returns (uint256 amountB) {
        require(amountA > 0, "BtswapFactory: INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "BtswapFactory: INSUFFICIENT_LIQUIDITY");
        amountB = amountA.mul(reserveB) / reserveA;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public view returns (uint256 amountOut) {
        require(amountIn > 0, "BtswapFactory: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "BtswapFactory: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn.mul(FEE_RATE_DENOMINATOR - feeRateNumerator);
        uint256 numerator = amountInWithFee.mul(reserveOut);
        uint256 denominator = reserveIn.mul(FEE_RATE_DENOMINATOR).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) public view returns (uint256 amountIn) {
        require(amountOut > 0, "BtswapFactory: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "BtswapFactory: INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn.mul(amountOut).mul(FEE_RATE_DENOMINATOR);
        uint256 denominator = reserveOut.sub(amountOut).mul(FEE_RATE_DENOMINATOR - feeRateNumerator);
        amountIn = (numerator / denominator).add(1);
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(address factory, uint256 amountIn, address[] memory path) public view returns (uint256[] memory amounts) {
        require(path.length >= 2, "BtswapFactory: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(address factory, uint256 amountOut, address[] memory path) public view returns (uint256[] memory amounts) {
        require(path.length >= 2, "BtswapFactory: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }


    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

}