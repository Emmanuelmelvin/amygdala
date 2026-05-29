module amygdala::fee;

use amygdala::amygdala::AMYGDALA;
use amygdala::memory_register::{Self as memory_register, MemoryRegister};
use sui::coin::{Self, Coin};

// --- Error Codes ---
const ENotOwner: u64 = 0;
const EInsufficientCredits: u64 = 1;

/// A capability representing the platform agent's operational authority.
public struct AdminCap has key, store {
    id: UID,
}

/// A global shared configuration object holding the trusted platform wallet address.
public struct PlatformConfig has key {
    id: UID,
    treasury_address: address,
}

fun init(ctx: &mut TxContext) {
    // 1. Create and route the AdminCap to the deployer
    let admin_cap = AdminCap {
        id: object::new(ctx),
    };
    transfer::public_transfer(admin_cap, ctx.sender());

    // 2. Create and SHARE the global config so anyone can read the correct treasury address
    let config = PlatformConfig {
        id: object::new(ctx),
        treasury_address: ctx.sender(), // Defaults to deployer, can be rotated
    };
    transfer::share_object(config);
}

/// Allows the platform admin to rotate the treasury wallet address if needed.
public fun update_treasury_address(
    _auth: &AdminCap,
    config: &mut PlatformConfig,
    new_address: address,
) {
    config.treasury_address = new_address;
}

/// Users/Owners call this to top up. 
/// It safely reads the destination wallet from the tamper-proof PlatformConfig.
public fun recharge_credit_count(
    config: &PlatformConfig, // Added read-only shared config parameter
    register: &mut MemoryRegister,
    amount: u64,
    payment: Coin<AMYGDALA>,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == memory_register::get_current_owner(register), ENotOwner);
    assert!(coin::value(&payment) == amount, EInsufficientCredits);

    memory_register::add_credit_count(register, amount);
    
    // SECURE: Funds are explicitly sent to the verified platform treasury address
    transfer::public_transfer(payment, config.treasury_address);
}