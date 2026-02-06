// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/* TicketToken (ERC-20)
minted as a reward for contributions ("tickets")
no real monetary value (educational/testnet only)
 only the Crowdfunding contract is allowed to mint */
contract TicketToken is ERC20, Ownable {
    address public minter; 

    event MinterUpdated(address indexed oldMinter, address indexed newMinter);

    constructor(
        string memory name_,
        string memory symbol_,
        address owner_
    ) ERC20(name_, symbol_) Ownable(owner_) {}

    modifier onlyMinter() {
        require(msg.sender == minter, "TicketToken: not minter");
        _;
    }

    /* owner sets which contract is allowed to mint
     call this once after deploying the crowdfunding contract */
    function setMinter(address newMinter) external onlyOwner {
        require(newMinter != address(0), "TicketToken: zero address");
        emit MinterUpdated(minter, newMinter);
        minter = newMinter;
    }

    /* mint "ticket" tokens to a user. Only minter can call 
    amount is in smallest units (like wei).if you want "1 token" 
    use 1 * 10**decimals() */
    function mint(address to, uint256 amount) external onlyMinter {
        require(to != address(0), "TicketToken: zero address");
        require(amount > 0, "TicketToken: amount=0");
        _mint(to, amount);
    }
}
