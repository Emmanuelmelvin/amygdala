module amygdala::memory_register;

use std::string::String;
use sui::event;
use sui::url::{Self, Url};

public enum Permission has copy, drop, store {
    Read,
    Write,
    Delete
}

public struct Namespace has store, copy, drop {
    prefix: String,
    permissions: vector<Permission>,
}

public struct MemoryRegister has key, store {
    id: UID,
    register_id: String,
    name: String,
    description: String,
    created_by: address,
    namespaces: vector<Namespace>,
    revoked_verifiable_credentials: vector<ID>,
    created_on: u64,
    image_url: Url,
}

public struct MemoryRegisterCap has key, store {
    id: UID,
    register_id: ID,
}

public fun register_id(cap: &MemoryRegisterCap): ID {
    cap.register_id
}

public struct MemoryRegisterMarketObject has key, store {
    id: UID,
    amount_in_usdc: u64,
    seller: address,
    register: MemoryRegister,
}

public struct MemoryRegisterListedEvent has copy, drop {
    market_id: ID,
    register_id: ID,
    amount_in_usdc: u64,
    seller: address,
}

public struct MemoryRegisterCreatedEvent has copy, drop {
    register_id: ID,
    created_by: address,
}

#[allow(lint(self_transfer))]
public fun create_memory_register(
    register_id_str: String,
    name: String,
    description: String,
    clock: &sui::clock::Clock,
    ctx: &mut TxContext
) {
    let id = object::new(ctx);
    let obj_id = object::uid_to_inner(&id);

    let register = MemoryRegister {
        id,
        register_id: register_id_str,
        name,
        description,
        created_by: ctx.sender(),
        namespaces: vector[],
        revoked_verifiable_credentials: vector[],
        created_on: sui::clock::timestamp_ms(clock),
        image_url: url::new_unsafe_from_bytes(b"https://example.com/default-register-image.png"),
    };

    let cap = MemoryRegisterCap {
        id: object::new(ctx),
        register_id: obj_id,
    };

    event::emit(MemoryRegisterCreatedEvent {
        register_id: obj_id,
        created_by: ctx.sender(),
    });

    transfer::public_share_object(register);
    transfer::public_transfer(cap, ctx.sender());
}

const ENotAuthorized: u64 = 0;

public fun revoke_credentials(
    register: &mut MemoryRegister,
    cap: &MemoryRegisterCap,
    credential_ids: vector<ID>,
) {
    assert!(object::uid_to_inner(&register.id) == cap.register_id, ENotAuthorized);

    let mut i = 0;
    while (i < std::vector::length(&credential_ids)) {
        let cred_id = std::vector::borrow(&credential_ids, i);
        std::vector::push_back(&mut register.revoked_verifiable_credentials, *cred_id);
        i = i + 1;
    }
}

public fun add_namespace(
    register: &mut MemoryRegister,
    cap: &MemoryRegisterCap,
    prefix: String,
    permissions: vector<Permission>
) {
    assert!(object::uid_to_inner(&register.id) == cap.register_id, ENotAuthorized);
    let namespace = Namespace { prefix, permissions };
    std::vector::push_back(&mut register.namespaces, namespace);
}

public fun remove_namespace(
    register: &mut MemoryRegister,
    cap: &MemoryRegisterCap,
    prefix: String
) {
    assert!(object::uid_to_inner(&register.id) == cap.register_id, ENotAuthorized);
    
    let mut i = 0;
    let len = std::vector::length(&register.namespaces);
    while (i < len) {
        let ns = std::vector::borrow(&register.namespaces, i);
        if (ns.prefix == prefix) {
            std::vector::remove(&mut register.namespaces, i);
            break
        };
        i = i + 1;
    }
}

public fun update_namespace_permissions(
    register: &mut MemoryRegister,
    cap: &MemoryRegisterCap,
    prefix: String,
    new_permissions: vector<Permission>
) {
    assert!(object::uid_to_inner(&register.id) == cap.register_id, ENotAuthorized);
    
    let mut i = 0;
    let len = std::vector::length(&register.namespaces);
    while (i < len) {
        let ns = std::vector::borrow_mut(&mut register.namespaces, i);
        if (ns.prefix == prefix) {
            ns.permissions = new_permissions;
            break
        };
        i = i + 1;
    }
}

public fun list_memory_register(
    cap: MemoryRegisterCap,
    register: MemoryRegister,
    amount_in_usdc: u64,
    ctx: &mut TxContext
) {
    assert!(object::uid_to_inner(&register.id) == cap.register_id, ENotAuthorized);

    let register_id = object::id(&register);

    let market_obj = MemoryRegisterMarketObject {
        id: object::new(ctx),
        amount_in_usdc,
        seller: ctx.sender(),
        register,
    };
    
    let market_id = object::id(&market_obj);

    let MemoryRegisterCap { id, register_id: _ } = cap;
    id.delete();

    event::emit(MemoryRegisterListedEvent {
        market_id,
        register_id,
        amount_in_usdc,
        seller: ctx.sender(),
    });

    transfer::public_share_object(market_obj);
}

public struct MemoryRegisterBoughtEvent has copy, drop {
    market_id: ID,
    register_id: ID,
    amount_in_usdc: u64,
    buyer: address,
}

#[allow(lint(self_transfer, share_owned))]
public fun buy_memory_register<T>(
    market_obj: MemoryRegisterMarketObject,
    payment: sui::coin::Coin<T>,
    active_credential_ids: vector<ID>,
    ctx: &mut TxContext
) {
    let MemoryRegisterMarketObject { id, amount_in_usdc, seller, register } = market_obj;
    let market_id = object::uid_to_inner(&id);
    let register_id = object::id(&register);

    assert!(sui::coin::value(&payment) >= amount_in_usdc, ENotAuthorized); // Reusing ENotAuthorized for insufficient funds here as a stub
    transfer::public_transfer(payment, seller);
    id.delete();

    let mut register = register;
    let cap = MemoryRegisterCap {
        id: object::new(ctx),
        register_id: object::id(&register),
    };

    revoke_credentials(&mut register, &cap, active_credential_ids);

    event::emit(MemoryRegisterBoughtEvent {
        market_id,
        register_id,
        amount_in_usdc,
        buyer: ctx.sender(),
    });

    transfer::public_share_object(register);
    transfer::public_transfer(cap, ctx.sender());
}
