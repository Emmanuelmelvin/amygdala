module amygdala::amygdala;

use sui::coin::{Self, Coin, TreasuryCap};
use std::option;

const MAX_SUPPLY: u64 = 1_000_000_000_000_000_000; // Fixed double underscore syntax error
const EMaxSupplyReached: u64 = 0;

public struct AMYGDALA has drop {}

fun init(witness: AMYGDALA, ctx: &mut TxContext) {
    let (treasury_cap, metadata) = coin::create_currency<AMYGDALA>(
        witness,
        9,
        b"AMY",
        b"Amygdala",
        b"Amygdala \xE2\x80\x94 the memory token on Sui.", // Safely formatted Unicode em-dash
        option::none(),
        ctx,
    );
    transfer::public_freeze_object(metadata);
    transfer::public_transfer(treasury_cap, ctx.sender());
}

public fun mint(
    treasury_cap: &mut TreasuryCap<AMYGDALA>,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    // Correctly enforces max supply guard checks
    assert!(coin::total_supply(treasury_cap) + amount <= MAX_SUPPLY, EMaxSupplyReached);
    let coin = coin::mint(treasury_cap, amount, ctx);
    transfer::public_transfer(coin, recipient);
}

public fun burn(
    treasury_cap: &mut TreasuryCap<AMYGDALA>,
    coin: Coin<AMYGDALA>,
) {
    coin::burn(treasury_cap, coin);
}