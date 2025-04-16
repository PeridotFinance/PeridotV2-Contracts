// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IComptroller {
    function enterMarkets(
        address[] calldata cTokens
    ) external returns (uint[] memory);

    function exitMarket(address cToken) external returns (uint);

    function getAccountLiquidity(
        address account
    ) external view returns (uint, uint, uint);

    function checkMembership(
        address account,
        address cToken
    ) external view returns (bool);
}

interface ICToken {
    function mint(uint mintAmount) external returns (uint);

    function redeem(uint redeemTokens) external returns (uint);

    function redeemUnderlying(uint redeemAmount) external returns (uint);

    function borrow(uint borrowAmount) external returns (uint);

    function repayBorrow(uint repayAmount) external returns (uint);

    function balanceOf(address owner) external view returns (uint);

    function borrowBalanceCurrent(address account) external returns (uint);

    function exchangeRateCurrent() external returns (uint);
}
