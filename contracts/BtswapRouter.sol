pragma solidity >=0.5.0 <0.7.0;

import "./common/library/SafeMath.sol";
import "./common/library/TransferHelper.sol";
import "./common/interface/IERC20.sol";
import "./common/interface/IBtswapETH.sol";
import "./common/interface/IBtswapFactory.sol";
import "./common/interface/IBtswapPairToken.sol";
import "./common/interface/IBtswapRouter02.sol";
import "./common/interface/IBtswapToken.sol";
import "./common/interface/IBtswapWhitelistedRole.sol";


contract BtswapRouter is IBtswapRouter02 {
    using SafeMath for uint256;

    address public factory;
    address public WETH;
    address public BT;

    constructor(address _factory, address _WETH, address _BT) public {
        factory = _factory;
        WETH = _WETH;
        BT = _BT;
    }

    function() external payable {
        // only accept ETH via fallback from the WETH contract
        assert(msg.sender == WETH);
    }

    function pairFor(address tokenA, address tokenB) public view returns (address pair){
        pair = IBtswapFactory(factory).pairFor(factory, tokenA, tokenB);
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal returns (uint256 amountA, uint256 amountB) {
        // create the pair if it doesn"t exist yet
        if (IBtswapFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            IBtswapFactory(factory).createPair(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = IBtswapFactory(factory).getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = IBtswapFactory(factory).quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "BtswapRouter: INSUFFICIENT_B_AMOUNT");
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = IBtswapFactory(factory).quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, "BtswapRouter: INSUFFICIENT_A_AMOUNT");
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = pairFor(tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IBtswapPairToken(pair).mint(to);
        IBtswapToken(BT).liquidity(msg.sender, pair);
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        (amountToken, amountETH) = _addLiquidity(
            token,
            WETH,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        address pair = pairFor(token, WETH);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IBtswapETH(WETH).deposit.value(amountETH)();
        assert(IBtswapETH(WETH).transfer(pair, amountETH));
        liquidity = IBtswapPairToken(pair).mint(to);
        IBtswapToken(BT).liquidity(msg.sender, pair);
        // refund dust eth, if any
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = pairFor(tokenA, tokenB);
        // send liquidity to pair
        IBtswapPairToken(pair).transferFrom(msg.sender, pair, liquidity);
        (uint256 amount0, uint256 amount1) = IBtswapPairToken(pair).burn(to);
        IBtswapToken(BT).liquidity(msg.sender, pair);
        (address token0,) = IBtswapFactory(factory).sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, "BtswapRouter: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "BtswapRouter: INSUFFICIENT_B_AMOUNT");
    }

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256 amountToken, uint256 amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IBtswapETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint256 amountA, uint256 amountB) {
        address pair = pairFor(tokenA, tokenB);
        uint256 value = approveMax ? uint256(- 1) : liquidity;
        IBtswapPairToken(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    function removeLiquidityETHWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint256 amountToken, uint256 amountETH) {
        address pair = pairFor(token, WETH);
        uint256 value = approveMax ? uint256(- 1) : liquidity;
        IBtswapPairToken(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256 amountETH) {
        (, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        IBtswapETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint256 amountETH) {
        address pair = pairFor(token, WETH);
        uint256 value = approveMax ? uint256(- 1) : liquidity;
        IBtswapPairToken(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint256[] memory amounts, address[] memory path, address _to) internal {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = IBtswapFactory(factory).sortTokens(input, output);
            uint256 amountInput = amounts[i];
            uint256 amountOut = amounts[i + 1];
            IBtswapToken(BT).swap(msg.sender, input, amountInput, output);
            (uint256 amount0Out, uint256 amount1Out) = input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address to = i < path.length - 2 ? pairFor(output, path[i + 2]) : _to;
            IBtswapPairToken(pairFor(input, output)).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        amounts = IBtswapFactory(factory).getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "BtswapRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        TransferHelper.safeTransferFrom(path[0], msg.sender, pairFor(path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        amounts = IBtswapFactory(factory).getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, "BtswapRouter: EXCESSIVE_INPUT_AMOUNT");
        TransferHelper.safeTransferFrom(path[0], msg.sender, pairFor(path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }

    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external payable ensure(deadline) returns (uint256[] memory amounts){
        require(path[0] == WETH, "BtswapRouter: INVALID_PATH");
        amounts = IBtswapFactory(factory).getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "BtswapRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        IBtswapETH(WETH).deposit.value(amounts[0])();
        assert(IBtswapETH(WETH).transfer(pairFor(path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }

    function swapTokensForExactETH(uint256 amountOut, uint256 amountInMax, address[] calldata path, address to, uint256 deadline) external ensure(deadline) returns (uint256[] memory amounts){
        require(path[path.length - 1] == WETH, "BtswapRouter: INVALID_PATH");
        amounts = IBtswapFactory(factory).getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, "BtswapRouter: EXCESSIVE_INPUT_AMOUNT");
        TransferHelper.safeTransferFrom(path[0], msg.sender, pairFor(path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        IBtswapETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external ensure(deadline) returns (uint256[] memory amounts){
        require(path[path.length - 1] == WETH, "BtswapRouter: INVALID_PATH");
        amounts = IBtswapFactory(factory).getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "BtswapRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        TransferHelper.safeTransferFrom(path[0], msg.sender, pairFor(path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        IBtswapETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapETHForExactTokens(uint256 amountOut, address[] calldata path, address to, uint256 deadline) external payable ensure(deadline) returns (uint256[] memory amounts){
        require(path[0] == WETH, "BtswapRouter: INVALID_PATH");
        amounts = IBtswapFactory(factory).getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, "BtswapRouter: EXCESSIVE_INPUT_AMOUNT");
        IBtswapETH(WETH).deposit.value(amounts[0])();
        assert(IBtswapETH(WETH).transfer(pairFor(path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        // refund dust eth, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = IBtswapFactory(factory).sortTokens(input, output);
            IBtswapPairToken pair = IBtswapPairToken(pairFor(input, output));
            uint256 amountInput;
            uint256 amountOutput;
            {// scope to avoid stack too deep errors
                (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
                (uint256 reserveInput, uint256 reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
                amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
                amountOutput = IBtswapFactory(factory).getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            IBtswapToken(BT).swap(msg.sender, input, amountInput, output);
            (uint256 amount0Out, uint256 amount1Out) = input == token0 ? (uint256(0), amountOutput) : (amountOutput, uint256(0));
            address to = i < path.length - 2 ? pairFor(output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) {
        TransferHelper.safeTransferFrom(path[0], msg.sender, pairFor(path[0], path[1]), amountIn);
        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin, "BtswapRouter: INSUFFICIENT_OUTPUT_AMOUNT");
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) {
        require(path[0] == WETH, "BtswapRouter: INVALID_PATH");
        uint256 amountIn = msg.value;
        IBtswapETH(WETH).deposit.value(amountIn)();
        assert(IBtswapETH(WETH).transfer(pairFor(path[0], path[1]), amountIn));
        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin, "BtswapRouter: INSUFFICIENT_OUTPUT_AMOUNT");
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) {
        require(path[path.length - 1] == WETH, "BtswapRouter: INVALID_PATH");
        TransferHelper.safeTransferFrom(path[0], msg.sender, pairFor(path[0], path[1]), amountIn);
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint256 amountOut = IERC20(WETH).balanceOf(address(this));
        require(amountOut >= amountOutMin, "BtswapRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        IBtswapETH(WETH).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) public view returns (uint256 amountB) {
        return IBtswapFactory(factory).quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public view returns (uint256 amountOut){
        return IBtswapFactory(factory).getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) public view returns (uint256 amountIn){
        return IBtswapFactory(factory).getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint256 amountIn, address[] memory path) public view returns (uint256[] memory amounts){
        return IBtswapFactory(factory).getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint256 amountOut, address[] memory path) public view returns (uint256[] memory amounts){
        return IBtswapFactory(factory).getAmountsIn(factory, amountOut, path);
    }

    function weth(address token) public view returns (uint256) {
        uint256 price = 0;

        if (WETH == token) {
            price = SafeMath.wad();
        }
        else if (IBtswapFactory(factory).getPair(token, WETH) != address(0)) {
            price = IBtswapPairToken(IBtswapFactory(factory).getPair(token, WETH)).price(token);
        }
        else {
            uint256 length = IBtswapWhitelistedRole(factory).getWhitelistedsLength();
            for (uint256 index = 0; index < length; index++) {
                address base = IBtswapWhitelistedRole(factory).whitelisteds(index);
                if (IBtswapFactory(factory).getPair(token, base) != address(0) && IBtswapFactory(factory).getPair(base, WETH) != address(0)) {
                    uint256 price0 = IBtswapPairToken(IBtswapFactory(factory).getPair(token, base)).price(token);
                    uint256 price1 = IBtswapPairToken(IBtswapFactory(factory).getPair(base, WETH)).price(base);
                    price = price0.wmul(price1);
                    break;
                }
            }
        }

        return price;
    }

    function onTransfer(address sender, address recipient) public onlyPair returns (bool) {
        IBtswapToken(BT).liquidity(sender, msg.sender);
        IBtswapToken(BT).liquidity(recipient, msg.sender);

        return true;
    }


    function isPair(address pair) public view returns (bool) {
        return IBtswapFactory(factory).getPair(IBtswapPairToken(pair).token0(), IBtswapPairToken(pair).token1()) == pair;
    }

    modifier onlyPair() {
        require(isPair(msg.sender), "BtswapRouter: caller is not the pair");
        _;
    }

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "BtswapRouter: EXPIRED");
        _;
    }

}