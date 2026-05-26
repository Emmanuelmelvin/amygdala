module amygdala::memory;
use std::ascii::String;
use sui::clock::Clock;
 
const ENotAuthorized: u64 = 1;
const ADMIN_PUBLIC_KEY: address = @0x997043ec15507d6f1d52c5b5396fcc9f8b0db67495dedc7d6b5927f24271f7f1;

public struct Memory has key, store {
    id: UID,
    name: String,
    description: Option<String>,
    image_url: Option<String>,
    meta_data_id: String,
    owner: address, 
    created_at: u64,
    revoked_agents: vector<address>,
}   

public struct MemoryMarketObject has key, store {
    id: UID,
    amount_in_usdc: u64,
    memory_object: Memory
}


public struct MemoryCap has key, store  {
    id: UID,
    memory_id: ID
}

public enum GrantType has copy, drop, store {
    Read,
    Write,
    ReadAndWrite
}

public struct MemoryGrant has key, store {
    id: UID,
    memory_id: ID,
    grant_type: GrantType
}

public fun create_memory(
    name: String,
    description: Option<String>,
    image_url: Option<String>,
    meta_data_id:  String,
    clock: &Clock,
    ctx: &mut TxContext
){
    let memory = Memory {
        id: object::new(ctx),
        name,
        description,
        meta_data_id,
        owner: ctx.sender(),
        created_at: clock.timestamp_ms(),
        image_url,
        revoked_agents: vector<address>[]
    };

    let memory_cap = MemoryCap {
        id: object::new(ctx),
        memory_id: object::id(&memory)
    };
    transfer::public_transfer(memory_cap, ctx.sender());
    transfer::public_share_object(memory);
}

public fun list_memory_for_sale(
    amount_in_usdc: u64,
    memory: Memory,
    memory_cap: MemoryCap,
    ctx: &mut TxContext
){
    if (memory_cap.memory_id != object::id(&memory)){
        abort ENotAuthorized;
    };

    let market = MemoryMarketObject {
        id: object::new(ctx),
        amount_in_usdc,
        memory_object: memory
    };

    transfer::public_share_object(market);
    let MemoryCap { 
        id,
        memory_id: _
    } = memory_cap;
    id.delete();
}

public fun claim_memory(
    market: MemoryMarketObject,
    ctx: &mut TxContext
){
    let MemoryMarketObject {
        id,
        amount_in_usdc: _,
        memory_object
    } = market;

    if (memory_object.owner != ctx.sender()){
        abort ENotAuthorized;
    };

    let memory_cap = MemoryCap {
        id: object::new(ctx),
        memory_id: object::id(&memory_object)
    };

    transfer::public_transfer(memory_cap, ctx.sender());
    transfer::share_object(memory_object);
    id.delete();
}

public fun delete_memory(
    memory: Memory,
    memory_cap: MemoryCap
){
    if (memory_cap.memory_id != object::id(&memory)){
        abort ENotAuthorized;
    };

    let MemoryCap {
        id: cap_id,
        memory_id: _
    } = memory_cap;
    cap_id.delete();

    let Memory {
        id: memory_id,
        name: _,
        description: _,
        image_url: _,
        meta_data_id: _,
        owner: _,
        created_at: _,
        revoked_agents: _
    } = memory;
    memory_id.delete();
}

public fun mint_grant(
    grant_type: GrantType,
    memory_cap: &MemoryCap,
    recipient: address,
    ctx: &mut TxContext
){
    let MemoryCap {
        id: _,
        memory_id
    } = memory_cap;
    let memory_id = *memory_id;
    
    let grant = MemoryGrant {
        id: object::new(ctx),
        memory_id,
        grant_type
    };

    transfer::public_transfer(grant, recipient);
}

public fun admin_release_memory(
    market: MemoryMarketObject,
    target_address: address,
    ctx: &mut TxContext
){
    if (ctx.sender() != ADMIN_PUBLIC_KEY){
        abort ENotAuthorized;
    };

    let MemoryMarketObject {
        id,
        amount_in_usdc: _,
        memory_object
    } = market;

    let memory_id = object::id(&memory_object);
    transfer::public_share_object(memory_object);

    let memory_cap = MemoryCap {
        id: object::new(ctx),
        memory_id
    };

    transfer::public_transfer(memory_cap, target_address);
    id.delete();
}