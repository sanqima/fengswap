
pragma solidity >=0.5.0 <0.7.0;


import "../interface/IERC20.sol";
import "../interface/IBtswapFactory.sol";
import "../interface/IBtswapPairToken.sol";
import "../interface/IBtswapRouter02.sol";
import "../interface/IBtswapToken.sol";
import "../interface/IBtswapWhitelistedRole.sol";
import "../library/SafeMath.sol";
import "../library/Array.sol";
import "../library/Roles.sol";
import "../library/Ownable.sol";
import "../library/BlacklistedRole.sol";
import "../library/DailyLimit.sol";
import "../library/PauserRole.sol";
import "../library/Pausable.sol";
import "../library/WhitelistedRole.sol";
import "../library/MinterRole.sol";
import "./ERC20.sol";


contract BtswapToken is IBtswapToken, WhitelistedRole, MinterRole, ERC20 {
    uint256 public constant MINT_DECAY_DURATION = 8409600;
    uint256 public INITIAL_BLOCK_REWARD = SafeMath.wad().mul(56);
    uint256 public PERCENTAGE_FOR_TAKER = SafeMath.wad().mul(60).div(100);
    uint256 public PERCENTAGE_FOR_MAKER = SafeMath.wad().mul(30).div(100);
    address public constant TAKER_ADDRESS = 0x0000000000000000000000000000000000000001;
    address public constant MAKER_ADDRESS = 0x0000000000000000000000000000000000000002;
    address public constant GROUP_ADDRESS = 0x0000000000000000000000000000000000000003;

    IBtswapRouter02 private _router;

    uint256 private _initMintBlock;
    uint256 private _lastMintBlock;
    mapping(address => uint256) private _weights;

    Pool public taker;
    Pool public maker;

    struct Pool {
        uint256 timestamp;
        uint256 quantity;
        uint256 deposit;
        mapping(address => User) users;
    }

    struct User {
        uint256 timestamp;
        uint256 quantity;
        uint256 deposit;
        mapping(address => uint256) deposits;
    }

    constructor () public ERC20("BTswap Token", "BT", 18) {
        _setInitMintBlock(block.number);
        _setLastMintBlock(block.number);
        _mint(msg.sender, 50000000 * 1e18);
    }


    /**
     * dao
     */
    function router() public view returns (IBtswapRouter02) {
        return _router;
    }

    function setRouter(IBtswapRouter02 newRouter) public onlyOwner {
        require(address(newRouter) != address(0), "BtswapToken: new router is the zero address");
        _router = newRouter;
    }

    function initMintBlock() public view returns (uint256) {
        return _initMintBlock;
    }

    function _setInitMintBlock(uint256 blockNumber) internal {
        _initMintBlock = blockNumber;
    }

    function lastMintBlock() public view returns (uint256) {
        return _lastMintBlock;
    }

    function _setLastMintBlock(uint256 blockNumber) internal {
        _lastMintBlock = blockNumber;
    }

    function weightOf(address token) public view returns (uint256) {
        uint256 _weight = _weights[token];

        if (_weight > 0) {
            return _weight;
        }

        return 1;
    }

    function setWeight(address newToken, uint256 newWeight) public onlyOwner {
        require(address(newToken) != address(0), "BtswapToken: new token is the zero address");
        _weights[newToken] = newWeight;
    }


    /**
     * miner
     */
    function phase(uint256 blockNumber) public view returns (uint256) {
        uint256 _phase = 0;

        if (blockNumber > initMintBlock()) {
            _phase = (blockNumber.sub(initMintBlock()).sub(1)).div(MINT_DECAY_DURATION);
        }

        return _phase;
    }

    function phase() public view returns (uint256) {
        return phase(block.number);
    }

    function reward(uint256 blockNumber) public view returns (uint256) {
        uint256 _phase = phase(blockNumber);
        if (_phase >= 10) {
            return 0;
        }

        return INITIAL_BLOCK_REWARD.div(2 ** _phase);
    }

    function reward() public view returns (uint256) {
        return reward(block.number);
    }

    function mintable(uint256 blockNumber) public view returns (uint256) {
        uint256 _mintable = 0;
        uint256 lastMintableBlock = lastMintBlock();
        uint256 n = phase(lastMintBlock());
        uint256 m = phase(blockNumber);

        while (n < m) {
            n++;
            uint256 r = n.mul(MINT_DECAY_DURATION).add(initMintBlock());
            _mintable = _mintable.add((r.sub(lastMintableBlock)).mul(reward(r)));
            lastMintableBlock = r;
        }
        _mintable = _mintable.add((blockNumber.sub(lastMintableBlock)).mul(reward(blockNumber)));

        return _mintable;
    }

    function mint() public returns (bool) {
        if (!isMintable()) {
            return false;
        }

        uint256 _mintable = mintable(block.number);
        if (_mintable <= 0) {
            return false;
        }

        _setLastMintBlock(block.number);

        uint256 takerMintable = _mintable.wmul(PERCENTAGE_FOR_TAKER);
        uint256 makerMintable = _mintable.wmul(PERCENTAGE_FOR_MAKER);
        uint256 groupMintable = _mintable.sub(takerMintable).sub(makerMintable);

        _mint(TAKER_ADDRESS, takerMintable);
        _mint(MAKER_ADDRESS, makerMintable);
        _mint(GROUP_ADDRESS, groupMintable);

        return true;
    }


    /**
     * oracle
     */
    function weth(address token, uint256 amount) public view returns (uint256) {
        uint256 _weth = router().weth(token);
        if (_weth <= 0) {
            return 0;
        }

        return _weth.wmul(amount);
    }

    function rebalance(address account, address pair) public view returns (uint256) {
        if (!isWhitelisted(IBtswapPairToken(pair).token0()) || !isWhitelisted(IBtswapPairToken(pair).token1())) {
            return 0;
        }

        uint256 m = IBtswapPairToken(pair).totalSupply();
        uint256 n = IBtswapPairToken(pair).balanceOf(account);
        if (n <= 0 || m <= 0) {
            return 0;
        }

        (uint112 reserve0, uint112 reserve1,) = IBtswapPairToken(pair).getReserves();
        uint256 _weth0 = weth(IBtswapPairToken(pair).token0(), uint256(reserve0));
        uint256 _weight0 = weightOf(IBtswapPairToken(pair).token0());
        uint256 _weth1 = weth(IBtswapPairToken(pair).token1(), uint256(reserve1));
        uint256 _weight1 = weightOf(IBtswapPairToken(pair).token1());

        uint256 _weth = _weth0.mul(_weight0).add(_weth1.mul(_weight1));

        return _weth.mul(n).div(m);
    }


    /**
     * taker
     */
    function shareOf(address account) public view returns (uint256, uint256) {
        uint256 m = takerQuantityOfPool();
        uint256 n = takerQuantityOf(account);

        return (m, n);
    }

    function takerQuantityOfPool() public view returns (uint256) {
        return taker.quantity;
    }

    function takerTimestampOfPool() public view returns (uint256) {
        return taker.timestamp;
    }

    function takerQuantityOf(address account) public view returns (uint256) {
        return taker.users[account].quantity;
    }

    function takerTimestampOf(address account) public view returns (uint256) {
        return taker.users[account].timestamp;
    }

    function takerBalanceOf() public view returns (uint256) {
        return balanceOf(TAKER_ADDRESS);
    }

    function takerBalanceOf(address account) public view returns (uint256) {
        (uint256 m, uint256 n) = shareOf(account);
        if (n <= 0 || m <= 0) {
            return 0;
        }

        if (n == m) {
            return takerBalanceOf();
        }

        return takerBalanceOf().mul(n).div(m);
    }

    function swap(address account, address input, uint256 amount, address output) public onlyMinter returns (bool) {
        require(account != address(0), "BtswapToken: taker swap account is the zero address");
        require(input != address(0), "BtswapToken: taker swap input is the zero address");
        require(output != address(0), "BtswapToken: taker swap output is the zero address");

        // if (!isWhitelisted(input) || !isWhitelisted(output)) {
        //     return false;
        // }

        uint256 quantity = weth(input, amount);
        if (quantity <= 0) {
            return false;
        }

        mint();

        taker.timestamp = block.timestamp;
        taker.quantity = takerQuantityOfPool().add(quantity);

        User storage user = taker.users[account];
        user.timestamp = block.timestamp;
        user.quantity = takerQuantityOf(account).add(quantity);

        return true;
    }

    function _takerWithdraw(uint256 quantity) internal returns (bool) {
        require(quantity > 0, "BtswapToken: taker withdraw quantity is the zero value");
        require(takerBalanceOf() >= quantity, "BtswapToken: taker withdraw quantity exceeds taker balance");

        uint256 delta = takerQuantityOfPool();
        if (takerBalanceOf() != quantity) {
            delta = takerQuantityOfPool().mul(quantity).div(takerBalanceOf());
        }

        taker.timestamp = block.timestamp;
        taker.quantity = takerQuantityOfPool().sub(delta);

        User storage user = taker.users[msg.sender];
        user.timestamp = block.timestamp;
        user.quantity = takerQuantityOf(msg.sender).sub(delta);

        _transfer(TAKER_ADDRESS, msg.sender, quantity);

        return true;
    }

    function takerWithdraw(uint256 quantity) public returns (bool) {
        mint();

        uint256 balance = takerBalanceOf(msg.sender);
        if (quantity <= balance) {
            return _takerWithdraw(quantity);
        }

        return _takerWithdraw(balance);
    }

    function takerWithdraw() public returns (bool) {
        mint();

        uint256 balance = takerBalanceOf(msg.sender);

        return _takerWithdraw(balance);
    }


    /**
     * maker
     */
    function liquidityOf(address account) public view returns (uint256, uint256) {
        uint256 m = makerQuantityOfPool().add(makerDepositOfPool().mul(block.number.sub(makerTimestampOfPool())));
        uint256 n = makerQuantityOf(account).add(makerDepositOf(account).mul(block.number.sub(makerTimestampOf(account))));

        return (m, n);
    }

    function makerQuantityOfPool() public view returns (uint256) {
        return maker.quantity;
    }

    function makerDepositOfPool() public view returns (uint256) {
        return maker.deposit;
    }

    function makerTimestampOfPool() public view returns (uint256) {
        return maker.timestamp;
    }

    function makerQuantityOf(address account) public view returns (uint256) {
        return maker.users[account].quantity;
    }

    function makerDepositOf(address account) public view returns (uint256) {
        return maker.users[account].deposit;
    }

    function makerLastDepositOf(address account, address pair) public view returns (uint256) {
        return maker.users[account].deposits[pair];
    }

    function makerTimestampOf(address account) public view returns (uint256) {
        return maker.users[account].timestamp;
    }

    function _makerBalanceAndLiquidityOf(address account) internal view returns (uint256, uint256, uint256) {
        (uint256 m, uint256 n) = liquidityOf(account);
        if (n <= 0 || m <= 0) {
            return (0, m, n);
        }

        if (n == m) {
            return (makerBalanceOf(), m, n);
        }

        return (makerBalanceOf().mul(n).div(m), m, n);
    }

    function makerBalanceOf() public view returns (uint256) {
        return balanceOf(MAKER_ADDRESS);
    }

    function makerBalanceOf(address account) public view returns (uint256) {
        (uint256 balance, ,) = _makerBalanceAndLiquidityOf(account);
        return balance;
    }

    function liquidity(address account, address pair) public onlyRouter returns (bool) {
        require(account != address(0), "BtswapToken: maker liquidity account is the zero address");
        require(pair != address(0), "BtswapToken: maker liquidity pair is the zero address");

        mint();
        
        User storage user = maker.users[account];
        uint256 deposit = rebalance(account, pair);
        uint256 previous = makerLastDepositOf(account, pair);

        (uint256 m, uint256 n) = liquidityOf(account);
        maker.quantity = m;
        maker.timestamp = block.number;
        maker.deposit = makerDepositOfPool().add(deposit).sub(previous);

        user.quantity = n;
        user.timestamp = block.number;
        user.deposit = makerDepositOf(account).add(deposit).sub(previous);
        user.deposits[pair] = deposit;

        return true;
    }

    function _makerWithdraw(address account) internal returns (bool) {
        require(account != address(0), "BtswapToken: maker withdraw account is the zero address");

        (uint256 withdrawn, uint256 m, uint256 n) = _makerBalanceAndLiquidityOf(account);
        if (withdrawn <= 0) {
            return false;
        }

        User storage user = maker.users[account];
        maker.timestamp = block.number;
        maker.quantity = m.sub(n);
        user.timestamp = block.number;
        user.quantity = 0;

        _transfer(MAKER_ADDRESS, account, withdrawn);

        return true;
    }

    function makerWithdraw() public returns (bool) {
        mint();

        return _makerWithdraw(msg.sender);
    }


    /**
     * group
     */
    function groupBalanceOf() public view returns (uint256) {
        return balanceOf(GROUP_ADDRESS);
    }

    function groupWithdraw(address account, uint256 amount) public onlyOwner returns (bool) {
        require(account != address(0), "BtswapToken: group withdraw account is the zero address");
        require(amount > 0, "BtswapToken: group withdraw amount is the zero value");
        require(groupBalanceOf() >= amount, "BtswapToken: group withdraw amount exceeds group balance");

        _transfer(GROUP_ADDRESS, account, amount);

        return true;
    }


    /**
     * modifier
     */
    function isMintable() public view returns (bool) {
        if (block.number.sub(lastMintBlock()) > 0 && reward(lastMintBlock()) > 0) {
            return true;
        }
        return false;
    }

    function isRouter(address account) public view returns (bool) {
        return account == address(router());
    }

    modifier onlyRouter() {
        require(isRouter(msg.sender), "BtswapToken: caller is not the router");
        _;
    }

}