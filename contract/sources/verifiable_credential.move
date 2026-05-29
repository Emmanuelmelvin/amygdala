module amygdala::verifiable_credential;

use std::string::String;
use std::option::Option;
use sui::table::{Self, Table};
use sui::clock::{Self, Clock};
use amygdala::memory_register::{Self, MemoryRegisterCap, MemoryRegister, Permission};

const ENotAuthorized: u64 = 0;
const ENameSpacePrefixNotFound: u64 = 1;
const ENamespacePermissionNotFound: u64 = 2;
const ECredentialRevoked: u64 = 3;
const ERateLimitExceeded: u64 = 4;

public struct VerifiableCredential has key, store {
    id: UID,
    registry_id: ID,
    agent_did: String,
    agent_address: address,
    permissions: vector<VerifiableCredentialPermissions>,
    ttl: Option<u64>,
    revoked: bool,
    // Configurable limit rate
    read_per_second: u64,
    // Tracks state across timestamps (in milliseconds)
    last_access_timestamp: u64,
    current_window_requests: u64,
}

public struct VerifiableCredentialPermissions has store {
    p: Table<String, Permission>,
}

public struct VerifiableCredentialCap has key, store {
    id: UID,
    credential_id: ID,
}

public fun create_credential(
    cap: &MemoryRegisterCap,
    register: &MemoryRegister,
    agent_did: String,
    agent_address: address,
    namespace_prefixes: vector<String>,
    permissions: vector<vector<Permission>>,
    ttl: Option<u64>,
    read_per_second: u64, // Inject the desired rate constraint 
    ctx: &mut TxContext
) {
    assert!(memory_register::register_id(cap) == object::id(register), ENotAuthorized);
    
    let mut j = 0;
    while (j < namespace_prefixes.length()) {
        let prefix = &namespace_prefixes[j];
        let mut i = 0;
        let mut found = false;
        while (i < register.get_namespaces().length()) {
            if (&register.get_namespace_prefix(i) == prefix) {
                found = true;
                break;
            };
            i = i + 1;
        };
        assert!(found, ENameSpacePrefixNotFound);
        j = j + 1;
    };

    let mut mut_permissions = permissions;
    let mut perms = vector[];
    let mut i = 0;
    
    while (i < namespace_prefixes.length()) {
        let mut p_table = table::new(ctx);
        let mut current_ns_permissions = mut_permissions.remove(0); 
        let prefix = &namespace_prefixes[i];

        while (!current_ns_permissions.is_empty()) {
            let permission = current_ns_permissions.remove(0);
            
            assert!(
                memory_register::has_namespace_permission(register, prefix, permission), 
                ENamespacePermissionNotFound
            );

            if (!table::contains(&p_table, *prefix)) {
                table::add(&mut p_table, *prefix, permission);
            };
        };
        
        current_ns_permissions.destroy_empty();

        let p = VerifiableCredentialPermissions { p: p_table };
        perms.push_back(p);
        i = i + 1;
    };

    let credential = VerifiableCredential {
        id: object::new(ctx),
        registry_id: memory_register::register_id(cap),
        agent_did,
        agent_address,
        permissions: perms,
        ttl,
        revoked: false,
        read_per_second,
        last_access_timestamp: 0,
        current_window_requests: 0,
    };

    let credential_cap = VerifiableCredentialCap {
        id: object::new(ctx),   
        credential_id: object::id(&credential),
    };
    
    transfer::public_transfer(credential_cap, agent_address);
    transfer::public_share_object(credential);
}

/// Call this function whenever an agent makes a memory read attempt using this credential
public fun use_credential_permission(
    credential: &mut VerifiableCredential,
    clock: &Clock
) {
    // 1. Core security checks
    assert!(!credential.revoked, ECredentialRevoked);
    
    let current_time = clock::timestamp_ms(clock);
    
    // Check if TTL has expired (if configured)
    if (credential.ttl.is_some()) {
        assert!(current_time < *credential.ttl.borrow(), ECredentialRevoked);
    };

    // 2. Compute sliding-window rate limit window (1 second = 1000 milliseconds)
    if (current_time >= credential.last_access_timestamp + 1000) {
        // Reset window tracker if the last recorded request occurred over a second ago
        credential.last_access_timestamp = current_time;
        credential.current_window_requests = 1;
    } else {
        // Still inside the current 1-second window, enforce threshold limit
        assert!(credential.current_window_requests < credential.read_per_second, ERateLimitExceeded);
        credential.current_window_requests = credential.current_window_requests + 1;
    };
}

public fun revoke_credential(
    cap: &MemoryRegisterCap,
    credential: &mut VerifiableCredential,
    _ctx: &mut TxContext
) {
    assert!(credential.registry_id == memory_register::register_id(cap), ENotAuthorized);
    credential.revoked = true;
}