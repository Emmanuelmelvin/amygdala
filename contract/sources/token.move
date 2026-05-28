module amygdala::amygdala {
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use std::option;

    const MAX_SUPPLY: u64 = 1_000_000_000__000_000_000;
    const EMaxSupplyReached: u64 = 0;

    public struct AMYGDALA has drop {}

    fun init(witness: AMYGDALA, ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency<AMYGDALA>(
            witness,
            9,
            b"AMY",
            b"Amygdala",
            b"Amygdala — the memory token on Sui.",
            option::none(),
            ctx,
        );
        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury_cap, tx_context::sender(ctx));
    }

    public fun mint(
        treasury_cap: &mut TreasuryCap<AMYGDALA>,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext,
    ) {
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
}