module amygdala::fee;

use amygdala::amygdala::AMYGDALA;
use amygdala::memory_register::{Self as memory_register, MemoryRegister};
use sui::coin::{Self, Coin};
use sui::transfer;
use sui::tx_context::TxContext;

const ENotAdmin: u64 = 0;
const ENotOwner: u64 = 1;
const EInsufficientCredits: u64 = 2;
const ADMIN_PUBLIC_ADDRESS: address = @0x1234567890abcdef1234567890abcdef12345678;

public fun decrement_credit_count(
    register: &mut MemoryRegister,
    amount: u64,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == ADMIN_PUBLIC_ADDRESS, ENotAdmin);

    memory_register::subtract_credit_count(register, amount);
}

public fun recharge_credit_count(
    register: &mut MemoryRegister,
    amount: u64,
    payment: Coin<AMYGDALA>,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == memory_register::get_current_owner(register), ENotOwner);
    assert!(coin::value(&payment) == amount, EInsufficientCredits);

    memory_register::add_credit_count(register, amount);
    transfer::public_transfer(payment, ADMIN_PUBLIC_ADDRESS);
}