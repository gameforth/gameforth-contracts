// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/lib/contracts/libraries/FixedPoint.sol';

import '@uniswap/v2-periphery/contracts/libraries/UniswapV2OracleLibrary.sol';
import '../lib/UniswapV2Library.sol'; // Needed because solidity 0.6.12

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/v0.6/interfaces/AggregatorV3Interface.sol";

interface GameForthInterface {
    function pushReport(uint256 payload) external;

    function purgeReports() external;
}

/**
 * @title TokenUniswapConsumer is a contract which is given data by a server
 * @dev This contract is designed to work on multiple networks, including
 * local test networks
 */
contract TokenUniswapConsumer is Ownable {
    using SafeMath for uint256;
    using FixedPoint for *;

    uint public constant PERIOD = 24 hours;

    IUniswapV2Pair immutable pair;
    address public immutable gameForth;
    address public immutable wETH;
    GameForthInterface public gameForthOracle;
    mapping(address => bool) public authorizedRequesters;
    uint256 public updatedHeight;

    AggregatorV3Interface internal priceFeed;

    uint    public price0CumulativeLast;
    uint    public price1CumulativeLast;
    uint32  public blockTimestampLast;
    FixedPoint.uq112x112 public price0Average;
    FixedPoint.uq112x112 public price1Average;

    constructor(address factory, address _gameForth, address _wETH, address _gameForthOracle, address _chainlinkETHUSD) public {
        IUniswapV2Pair _pair = IUniswapV2Pair(UniswapV2Library.pairFor(factory, _gameForth, _wETH));
        pair = _pair;
        gameForth = _pair.token0();
        wETH = _pair.token1();
        gameForthOracle = GameForthInterface(_gameForthOracle);
        priceFeed = AggregatorV3Interface(_chainlinkETHUSD);
        price0CumulativeLast = _pair.price0CumulativeLast(); // fetch the current accumulated price value (1 / 0)
        price1CumulativeLast = _pair.price1CumulativeLast(); // fetch the current accumulated price value (0 / 1)
        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, blockTimestampLast) = _pair.getReserves();
        require(reserve0 != 0 && reserve1 != 0, 'TokenUniswapConsumer: NO_RESERVES'); // ensure that there's liquidity in the pair
    }

    function update() private {
        (uint price0Cumulative, uint price1Cumulative, uint32 blockTimestamp) =
            UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

        // ensure that at least one full period has passed since the last update
        require(timeElapsed >= PERIOD, 'TokenUniswapConsumer: PERIOD_NOT_ELAPSED');

        // overflow is desired, casting never truncates
        // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast) / timeElapsed));
        price1Average = FixedPoint.uq112x112(uint224((price1Cumulative - price1CumulativeLast) / timeElapsed));

        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = blockTimestamp;
    }

    /*
     * @notice Creates a request to the stored Oracle contract address
     */
    function requestPushReport()
        external
        ensureAuthorizedRequester()
        returns (uint256 rGMEInUSD)
    {
        update();

        (
             , 
            int ETHUSD,
             ,
             ,
             
        ) = priceFeed.latestRoundData();
        // we know how much USD (with 8 decimals) ETH costs

        uint256 newETHUSD = uint(ETHUSD).mul(10**1); // now 9 decimals
        uint256 rGMEInETH = price1Average.mul(1).decode144(); // with 9 decimal places

        rGMEInUSD = newETHUSD.mul(rGMEInETH); // current price of rGME in USD via ETH as proxy

        updatedHeight = block.number;
        gameForthOracle.pushReport(uint256(rGMEInUSD));
    }

    /**
     * @notice Called by the owner to permission other addresses to generate new
     * requests to oracles.
     * @param _requester the address whose permissions are being set
     * @param _allowed boolean that determines whether the requester is
     * permissioned or not
     */
    function setAuthorization(address _requester, bool _allowed)
        public
        onlyOwner()
    {
        authorizedRequesters[_requester] = _allowed;
    }    
    
    /**
     * @notice Calls contract's purge function
     */
    function purgeReports() external onlyOwner() {
        gameForthOracle.purgeReports();
    }


    /**
     * @dev Reverts if `msg.sender` is not authorized to make requests.
     */
    modifier ensureAuthorizedRequester() {
        require(
            authorizedRequesters[msg.sender] || msg.sender == owner(),
            "Unauthorized to create requests"
        );
        _;
    }
}
