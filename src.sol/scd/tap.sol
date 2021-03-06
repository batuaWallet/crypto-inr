// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2017  Nikolai Mushegian <nikolai@dapphub.com>
// Copyright (C) 2017  Daniel Brockman <daniel@dapphub.com>
// Copyright (C) 2017  Rain Break <rainbreak@riseup.net>

// tap.sol -- liquidation engine (see also `vow`)

pragma solidity ^0.7.0;

import "./tub.sol";

contract SaiTap is DSThing {
    DSToken  public  sai;
    DSToken  public  sin;
    DSToken  public  skr;

    SaiVox   public  vox;
    SaiTub   public  tub;

    uint256  public  gap;  // Boom-Bust Spread
    bool     public  off;  // Cage flag
    uint256  public  fix;  // Cage price

    // Surplus
    function joy() public view returns (uint) {
        return sai.balanceOf(address(this));
    }
    // Bad debt
    function woe() public view returns (uint) {
        return sin.balanceOf(address(this));
    }
    // Collateral pending liquidation
    function fog() public view returns (uint) {
        return skr.balanceOf(address(this));
    }

    constructor(SaiTub tub_) {
        tub = tub_;

        sai = tub.sai();
        sin = tub.sin();
        skr = tub.skr();

        vox = tub.vox();

        gap = WAD;
    }

    function mold(bytes32 param, uint val) public payable note auth {
        if (param == "gap") gap = val;
    }

    // Cancel debt
    function heal() public payable note {
        if (joy() == 0 || woe() == 0) return;  // optimised
        uint wad = min(joy(), woe());
        sai.burn(wad);
        sin.burn(wad);
    }

    // Feed price (sai per skr)
    function s2s() public returns (uint) {
        uint tag = tub.tag();    // ref per skr
        uint256 par = vox.par();    // ref per sai
        return rdiv(tag, par);  // sai per skr
    }
    // Boom price (sai per skr)
    function bid(uint wad) public returns (uint) {
        return rmul(wad, wmul(s2s(), sub(2 * WAD, gap)));
    }
    // Bust price (sai per skr)
    function ask(uint wad) public returns (uint) {
        return rmul(wad, wmul(s2s(), gap));
    }
    function flip(uint wad) internal {
        require(ask(wad) > 0);
        skr.push(msg.sender, wad);
        sai.pull(msg.sender, ask(wad));
        heal();
    }
    function flop(uint wad) internal {
        skr.mint(sub(wad, fog()));
        flip(wad);
        require(joy() == 0);  // can't flop into surplus
    }
    function flap(uint wad) internal {
        heal();
        sai.push(msg.sender, bid(wad));
        skr.burn(msg.sender, wad);
    }
    function bust(uint wad) public payable note {
        require(!off);
        if (wad > fog()) flop(wad);
        else flip(wad);
    }
    function boom(uint wad) public payable note {
        require(!off);
        flap(wad);
    }

    //------------------------------------------------------------------

    function cage(uint fix_) public payable note auth {
        require(!off);
        off = true;
        fix = fix_;
    }
    function cash(uint wad) public payable note {
        require(off);
        sai.burn(msg.sender, wad);
        require(tub.gem().transfer(msg.sender, rmul(wad, fix)));
    }
    function mock(uint wad) public payable note {
        require(off);
        sai.mint(msg.sender, wad);
        require(tub.gem().transferFrom(msg.sender, address(this), rmul(wad, fix)));
    }
    function vent() public payable note {
        require(off);
        skr.burn(fog());
    }
}
