// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";

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

}
