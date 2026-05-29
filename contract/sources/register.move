module amygdala::memory_register;

use std::string::String;
use std::option::{Self, Option};
use sui::event;
use sui::url::{Self, Url};

const ENotAuthorized: u64 = 0;
const EIndexOutOfBounds: u64 = 1;

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
    name: String,
    description: String,
    image_url: Url,
    tag: String,
    credit_count: u64,
    created_by: address,
    current_owner: address,
    last_updated_at: u64,
    last_query_at: u64,
    market_value_in_usdc: Option<u64>,
    namespaces: vector<Namespace>,
    created_on: u64,
}

public struct MemoryRegisterCap has key, store {
    id: UID,
    register_id: ID,
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

public struct NamespacePermissionsUpdatedEvent has copy, drop {
    register_id: ID,
    prefix: String,
}

public struct MemoryRegisterCreatedEvent has copy, drop {
    register_id: ID,
    created_by: address,
}

public(package) fun get_current_owner(register: &MemoryRegister): address {
    register.current_owner
}

public(package) fun get_credit_count(register: &MemoryRegister): u64 {
    register.credit_count
}

public(package) fun add_credit_count(register: &mut MemoryRegister, amount: u64) {
    register.credit_count = register.credit_count + amount;
}

public(package) fun subtract_credit_count(register: &mut MemoryRegister, amount: u64) {
    assert!(register.credit_count >= amount, ENotAuthorized);
    register.credit_count = register.credit_count - amount;
}

#[allow(lint(self_transfer))]
public fun create_memory_register(
    tag: String,
    name: String,
    image_url_bytes: vector<u8>, // Vector of raw bytes representing the image URL string
    description: String,
    clock: &sui::clock::Clock,
    ctx: &mut TxContext
) {
    let id = object::new(ctx);
    let obj_id = object::uid_to_inner(&id);

    let register = MemoryRegister {
        id,
        tag,
        name,
        description,
        created_by: ctx.sender(),
        current_owner: ctx.sender(),
        credit_count: 0,
        namespaces: vector[],
        created_on: sui::clock::timestamp_ms(clock),
        image_url: url::new_unsafe_from_bytes(image_url_bytes),
        last_updated_at: sui::clock::timestamp_ms(clock),
        last_query_at: sui::clock::timestamp_ms(clock),
        market_value_in_usdc: option::none(),
    };

    let cap = MemoryRegisterCap {
        id: object::new(ctx),
        register_id: obj_id,
    };

    event::emit(MemoryRegisterCreatedEvent {
        register_id: obj_id,
        created_by: ctx.sender()
    });

    transfer::public_share_object(register);
    transfer::public_transfer(cap, ctx.sender());
}

public(package) fun register_id(cap: &MemoryRegisterCap): ID { cap.register_id }

public(package) fun namespace_exists(register: &MemoryRegister, prefix: &String): bool {
    let mut i = 0;
    let len = register.namespaces.length();
    while (i < len) {
        if (&register.namespaces.borrow(i).prefix == prefix) return true;
        i = i + 1;
    };
    false
}

public(package) fun get_namespace_count(register: &MemoryRegister): u64 {
    register.namespaces.length()
}

public(package) fun get_namespace_prefix(register: &MemoryRegister, index: u64): String {
    assert!(index < register.namespaces.length(), EIndexOutOfBounds);
    register.namespaces.borrow(index).prefix
}

public(package) fun get_namespace_permissions(register: &MemoryRegister, prefix: &String): Option<vector<Permission>> {
    let mut i = 0;
    let len = register.namespaces.length();
    while (i < len) {
        let ns = register.namespaces.borrow(i);
        if (&ns.prefix == prefix) return option::some(ns.permissions);
        i = i + 1;
    };
    option::none()
}

public(package) fun has_namespace_permission(register: &MemoryRegister, prefix: &String, permission: Permission): bool {
    let mut i = 0;
    let len = register.namespaces.length();
    while (i < len) {
        let ns = register.namespaces.borrow(i);
        if (&ns.prefix == prefix) {
            let permissions = &ns.permissions;
            let mut j = 0;
            let p_len = permissions.length();
            while (j < p_len) {
                if (*permissions.borrow(j) == permission) return true;
                j = j + 1;
            };
        };
        i = i + 1;
    };
    false
}

public fun get_namespaces(register: &MemoryRegister): vector<Namespace> {
    register.namespaces
}

public fun add_namespace(
    register: &mut MemoryRegister,
    cap: &MemoryRegisterCap,
    prefixes: vector<String>,
    permissions: vector<vector<Permission>>
) {
    let register_uid = object::uid_to_inner(&register.id);
    assert!(register_uid == cap.register_id, ENotAuthorized);

    let mut mut_prefixes = prefixes;
    let mut mut_permissions = permissions;

    while (!mut_prefixes.is_empty()) {
        let prefix = mut_prefixes.remove(0);
        let permission_set = mut_permissions.remove(0);
        
        if (namespace_exists(register, &prefix)) {
            continue;
        };
        
        register.namespaces.push_back(Namespace { 
            prefix, 
            permissions: permission_set 
        });
    }
}

public fun update_namespace_permissions(
    register: &mut MemoryRegister,
    cap: &MemoryRegisterCap,
    prefix: String,
    new_permissions: vector<Permission>
) {
    let register_uid = object::uid_to_inner(&register.id);
    assert!(register_uid == cap.register_id, ENotAuthorized);
    
    let mut i = 0;
    let len = register.namespaces.length();
    while (i < len) {
        let ns = register.namespaces.borrow_mut(i);
        if (ns.prefix == prefix) {
            ns.permissions = new_permissions;
            event::emit(NamespacePermissionsUpdatedEvent {
                register_id: register_uid,
                prefix,
            });
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
    ctx: &mut TxContext
) {
    let MemoryRegisterMarketObject { id, amount_in_usdc, seller, mut register } = market_obj;
    let market_id = object::uid_to_inner(&id);
    let register_id = object::id(&register);

    assert!(sui::coin::value(&payment) >= amount_in_usdc, ENotAuthorized); 
    transfer::public_transfer(payment, seller);
    id.delete();

    // Dynamically update ownership of the inner struct data upon sale
    register.current_owner = ctx.sender();

    let cap = MemoryRegisterCap {
        id: object::new(ctx),
        register_id: register_id,
    };

    event::emit(MemoryRegisterBoughtEvent {
        market_id,
        register_id,
        amount_in_usdc,
        buyer: ctx.sender(),
    });

    // Share the object out again under its new ownership bounds
    transfer::public_share_object(register);
    transfer::public_transfer(cap, ctx.sender());
}