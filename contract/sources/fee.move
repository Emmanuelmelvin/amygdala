module amygdala::fee;

use amygdala::amygdala::AMYGDALA;
use amygdala::memory_register::{Self as memory_register, MemoryRegister};
use amygdala::verifiable_credential::{Self as credential, VerifiableCredential};
use sui::coin::{Self, Coin};
use sui::clock::{Clock};

// --- Error Codes ---
const ENotOwner: u64 = 0;
const EInsufficientCredits: u64 = 1;

/// A capability representing the platform agent's authority.
public struct AdminCap has key, store {
    id: UID,
}

fun init(ctx: &mut TxContext) {
    let admin_cap = AdminCap {
        id: object::new(ctx),
    };
    transfer::public_transfer(admin_cap, ctx.sender());
}

/// Executed by the Platform Agent backend. 
/// Validates rate-limits and deducts credits in one single operation.
public fun process_agent_request(
    _auth: &AdminCap,
    credential: &mut VerifiableCredential,
    register: &mut MemoryRegister,
    credit_amount: u64,
    clock: &Clock,
) {
    // 1. Enforce rate-limiting logic on the credential (updates timestamps and windows)
    credential::use_credential_permission(credential, clock);

    // 2. Deduct the operational credit cost from the register
    memory_register::subtract_credit_count(register, credit_amount);
}

/// Users/Owners call this directly to top up their registry's balance
public fun recharge_credit_count(
    register: &mut MemoryRegister,
    amount: u64,
    payment: Coin<AMYGDALA>,
    platform_address: address,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == memory_register::get_current_owner(register), ENotOwner);
    assert!(coin::value(&payment) == amount, EInsufficientCredits);

    memory_register::add_credit_count(register, amount);
    transfer::public_transfer(payment, platform_address);
}