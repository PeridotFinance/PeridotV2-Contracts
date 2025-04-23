// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "./interfaces/INttToken.sol";

/**
 * @title MyNttToken
 * @dev Basic ERC20 token implementation compatible with Wormhole NTT (Native Token Transfer)
 *      in burn/mint mode by implementing the INttToken interface.
 *      Uses OpenZeppelin contracts for standard ERC20 and Burnable features.
 */
contract NTTToken is ERC20, ERC20Burnable, INttToken {
    address private _minter;
    uint public INITIAL_SUPPLY = 10000000e18;

    /**
     * @notice Modifier to check if the caller is the designated minter.
     * @dev Reverts with CallerNotMinter error if caller is not the minter.
     */
    modifier onlyMinter() {
        if (msg.sender != _minter) {
            revert CallerNotMinter(msg.sender);
        }
        _;
    }

    /**
     * @notice Constructor to initialize the token name, symbol, and set the deployer as the initial minter.
     * @param name_ The name of the token.
     * @param symbol_ The symbol of the token.
     */
    constructor(
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {
        // Set the deployer as the initial minter
        address initialMinter = msg.sender;
        if (initialMinter == address(0)) {
            // Although msg.sender cannot be zero, this check aligns with setMinter logic
            revert InvalidMinterZeroAddress();
        }
        _minter = initialMinter;
        emit NewMinter(address(0), _minter);

        // Mint initial supply to deployer (Optional)
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    /**
     * @notice Sets the minter address.
     * @dev Can only be called by the current minter.
     *      Reverts if the newMinter is the zero address.
     * @param newMinter The address of the new minter.
     */
    function setMinter(address newMinter) external override onlyMinter {
        if (newMinter == address(0)) {
            revert InvalidMinterZeroAddress();
        }
        address oldMinter = _minter;
        _minter = newMinter;
        emit NewMinter(oldMinter, newMinter);
    }

    /**
     * @notice Mints tokens to a specified account.
     * @dev Can only be called by the minter.
     * @param account The address that will receive the minted tokens.
     * @param amount The amount of tokens to mint.
     */
    function mint(
        address account,
        uint256 amount
    ) external override onlyMinter {
        _mint(account, amount);
    }

    /**
     * @notice Returns the address of the current minter.
     */
    function minter() external view returns (address) {
        return _minter;
    }

    /**
     * @notice Burns a specific amount of tokens from the caller's account.
     * @dev Inherited from ERC20Burnable, fulfills the INttToken requirement.
     * @param amount The amount of tokens to burn.
     */

    function burn(uint256 amount) public override(ERC20Burnable, INttToken) {
        uint256 balance = balanceOf(msg.sender);
        if (balance < amount) {
            revert InsufficientBalance(balance, amount); // Use the interface's custom error
        }
        super.burn(amount); // Call the original ERC20Burnable burn logic
    }
}
