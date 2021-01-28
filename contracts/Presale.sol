// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./GameForth.sol";
import "hardhat/console.sol";

contract Presale is Context, Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    mapping(address => uint256) public balances;
    mapping(address => bool) public whitelist;

    mapping(string => address) private rec;

    uint256 public max = 3 ether;
    uint256 public min = 0.1 ether;
    uint256 public cap = 200 ether;
    uint256 public recev = 0;

    bool public active = false;
    GameForth public gameforth;

    function presale(string memory rx) public payable returns (bool) {
        require(
            msg.value >= min &&
                (balances[msg.sender].add(msg.value) < max ||
                    whitelist[msg.sender]) &&
                active,
            "Value too small or too high or presale inactive"
        );
        balances[msg.sender] = balances[msg.sender].add(msg.value);
        recev = recev + msg.value;

        uint256 alloc = msg.value.mul(2).div(10);
        if (rec[rx] != address(0)) {
            uint256 rew = alloc.div(10);
            alloc = alloc.sub(rew);
            payable(rec[rx]).transfer(rew);
        }
        payable(owner()).transfer(alloc);
        uint256 toTransfer = msg.value.div(10**9).mul(30);

        gameforth.transfer(msg.sender, toTransfer);
    }

    function list() public onlyOwner() {
        address router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
        uint256 numList = address(this).balance.div(10**9).mul(25);
        gameforth.approve(router, numList);
        gameforth.unlimit();
        IUniswapV2Router02(router).addLiquidityETH{
            value: address(this).balance
        }(
            address(gameforth),
            numList,
            numList,
            address(this).balance,
            address(0), // destination of LP tokens
            block.timestamp + 600
        );

        active = false;
    }

    function setGameForth(address payable addr) public onlyOwner {
        require(address(gameforth) == address(0), "already set");
        gameforth = GameForth(addr);
        active = true;
    }

    function addWhitelist(address payable addr) public onlyOwner {
        whitelist[addr] = true;
    }

    function endSale() public onlyOwner {
        active = false;
    }
}
