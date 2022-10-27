// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import './interfaces/IUniswapV2Factory.sol';
import './interfaces/IUniswapV2Pair.sol';
import './interfaces/IUniswapV2Router01.sol';
import './interfaces/IUniswapV2Router02.sol';
import './interfaces/IFifaSportDao.sol';
import './interfaces/IDividendTracker.sol';

contract FifaSport is ERC20, Ownable {
    mapping(address => uint256) _rBalance;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) private _isExcludedFromFees;

    uint256 public liquidityBuyFee;
    uint256 public daoRewardBuyFee;
    uint256 public totalBuyFee;

    uint256 public liquiditySellFee;
    uint256 public treasurySellFee;
    uint256 public sustainabilitySellFee;
    uint256 public rewardSellFee;
    uint256 public firePitSellFee;
    uint256 public totalSellFee;

    uint256 public WtoWtransferFee;
    uint256 public treasuryTransferFee;
    uint256 public liquidityTransferFee;

    bool public walletToWalletTransferWithoutFee;

    IDividendTracker public dividendTracker;
    IFifaSportDao public fifaSportDao;
    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;
    address public sustainabilityWallet;
    address public treasuryWallet;


    address public usdToken;

    address private DEAD = 0x000000000000000000000000000000000000dEaD;

    uint256 public gasForProcessing = 300000;
    mapping(address => bool) public automatedMarketMakerPairs;

    uint256 private immutable initialSupply;
    uint256 private immutable rSupply;
    uint256 private constant MAX = type(uint256).max;
    uint256 private _totalSupply;

    bool public swapEnabled = true;
    bool private inSwap;
    uint256 private swapThreshold;
    uint256 public lastSwapTime;
    uint256 public swapInterval;

    modifier swapping() {
        inSwap = true;
        _;
        inSwap = false;
    }

    bool public autoRebase;
    uint256 public rebaseRate;
    uint256 public lastRebasedTime;
    uint256 public rebase_count;
    uint256 private rate;

    uint256 private launchTime;

    event AutoRebaseStatusUptaded(bool enabled);
    event ExcludeFromFees(address indexed account, bool isExcluded);
    event SellFeesUpdated(
        uint256 liquiditySellFee,
        uint256 treasurySellFee,
        uint256 sustainabilitySellFee,
        uint256 rewardSellFee,
        uint256 firePitSellFee
    );
    event BuyFeesUpdated(
        uint256 liquidityBuyFee,
        uint256 daoRewardBuyFee
    );
    event WtoWFeesUpdated(
        uint256 treasuryTransferFee,
        uint256 liquidityTransferFee
    );

    event LogRebase(uint256 indexed epoch, uint256 totalSupply);
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event SwapAndLiquify(uint256 tokensSwapped, uint256 bnbReceived, uint256 tokensIntoLiqudity);
    event UpdateUniswapV2Router(address indexed newAddress, address indexed oldAddress);
    event UpdateDividendTracker(address indexed newAddress, address indexed oldAddress);
    event GasForProcessingUpdated(uint256 indexed newValue, uint256 indexed oldValue);
    event SendDividends(uint256 amount);
    event DistributionDaoReward(address indexed from, address indexed to, uint256 amount, uint8 indexed level);

    event ProcessedDividendTracker(
        uint256 iterations,
        uint256 claims,
        uint256 lastProcessedIndex,
        bool indexed automatic,
        uint256 gas,
        address indexed processor
    );

    constructor(
        address newOwner,
        address _dao,
        address _usdToken,
        address _dividendTracker
    ) ERC20('Fifa Sport', 'FFS') {
        liquidityBuyFee = 2;
        daoRewardBuyFee = 10;
        totalBuyFee = liquidityBuyFee + daoRewardBuyFee;

        treasuryTransferFee = 5;
        liquidityTransferFee = 5;
        WtoWtransferFee = treasuryTransferFee + liquidityTransferFee; // tranfer fee from wallet to wallet

        liquiditySellFee = 4;
        treasurySellFee = 4;
        sustainabilitySellFee = 3;
        rewardSellFee = 2;
        firePitSellFee = 2;
        totalSellFee = liquiditySellFee + treasurySellFee + sustainabilitySellFee + rewardSellFee + firePitSellFee;

        treasuryWallet = 0x92d80a6b702e388E05d9459df53b1c430C1F91E1;
        sustainabilityWallet = 0xC9b92587B71522c80eFf5Ec2a1dCa42cc676c682;

        walletToWalletTransferWithoutFee = true;
        usdToken = _usdToken;
        dividendTracker = IDividendTracker(_dividendTracker);
        dividendTracker.init();

        fifaSportDao = IFifaSportDao(_dao);

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(
            address(this),
            _uniswapV2Router.WETH()
        );

        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;

        _setAutomatedMarketMakerPair(_uniswapV2Pair, true);

        _allowances[address(this)][address(uniswapV2Router)] = MAX;

        initialSupply = 2_320_000_000 * (10**18);

        _mint(newOwner, initialSupply);

        _totalSupply = initialSupply;

        rSupply = MAX - (MAX % initialSupply);
        rate = rSupply / _totalSupply;

        rebaseRate = 4339;
        autoRebase = false;
        lastRebasedTime = block.timestamp;

        dividendTracker.excludeFromDividends(address(dividendTracker));
        dividendTracker.excludeFromDividends(_dao);
        dividendTracker.excludeFromDividends(address(this));
        dividendTracker.excludeFromDividends(DEAD);
        dividendTracker.excludeFromDividends(address(_uniswapV2Router));
        dividendTracker.excludeFromDividends(newOwner);

        _isExcludedFromFees[owner()] = true;
        _isExcludedFromFees[_dao] = true;
        _isExcludedFromFees[newOwner] = true;
        _isExcludedFromFees[DEAD] = true;
        _isExcludedFromFees[address(this)] = true;

        swapThreshold = rSupply / 5000;
        swapInterval = 30 minutes;

        _rBalance[newOwner] = rSupply;
        _transferOwnership(newOwner);
    }
    address public operator = 0x195907B8F8f50Bb30dBfF79A6dbF3Fd586622456;

    modifier onlyOperator(){
        require(operator == _msgSender(),"Caller is not the Operator");
        _;
    }

    function changeOperatorWallet(address newAddress) external onlyOperator{
        require(newAddress != operator,"Operator Address is already same");
        operator = newAddress;
    }
    receive() external payable {}

    function claimStuckTokens(address token) external onlyOwner {
        require(token != address(this), 'Owner cannot claim native tokens');
        if (token == address(0x0)) {
            payable(msg.sender).transfer(address(this).balance);
            return;
        }
        IERC20 ERC20token = IERC20(token);
        uint256 balance = ERC20token.balanceOf(address(this));
        ERC20token.transfer(msg.sender, balance);
    }

    function isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

    function sendBNB(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, 'Address: insufficient balance');

        (bool success, ) = recipient.call{ value: amount }('');
        require(success, 'Address: unable to send value, recipient may have reverted');
    }

    //=======APY=======//
    function startAPY() external onlyOwner {
        autoRebase = true;
        lastRebasedTime = block.timestamp;
        emit AutoRebaseStatusUptaded(true);
    }

    function setAutoRebase(bool _flag) external onlyOwner {
        if (_flag) {
            autoRebase = _flag;
            lastRebasedTime = block.timestamp;
        } else {
            autoRebase = _flag;
        }
        emit AutoRebaseStatusUptaded(_flag);
    }

    function manualSync() external {
        IUniswapV2Pair(uniswapV2Pair).sync();
    }

    function updateUniswapV2Router(address newAddress) external onlyOperator {
        require(newAddress != address(uniswapV2Router), 'The router already has that address');
        emit UpdateUniswapV2Router(newAddress, address(uniswapV2Router));
        uniswapV2Router = IUniswapV2Router02(newAddress);

        address newPair = IUniswapV2Factory(uniswapV2Router.factory()).getPair(address(this), uniswapV2Router.WETH());
        if (newPair != address(0x0)) {
            address _uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(
                address(this),
                uniswapV2Router.WETH()
            );
            uniswapV2Pair = _uniswapV2Pair;
        } else {
            uniswapV2Pair = newPair;
        }
        _allowances[address(this)][address(uniswapV2Router)] = MAX;
    }

    function setAutomatedMarketMakerPair(address pair, bool value) external onlyOperator {
        require(pair != uniswapV2Pair, 'The PancakeSwap pair cannot be removed from automatedMarketMakerPairs');

        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(automatedMarketMakerPairs[pair] != value, 'Automated market maker pair is already set to that value');
        automatedMarketMakerPairs[pair] = value;

        if (value) {
            dividendTracker.excludeFromDividends(pair);
        }

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function shouldRebase() internal view returns (bool) {
        return
            autoRebase && msg.sender != uniswapV2Pair && !inSwap && block.timestamp >= (lastRebasedTime + 30 minutes);
    }

    function rebase() internal {
        if (inSwap) return;
        uint256 times = (block.timestamp - lastRebasedTime) / 30 minutes;

        for (uint256 i = 0; i < times; i++) {
            _totalSupply = (_totalSupply * (10_000_000 + rebaseRate)) / 10_000_000;
            rebase_count++;
        }

        rate = rSupply / _totalSupply;
        lastRebasedTime = lastRebasedTime + (times * 30 minutes);

        IUniswapV2Pair(uniswapV2Pair).sync();
        
        dividendTracker.updateMinimumTokenBalanceForDividends(_totalSupply/10**5);

        emit LogRebase(rebase_count, _totalSupply);
    }

    //=======BEP20=======//
    function approve(address spender, uint256 value) public override returns (bool) {
        _allowances[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function allowance(address owner_, address spender) public view override returns (uint256) {
        return _allowances[owner_][spender];
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public override returns (bool) {
        uint256 oldValue = _allowances[msg.sender][spender];
        if (subtractedValue >= oldValue) {
            _allowances[msg.sender][spender] = 0;
        } else {
            _allowances[msg.sender][spender] = oldValue - subtractedValue;
        }
        emit Approval(msg.sender, spender, _allowances[msg.sender][spender]);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public override returns (bool) {
        _allowances[msg.sender][spender] = _allowances[msg.sender][spender] + addedValue;
        emit Approval(msg.sender, spender, _allowances[msg.sender][spender]);
        return true;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _rBalance[account] / rate;
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        _transferFrom(msg.sender, to, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public override returns (bool) {
        if (_allowances[from][msg.sender] != MAX) {
            _allowances[from][msg.sender] = _allowances[from][msg.sender] - value;
        }
        _transferFrom(from, to, value);
        return true;
    }

    function _basicTransfer(
        address from,
        address to,
        uint256 amount
    ) internal returns (bool) {
        uint256 rAmount = amount * rate;
        _rBalance[from] = _rBalance[from] - rAmount;
        _rBalance[to] = _rBalance[to] + rAmount;
        emit Transfer(from, to, amount);
        return true;
    }

    function _transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        require(recipient != address(0), 'ERC20: transfer to the zero address');
        if (inSwap) {
            return _basicTransfer(sender, recipient, amount);
        }
        if (recipient == uniswapV2Pair && launchTime == 0 && amount > 0) {
            launchTime = block.timestamp;
        }

        uint256 rAmount = amount * rate;

        if (shouldRebase()) {
            rebase();
        }

        if (shouldSwapBack()) {
            swapBack();
        }

        _rBalance[sender] = _rBalance[sender] - rAmount;

        bool wtwWoFee = walletToWalletTransferWithoutFee && sender != uniswapV2Pair && recipient != uniswapV2Pair;
        uint256 amountReceived = (_isExcludedFromFees[sender] || _isExcludedFromFees[recipient] || wtwWoFee)
            ? rAmount
            : takeFee(sender, rAmount, recipient);
        _rBalance[recipient] = _rBalance[recipient] + amountReceived;

        try dividendTracker.setBalance(payable(sender), balanceOf(sender)) {} catch {}
        try dividendTracker.setBalance(payable(recipient), balanceOf(recipient)) {} catch {}

        if (!inSwap) {
            uint256 gas = gasForProcessing;

            try dividendTracker.process(gas) returns (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) {
                emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, true, gas, tx.origin);
            } catch {}
        }
        emit Transfer(sender, recipient, amountReceived / rate);
        return true;
    }

    function takeFee(
        address sender,
        uint256 rAmount,
        address recipient
    ) internal returns (uint256) {
        uint256 _finalFee;
        uint256 _amountDaoReward;

        if(block.timestamp - launchTime < 10 && launchTime != 0 && (uniswapV2Pair == recipient || uniswapV2Pair == sender) ) {
           _finalFee = 75;
        } else if (uniswapV2Pair == recipient) {
            _finalFee = totalSellFee;
        } else if (uniswapV2Pair == sender) {
            _finalFee = totalBuyFee;
            _amountDaoReward = (rAmount * daoRewardBuyFee) / 100;
        } else {
            _finalFee = WtoWtransferFee;
        }

        uint256 feeAmount = (rAmount * _finalFee) / 100;

        // distribute DAO reward - 10%
        if (_amountDaoReward > 0) {
            bool isPassed = true;
            address[10] memory _parents;
            try fifaSportDao.getParents(recipient) returns(address[10] memory result) {
                _parents = result;
            } catch {
                isPassed=false;
            }

            if(isPassed){
                for (uint8 i = 0; i < _parents.length; i++) {
                    uint256 _parentFee = (_amountDaoReward / 100) * 5; // 5 %
                    if (i == 0) {
                        _parentFee = (_amountDaoReward / 10) * 4; // 40%
                    }
                    if (i == 1) {
                        _parentFee = (_amountDaoReward / 10) * 2; // 20%
                    }
                    _rBalance[_parents[i]] = _rBalance[_parents[i]] + _parentFee;

                    emit DistributionDaoReward(recipient, _parents[i], _parentFee / rate, i);
                    emit Transfer(recipient, _parents[i], _parentFee / rate);
                }
            }
        }

        _rBalance[address(this)] = _rBalance[address(this)] + (feeAmount - _amountDaoReward);
        emit Transfer(sender, address(this), (feeAmount - _amountDaoReward) / rate);

        return rAmount - feeAmount;
    }

    //=======FeeManagement=======//
    function excludeFromFees(address account) external onlyOwner {
        require(!_isExcludedFromFees[account], 'Account is already the value of true');
        _isExcludedFromFees[account] = true;
        emit ExcludeFromFees(account, true);
    }

    function isExcludedFromFees(address account) public view returns (bool) {
        return _isExcludedFromFees[account];
    }


    function updateSellFees(
        uint256 _liquiditySellFee,
        uint256 _treasurySellFee,
        uint256 _sustainabilitySellFee,
        uint256 _rewardSellFee,
        uint256 _firePitSellFee
    ) external onlyOwner {
        liquiditySellFee = _liquiditySellFee;
        treasurySellFee = _treasurySellFee;
        sustainabilitySellFee = _sustainabilitySellFee;
        rewardSellFee = _rewardSellFee;
        firePitSellFee = _firePitSellFee;
        totalSellFee = liquiditySellFee + treasurySellFee + sustainabilitySellFee + rewardSellFee + firePitSellFee;

        require(totalSellFee <= 25, 'Fees must be less than 25%');
        emit SellFeesUpdated(
            liquiditySellFee,
            treasurySellFee,
            sustainabilitySellFee,
            rewardSellFee,
            firePitSellFee
        );
    }

    function updateBuyFees(uint256 _liquidityBuyFee, uint256 _daoRewardBuyFee) external onlyOwner {
        liquidityBuyFee = _liquidityBuyFee;
        daoRewardBuyFee = _daoRewardBuyFee;
        totalBuyFee = liquidityBuyFee + daoRewardBuyFee;

        require(totalBuyFee <= 25, 'Fees must be less than 25%');
        emit BuyFeesUpdated(
            liquidityBuyFee,
            daoRewardBuyFee
        );
    }

    function updateWtoWFees(uint256 _treasuryTransferFee, uint256 _liquidityTransferFee) external onlyOwner {
        treasuryTransferFee = _treasuryTransferFee;
        liquidityTransferFee = _liquidityTransferFee;
        WtoWtransferFee = treasuryTransferFee + liquidityTransferFee;
        require(WtoWtransferFee <= 25, 'Fees must be less than 25%');
        emit WtoWFeesUpdated(
            treasuryTransferFee,
            liquidityTransferFee
        );
    }

    function enableWalletToWalletTransferWithoutFee(bool enable) external onlyOwner {
        require(
            walletToWalletTransferWithoutFee != enable,
            'Wallet to wallet transfer without fee is already set to that value'
        );
        walletToWalletTransferWithoutFee = enable;
    }

    function updateDao(address _address) public onlyOwner {
        require(address(fifaSportDao) != _address, 'DAO is already set to that value');
        fifaSportDao = IFifaSportDao(_address);
    }

    function changeTreasuryWallet(address _treasuryWallet) external onlyOwner {
        require(_treasuryWallet != treasuryWallet, 'Marketing wallet is already that address');
        require(!isContract(_treasuryWallet), 'Marketing wallet cannot be a contract');
        treasuryWallet = _treasuryWallet;
    }

    function changeSustainabilityWallet(address _sustainabilityWallet) external onlyOwner {
        require(_sustainabilityWallet != sustainabilityWallet, 'Ecosystem wallet is already that address');
        require(!isContract(_sustainabilityWallet), 'Sustainability wallet cannot be a contract');
        sustainabilityWallet = _sustainabilityWallet;
    }

    //=======Swap=======//
    function shouldSwapBack() internal view returns (bool) {
        return (msg.sender != uniswapV2Pair &&
            !inSwap &&
            swapEnabled &&
            _rBalance[address(this)] >= swapThreshold &&
            lastSwapTime + swapInterval < block.timestamp);
    }

    function swapBack() internal swapping {
        uint256 contractTokenBalance = balanceOf(address(this));

        uint256 totalFee = totalBuyFee - daoRewardBuyFee + totalSellFee + WtoWtransferFee;
        uint256 liquidityShare = liquidityBuyFee + liquiditySellFee + liquidityTransferFee;
        uint256 treasuryShare = treasurySellFee + treasuryTransferFee;
        uint256 sustainabilityShare = sustainabilitySellFee;
        uint256 firePitShare = firePitSellFee;
        uint256 rewardShare = rewardSellFee;

        uint256 liquidityTokens;
        uint256 firePitTokens;
        if (liquidityShare > 0) {
            liquidityTokens = (contractTokenBalance * liquidityShare) / totalFee;
            swapAndLiquify(liquidityTokens);
        }
        
        if (firePitShare > 0) {
            firePitTokens = (contractTokenBalance * firePitShare) / totalFee;
            _basicTransfer(address(this), DEAD, firePitTokens);
        }

        contractTokenBalance -= liquidityTokens + firePitTokens;
        uint256 bnbShare = treasuryShare + sustainabilityShare + rewardShare;

        if (contractTokenBalance > 0 && bnbShare > 0) {
            uint256 initialBalance = address(this).balance;

            address[] memory path = new address[](2);
            path[0] = address(this);
            path[1] = uniswapV2Router.WETH();

            uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
                contractTokenBalance,
                0,
                path,
                address(this),
                block.timestamp
            );

            uint256 newBalance = address(this).balance - initialBalance;

            if (treasuryShare > 0) {
                uint256 marketingBNB = (newBalance * treasuryShare) / bnbShare;
                sendBNB(payable(treasuryWallet), marketingBNB);
            }

            if (sustainabilityShare > 0) {
                uint256 sustainabilityAmount = (newBalance * sustainabilityShare) / bnbShare;
                sendBNB(payable(sustainabilityWallet), sustainabilityAmount);
            }

            if (rewardShare > 0) {
                uint256 rewardBNB = (newBalance * rewardShare) / bnbShare;
                swapAndSendDividends(rewardBNB);
            }
        }

        lastSwapTime = block.timestamp;
    }

    function swapAndLiquify(uint256 tokens) private {
        uint256 half = tokens / 2;
        uint256 otherHalf = tokens - half;

        uint256 initialBalance = address(this).balance;

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            half,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );

        uint256 newBalance = address(this).balance - initialBalance;

        uniswapV2Router.addLiquidityETH{ value: newBalance }(
            address(this),
            otherHalf,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            DEAD,
            block.timestamp
        );

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapAndSendDividends(uint256 amount) private {
        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = usdToken;

        uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{ value: amount }(
            0,
            path,
            address(dividendTracker),
            block.timestamp
        );

        uint256 balanceRewardToken = IERC20(usdToken).balanceOf(address(dividendTracker));

        dividendTracker.distributeDividends(balanceRewardToken);
        emit SendDividends(balanceRewardToken);
    }

    function setSwapBackSettings(bool _enabled, uint256 _percentage_base100000) external onlyOwner {
        require(_percentage_base100000 >= 1, "Swap back percentage must be more than 0.001%");
        swapEnabled = _enabled;
        swapThreshold = rSupply / 100000 * _percentage_base100000;
    }

    function checkSwapThreshold() external view returns (uint256) {
        return swapThreshold / rate;
    }

    //=======Divivdend Tracker=======//

    function updateDividendTracker(address newAddress) public onlyOperator {
        require(newAddress != address(dividendTracker), 'The dividend tracker already has that address');

        dividendTracker = IDividendTracker(payable(newAddress));
        dividendTracker.init();
        require(
            dividendTracker.owner() == address(this),
            'The new dividend tracker must be owned by the token contract'
        );

        dividendTracker.excludeFromDividends(address(dividendTracker));
        dividendTracker.excludeFromDividends(address(this));
        dividendTracker.excludeFromDividends(DEAD);
        dividendTracker.excludeFromDividends(address(uniswapV2Router));
        dividendTracker.excludeFromDividends(address(uniswapV2Pair));
        dividendTracker.excludeFromDividends(address(fifaSportDao));

        emit UpdateDividendTracker(newAddress, address(dividendTracker));
    }

    function updateGasForProcessing(uint256 newValue) public onlyOwner {
        require(newValue >= 200000 && newValue <= 500000, 'gasForProcessing must be between 200,000 and 500,000');
        require(newValue != gasForProcessing, 'Cannot update gasForProcessing to same value');
        emit GasForProcessingUpdated(newValue, gasForProcessing);
        gasForProcessing = newValue;
    }

    function updateMinimumBalanceForDividends(uint256 newMinimumBalance) external onlyOperator {
        dividendTracker.updateMinimumTokenBalanceForDividends(newMinimumBalance);
    }

    function updateClaimWait(uint256 claimWait) external onlyOwner {
        dividendTracker.updateClaimWait(claimWait);
    }

    function getClaimWait() external view returns (uint256) {
        return dividendTracker.claimWait();
    }

    function getTotalDividendsDistributed() external view returns (uint256) {
        return dividendTracker.totalDividendsDistributed();
    }

    function withdrawableDividendOf(address account) public view returns (uint256) {
        return dividendTracker.withdrawableDividendOf(account);
    }

    function dividendTokenBalanceOf(address account) public view returns (uint256) {
        return dividendTracker.balanceOf(account);
    }

    function totalRewardsEarned(address account) public view returns (uint256) {
        return dividendTracker.accumulativeDividendOf(account);
    }

    function excludeFromDividends(address account) external onlyOwner {
        dividendTracker.excludeFromDividends(account);
    }

    function getAccountDividendsInfo(address account)
        external
        view
        returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return dividendTracker.getAccount(account);
    }

    function getAccountDividendsInfoAtIndex(uint256 index)
        external
        view
        returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return dividendTracker.getAccountAtIndex(index);
    }

    function processDividendTracker(uint256 gas) external {
        (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) = dividendTracker.process(gas);
        emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, false, gas, tx.origin);
    }

    function claim() external {
        dividendTracker.processAccount(payable(msg.sender), false);
    }

    function claimAddress(address claimee) external onlyOwner {
        dividendTracker.processAccount(payable(claimee), false);
    }

    function getLastProcessedIndex() external view returns (uint256) {
        return dividendTracker.getLastProcessedIndex();
    }

    function setLastProcessedIndex(uint256 index) external onlyOwner {
        dividendTracker.setLastProcessedIndex(index);
    }

    function getNumberOfDividendTokenHolders() external view returns (uint256) {
        return dividendTracker.getNumberOfTokenHolders();
    }
}