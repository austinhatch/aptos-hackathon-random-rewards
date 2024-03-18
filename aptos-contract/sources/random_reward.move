module my_management_addr::random_reward {
    use std::signer;
    use std::error;
    use std::string::{Self, String};
    use std::option::{Self, Option};
    use aptos_token_objects::collection;
    use aptos_token_objects::token;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::account;
    use aptos_framework::aptos_account;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_std::smart_vector;
    use aptos_framework::randomness;

    #[test_only]
    use aptos_std::debug::print;

    const ENO_ACCESS: u64 = 100;
    const ENOT_OWNER: u64 = 101;
    const ENO_RECEIVER_ACCOUNT: u64 = 102;
    const ENOT_ADMIN: u64 = 103;
    const ENOT_VALID_TICKET: u64 = 104;
    const ENOT_TOKEN_OWNER: u64 = 105;
    const EINALID_DATE_OVERRIDE: u64 = 106;

    #[test_only]
    const EINVALID_UPDATE: u64 = 107;

    const EMPTY_STRING: vector<u8> = b"";
    const ORGANIZATIONS_COLLECTION_NAME: vector<u8> = b"ORGANIZATIONS";

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct NYCConfig has key {
        admin: address,
        base_uri: String,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct NYCOrganization has key {
        id: String,
        name: String,
        admin: address,
        transfer_ref: object::TransferRef,
        mutator_ref: token::MutatorRef,
        extend_ref: object::ExtendRef
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct NYCEvent has key {
        id: String,
        name: String,
        start_date: u64,
        end_date: u64,
        currency: String,
        organization: Object<NYCOrganization>,
        transfer_ref: object::TransferRef,
        mutator_ref: collection::MutatorRef,
        extend_ref: object::ExtendRef
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct NYCTicket has key {
        id: String,
        ticket_type_id: String,
        event: Object<NYCEvent>,
        organization: Object<NYCOrganization>,
        attended_by: Option<address>,
        attended_at: u64,
        transfer_events: event::EventHandle<NYCTicketTransferEvent>,
        transfer_ref: object::TransferRef,
        mutator_ref: token::MutatorRef,
        extend_ref: object::ExtendRef
    }

    struct NYCTicketTransferEvent has drop, store {
        ticket_address: address,
        receiver_address: address,
        price_apt: u64, //In APT
        price: u64, //In cents. $1 = 100
        currency: String, //ISO currency code
        date: u64,
    }
    

    fun init_module(sender: &signer) {
        let base_uri = string::utf8(b"https://aptos-metadata.s3.us-east-2.amazonaws.com/baseUri/");

        let on_chain_config = NYCConfig {
            admin: signer::address_of(sender),
            base_uri
        };
        move_to(sender, on_chain_config);

        let description = string::utf8(EMPTY_STRING);
        let name = string::utf8(ORGANIZATIONS_COLLECTION_NAME);
        let uri = generate_org_uri_from_id(base_uri,string::utf8(ORGANIZATIONS_COLLECTION_NAME));

        collection::create_unlimited_collection(
            sender,
            description,
            name,
            option::none(),
            uri,
        );
    }

    entry public fun create_organization(admin: &signer, organization_id: String, organization_name: String) acquires NYCConfig {
        let nyc_config_obj = is_admin(admin);

        let uri = generate_org_uri_from_id(nyc_config_obj.base_uri, organization_id);

        let token_constructor_ref = token::create_named_token(admin, string::utf8(ORGANIZATIONS_COLLECTION_NAME), string::utf8(EMPTY_STRING), organization_id, option::none(), uri);
        let object_signer = object::generate_signer(&token_constructor_ref);
        let transfer_ref = object::generate_transfer_ref(&token_constructor_ref);
        let mutator_ref = token::generate_mutator_ref(&token_constructor_ref);
        let extend_ref = object::generate_extend_ref(&token_constructor_ref);

        object::disable_ungated_transfer(&transfer_ref);

        let organization = NYCOrganization {
            id: organization_id,
            name: organization_name,
            admin: nyc_config_obj.admin,
            transfer_ref,
            mutator_ref,
            extend_ref
        };

        move_to(&object_signer, organization);
    }

    entry public fun create_event(admin: &signer, organization: Object<NYCOrganization>, event_id: String, event_name: String, currency: String, start_date: u64, end_date: u64) acquires NYCConfig, NYCOrganization {
        let nyc_config_obj = is_admin(admin);

        let org_obj = borrow_global_mut<NYCOrganization>(object::object_address(&organization));

        let uri = generate_event_uri_from_id(nyc_config_obj.base_uri, org_obj.id, event_id);

        let collection_constructor_ref = collection::create_unlimited_collection(
            admin,
            string::utf8(EMPTY_STRING),
            event_id,
            option::none(),
            uri,
        );
        let object_signer = object::generate_signer(&collection_constructor_ref);
        let transfer_ref = object::generate_transfer_ref(&collection_constructor_ref);
        let mutator_ref = collection::generate_mutator_ref(&collection_constructor_ref);
        let extend_ref = object::generate_extend_ref(&collection_constructor_ref);

        object::disable_ungated_transfer(&transfer_ref);

        let event = NYCEvent {
            id: event_id,
            name: event_name,
            currency,
            start_date,
            end_date,
            organization,
            transfer_ref,
            mutator_ref,
            extend_ref
        };

        move_to(&object_signer, event);
    }

    entry public fun create_ticket(admin: &signer, receiver: address, event: Object<NYCEvent>, ticket_type_id: String, ticket_id: String, price_apt: u64, price: u64, date: u64)
    acquires NYCConfig, NYCEvent, NYCTicket, NYCOrganization {
        let nyc_config_obj = is_admin(admin);
        let sender_addr = signer::address_of(admin);

        if(!account::exists_at(receiver)) {
            aptos_account::create_account(receiver);
        };
        
        let event_obj = borrow_global_mut<NYCEvent>(object::object_address(&event));
        let org_obj = borrow_global_mut<NYCOrganization>(object::object_address(&event_obj.organization));


        let uri = generate_ticket_uri_from_id(nyc_config_obj.base_uri, org_obj.id, event_obj.id, ticket_type_id);


        let token_constructor_ref = token::create_named_token(admin, event_obj.id, string::utf8(EMPTY_STRING), ticket_id, option::none(), uri);
        let object_signer = object::generate_signer(&token_constructor_ref);
        let transfer_ref = object::generate_transfer_ref(&token_constructor_ref);
        let mutator_ref = token::generate_mutator_ref(&token_constructor_ref);
        let extend_ref = object::generate_extend_ref(&token_constructor_ref);

        object::disable_ungated_transfer(&transfer_ref);

        let linear_transfer_ref = object::generate_linear_transfer_ref(&transfer_ref);
        object::transfer_with_ref(linear_transfer_ref, receiver);

        let ticket = NYCTicket {
            id: ticket_id,
            event,
            ticket_type_id,
            organization: event_obj.organization,
            attended_at: 0,
            attended_by: option::none(),
            transfer_events: object::new_event_handle(&object_signer),
            transfer_ref,
            mutator_ref,
            extend_ref
        };

        move_to(&object_signer, ticket);

        let purchase_date = timestamp::now_microseconds();
        if(date > 0) {
            assert!(date < timestamp::now_microseconds(), EINALID_DATE_OVERRIDE);
            purchase_date = date;
        };

        let ticket_obj = borrow_global_mut<NYCTicket>(object::address_from_constructor_ref(&token_constructor_ref));
        event::emit_event<NYCTicketTransferEvent>(
            &mut ticket_obj.transfer_events,
            NYCTicketTransferEvent {
                ticket_address: generate_ticket_address(sender_addr, event_obj.id, ticket_id),
                receiver_address: receiver,
                price_apt,
                price,
                currency: event_obj.currency,
                date: purchase_date
            }
        );
    }

    entry fun create_random_ticket(admin: &signer, receiver: address, event: Object<NYCEvent>, ticket_types: vector<String>, ticket_id: String, price_apt: u64, price: u64, date: u64) acquires NYCConfig, NYCEvent, NYCTicket, NYCOrganization {
        is_admin(admin);
        create_random_ticket_internal(admin, receiver, event, ticket_types, ticket_id, price_apt, price, date);
    }

    /*
        Function for minting a truly random reward or ticket (Token) based on a truly random distribution
    */
    public fun create_random_ticket_internal(admin: &signer, receiver: address, event: Object<NYCEvent>, ticket_types: vector<String>, ticket_id: String, price_apt: u64, price: u64, date: u64)
    acquires NYCConfig, NYCEvent, NYCTicket, NYCOrganization {
        let nyc_config_obj = is_admin(admin);
        let sender_addr = signer::address_of(admin);

        if(!account::exists_at(receiver)) {
            aptos_account::create_account(receiver);
        };
        
        let event_obj = borrow_global_mut<NYCEvent>(object::object_address(&event));
        let org_obj = borrow_global_mut<NYCOrganization>(object::object_address(&event_obj.organization));

        //generate random ticket type
        let ticket_types_smart_vector = smart_vector::new<String>();
        smart_vector::add_all(&mut ticket_types_smart_vector, ticket_types);
        let random_ticket_type_id_idx = randomness::u64_range(0,smart_vector::length(&ticket_types_smart_vector));
        let ticket_type_id = *smart_vector::borrow(&ticket_types_smart_vector, random_ticket_type_id_idx);
        smart_vector::destroy(ticket_types_smart_vector);

        let uri = generate_ticket_uri_from_id(nyc_config_obj.base_uri, org_obj.id, event_obj.id, ticket_type_id);

        let token_constructor_ref = token::create_named_token(admin, event_obj.id, string::utf8(EMPTY_STRING), ticket_id, option::none(), uri);
        let object_signer = object::generate_signer(&token_constructor_ref);
        let transfer_ref = object::generate_transfer_ref(&token_constructor_ref);
        let mutator_ref = token::generate_mutator_ref(&token_constructor_ref);
        let extend_ref = object::generate_extend_ref(&token_constructor_ref);

        object::disable_ungated_transfer(&transfer_ref);

        let linear_transfer_ref = object::generate_linear_transfer_ref(&transfer_ref);
        object::transfer_with_ref(linear_transfer_ref, receiver);

        let ticket = NYCTicket {
            id: ticket_id,
            event,
            ticket_type_id,
            organization: event_obj.organization,
            attended_at: 0,
            attended_by: option::none(),
            transfer_events: object::new_event_handle(&object_signer),
            transfer_ref,
            mutator_ref,
            extend_ref
        };

        move_to(&object_signer, ticket);

        let purchase_date = timestamp::now_microseconds();
        if(date > 0) {
            assert!(date < timestamp::now_microseconds(), EINALID_DATE_OVERRIDE);
            purchase_date = date;
        };

        let ticket_obj = borrow_global_mut<NYCTicket>(object::address_from_constructor_ref(&token_constructor_ref));
        event::emit_event<NYCTicketTransferEvent>(
            &mut ticket_obj.transfer_events,
            NYCTicketTransferEvent {
                ticket_address: generate_ticket_address(sender_addr, event_obj.id, ticket_id),
                receiver_address: receiver,
                price_apt,
                price,
                currency: event_obj.currency,
                date: purchase_date
            }
        );
    }

    entry fun create_weighted_random_ticket(admin: &signer, receiver: address, event: Object<NYCEvent>, ticket_types: vector<String>, ticket_weights: vector<u64>, ticket_id: String, price_apt: u64, price: u64, date: u64) acquires NYCConfig, NYCEvent, NYCTicket, NYCOrganization {
        is_admin(admin);
        create_weighted_random_ticket_internal(admin, receiver, event, ticket_types, ticket_weights, ticket_id, price_apt, price, date);
    }

    /*
        Function for minting a weighted random reward or ticket (Token) based on a smart_vector of weights needing to add to 100
    */
    public fun create_weighted_random_ticket_internal(admin: &signer, receiver: address, event: Object<NYCEvent>, ticket_types: vector<String>, ticket_weights: vector<u64>, ticket_id: String, price_apt: u64, price: u64, date: u64)
    acquires NYCConfig, NYCEvent, NYCTicket, NYCOrganization {
        let nyc_config_obj = is_admin(admin);
        let sender_addr = signer::address_of(admin);

        if(!account::exists_at(receiver)) {
            aptos_account::create_account(receiver);
        };
        
        //Assert that the ticket types and weights have the same length

        let ticket_types_smart_vector = smart_vector::new<String>();
        smart_vector::add_all(&mut ticket_types_smart_vector, ticket_types);

        let ticket_weights_smart_vector = smart_vector::new<u64>();
        smart_vector::add_all(&mut ticket_weights_smart_vector, ticket_weights);


        let len_types = smart_vector::length(&ticket_types_smart_vector);
        let len_weights = smart_vector::length(&ticket_weights_smart_vector);
        assert!(len_types == len_weights, 42);

        //Get total sum of weights
        let sum = 0u64;
        let i = 0u64;

        while (i < len_weights) {
            let element = smart_vector::borrow(&ticket_weights_smart_vector, i);
            sum = sum + *element;
            i = i + 1;
        };

        smart_vector::destroy(ticket_types_smart_vector);
        smart_vector::destroy(ticket_weights_smart_vector);


        let ticket_type_id = find_winning_ticket_type(ticket_types, ticket_weights, sum);

        let event_obj = borrow_global_mut<NYCEvent>(object::object_address(&event));
        let org_obj = borrow_global_mut<NYCOrganization>(object::object_address(&event_obj.organization));

        let uri = generate_ticket_uri_from_id(nyc_config_obj.base_uri, org_obj.id, event_obj.id, ticket_type_id);

        let token_constructor_ref = token::create_named_token(admin, event_obj.id, string::utf8(EMPTY_STRING), ticket_id, option::none(), uri);
        let object_signer = object::generate_signer(&token_constructor_ref);
        let transfer_ref = object::generate_transfer_ref(&token_constructor_ref);
        let mutator_ref = token::generate_mutator_ref(&token_constructor_ref);
        let extend_ref = object::generate_extend_ref(&token_constructor_ref);

        object::disable_ungated_transfer(&transfer_ref);

        let linear_transfer_ref = object::generate_linear_transfer_ref(&transfer_ref);
        object::transfer_with_ref(linear_transfer_ref, receiver);

        let ticket = NYCTicket {
            id: ticket_id,
            event,
            ticket_type_id,
            organization: event_obj.organization,
            attended_at: 0,
            attended_by: option::none(),
            transfer_events: object::new_event_handle(&object_signer),
            transfer_ref,
            mutator_ref,
            extend_ref
        };

        move_to(&object_signer, ticket);

        let purchase_date = timestamp::now_microseconds();
        if(date > 0) {
            assert!(date < timestamp::now_microseconds(), EINALID_DATE_OVERRIDE);
            purchase_date = date;
        };

        let ticket_obj = borrow_global_mut<NYCTicket>(object::address_from_constructor_ref(&token_constructor_ref));
        event::emit_event<NYCTicketTransferEvent>(
            &mut ticket_obj.transfer_events,
            NYCTicketTransferEvent {
                ticket_address: generate_ticket_address(sender_addr, event_obj.id, ticket_id),
                receiver_address: receiver,
                price_apt,
                price,
                currency: event_obj.currency,
                date: purchase_date
            }
        );
    }
    
    fun find_winning_ticket_type( ticket_types: vector<String>, ticket_weights: vector<u64>, total_weights: u64) : String{
        let random_number = randomness::u64_range(0,total_weights);

        let ticket_types_smart_vector = smart_vector::new<String>();
        smart_vector::add_all(&mut ticket_types_smart_vector, ticket_types);

        let ticket_weights_smart_vector = smart_vector::new<u64>();
        smart_vector::add_all(&mut ticket_weights_smart_vector, ticket_weights);

        //Find a winner based on those weights
        let j = 0u64;
        let accumulated_shares = 0u64;

        while (j < smart_vector::length(&ticket_weights_smart_vector)) {
            let shares = *smart_vector::borrow(&ticket_weights_smart_vector, j);
            accumulated_shares = accumulated_shares + shares;
            
            if (accumulated_shares >= random_number) {
                let winner = *smart_vector::borrow(&ticket_types_smart_vector, j);
                smart_vector::destroy(ticket_types_smart_vector);
                smart_vector::destroy(ticket_weights_smart_vector);
                return winner

            } else{

            };
            j = j + 1;
        };
        smart_vector::destroy(ticket_types_smart_vector);
        smart_vector::destroy(ticket_weights_smart_vector);
        // Fallback or error if no winner is found
        abort(404)
    }

    entry public fun transfer_ticket(admin: &signer, receiver: address, ticket: Object<NYCTicket>, price_apt: u64, price: u64) acquires NYCConfig, NYCTicket, NYCEvent {
        is_admin(admin);

        if(!account::exists_at(receiver)) {
            aptos_account::create_account(receiver);
        };

        let ticket_obj = borrow_global_mut<NYCTicket>(object::object_address(&ticket));
        let linear_transfer_ref = object::generate_linear_transfer_ref(&ticket_obj.transfer_ref);
        object::transfer_with_ref(linear_transfer_ref, receiver);

        let event_obj = borrow_global<NYCEvent>(object::object_address(&ticket_obj.event));

        event::emit_event<NYCTicketTransferEvent>(
            &mut ticket_obj.transfer_events,
            NYCTicketTransferEvent {
                ticket_address: object::object_address(&ticket),
                receiver_address: receiver,
                price_apt,
                price,
                currency: event_obj.currency,
                date: timestamp::now_microseconds()
            }
        );
    }

    entry public fun redeem_ticket(admin: &signer, ticket: Object<NYCTicket>) acquires NYCConfig, NYCTicket {
        is_admin(admin);

        let ticket_obj = borrow_global_mut<NYCTicket>(object::object_address(&ticket));

        let owner_addr = object::owner(ticket);
        let attended_by = &mut ticket_obj.attended_by;
        option::fill(attended_by, owner_addr);
        ticket_obj.attended_at = timestamp::now_microseconds();
    }

    entry public fun update_organization_uri(admin: &signer, organization: Object<NYCOrganization>) acquires NYCConfig, NYCOrganization {
        let nyc_config_obj = is_admin(admin);

        let organization_obj = borrow_global_mut<NYCOrganization>(object::object_address(&organization));
        let uri = generate_org_uri_from_id(nyc_config_obj.base_uri, organization_obj.id);

        token::set_uri(&organization_obj.mutator_ref, uri);
    }

    entry public fun update_event_uri(admin: &signer, nyc_event: Object<NYCEvent>) acquires NYCConfig, NYCEvent, NYCOrganization {
        let nyc_config_obj = is_admin(admin);

        let event_obj = borrow_global_mut<NYCEvent>(object::object_address(&nyc_event));
        let org_obj = borrow_global<NYCOrganization>(object::object_address(&event_obj.organization));

        let uri = generate_event_uri_from_id(nyc_config_obj.base_uri, org_obj.id, event_obj.id);

        collection::set_uri(&event_obj.mutator_ref, uri);
    }

    entry public fun update_ticket_uri(admin: &signer, nyc_event: Object<NYCTicket>) acquires NYCConfig, NYCTicket, NYCEvent, NYCOrganization {
        let nyc_config_obj = is_admin(admin);
        let event_obj = borrow_global_mut<NYCEvent>(object::object_address(&nyc_event));
        let org_obj = borrow_global<NYCOrganization>(object::object_address(&event_obj.organization));
        let ticket_obj = borrow_global_mut<NYCTicket>(object::object_address(&nyc_event));
        let uri = generate_ticket_uri_from_id(nyc_config_obj.base_uri, org_obj.id, event_obj.id, ticket_obj.ticket_type_id);

        token::set_uri(&ticket_obj.mutator_ref, uri);
    }

    entry public fun update_event_name(admin: &signer, nyc_event: Object<NYCEvent>, name: String) acquires NYCConfig, NYCEvent {
        is_admin(admin);

        let event_obj = borrow_global_mut<NYCEvent>(object::object_address(&nyc_event));
        event_obj.name = name;
    }

    entry public fun update_event_start_date(admin: &signer, nyc_event: Object<NYCEvent>, start_date: u64) acquires NYCConfig, NYCEvent {
        is_admin(admin);

        let event_obj = borrow_global_mut<NYCEvent>(object::object_address(&nyc_event));
        event_obj.start_date = start_date;
    }

    entry public fun update_event_end_date(admin: &signer, nyc_event: Object<NYCEvent>, end_date: u64) acquires NYCConfig, NYCEvent {
        is_admin(admin);

        let event_obj = borrow_global_mut<NYCEvent>(object::object_address(&nyc_event));
        event_obj.end_date = end_date;
    }

    entry public fun update_organization_name(admin: &signer, organization: Object<NYCOrganization>, name: String) acquires NYCConfig, NYCOrganization {
        is_admin(admin);

        let organization_obj = borrow_global_mut<NYCOrganization>(object::object_address(&organization));
        organization_obj.name = name;
    }

    inline fun is_admin(admin: &signer): &NYCConfig {
        let admin_addr = signer::address_of(admin);
        let nyc_config_obj = borrow_global<NYCConfig>(admin_addr);
        assert!(nyc_config_obj.admin == admin_addr, error::permission_denied(ENOT_ADMIN));

        nyc_config_obj
    }

    public fun validate_ticket(event: Object<NYCEvent>, ticket: Object<NYCTicket>) acquires NYCTicket, NYCEvent {
        let ticket_obj = borrow_global<NYCTicket>(object::object_address(&ticket));
        let ticket_event_obj = borrow_global<NYCEvent>(object::object_address(&ticket_obj.event));
        let event_obj = borrow_global<NYCEvent>(object::object_address(&event));

        assert!(
            event_obj.id == ticket_event_obj.id,
            error::permission_denied(ENOT_VALID_TICKET),
        );
    }

    fun generate_org_uri_from_id(base_uri: String, id: String): String {
        let base_uri_bytes = string::bytes(&base_uri);
        let uri = string::utf8(*base_uri_bytes);
        string::append(&mut uri, id);
        string::append_utf8(&mut uri, b"/metadata.json");

        uri
    }

      fun generate_event_uri_from_id(base_uri: String, org_id: String, event_id: String): String {
        let base_uri_bytes = string::bytes(&base_uri);
        let uri = string::utf8(*base_uri_bytes);
        string::append(&mut uri, org_id);
        string::append_utf8(&mut uri, b"/");
        string::append(&mut uri, event_id);
        string::append_utf8(&mut uri, b"/metadata.json");

        uri
    }

      fun generate_ticket_uri_from_id(base_uri: String, org_id: String, event_id: String, ticket_type_id: String): String {
        let base_uri_bytes = string::bytes(&base_uri);
        let uri = string::utf8(*base_uri_bytes);
        string::append(&mut uri, org_id);
        string::append_utf8(&mut uri, b"/");
        string::append(&mut uri, event_id);
        string::append_utf8(&mut uri, b"/");
        string::append(&mut uri, ticket_type_id);
        string::append_utf8(&mut uri, b"/metadata.json");

        uri
    }

    fun generate_ticket_address(creator_address: address, event_id: String, ticket_id: String): address {
        token::create_token_address(
            &creator_address,
            &event_id,
            &ticket_id
        )
    }

    fun generate_event_address(creator_address: address, event_id: String): address {
        collection::create_collection_address(
            &creator_address,
            &event_id,
        )
    }

    fun generate_organization_address(creator_address: address, organization_id: String): address {
        token::create_token_address(
            &creator_address,
            &string::utf8(ORGANIZATIONS_COLLECTION_NAME),
            &organization_id
        )
    }

    #[view]
    fun view_organization(creator_address: address, organization_id: String): NYCOrganization acquires NYCOrganization {
        let token_address = generate_organization_address(creator_address, organization_id);
        move_from<NYCOrganization>(token_address)
    }

    #[view]
    fun view_event(creator_address: address, event_id: String): NYCEvent acquires NYCEvent {
        let collection_address = generate_event_address(creator_address, event_id);
        move_from<NYCEvent>(collection_address)
    }

    #[view]
    fun view_ticket(creator_address: address, event_id: String, ticket_id: String): NYCTicket acquires NYCTicket {
        let token_address = generate_ticket_address(creator_address, event_id, ticket_id);
        move_from<NYCTicket>(token_address)
    }

    #[test_only]
    fun init_module_for_test(creator: &signer, aptos_framework: &signer) {
        account::create_account_for_test(signer::address_of(creator));
        init_module(creator);

        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::update_global_time_for_test(1691941413632);
    }

    #[test(account = @0xFA, user = @0xFF, aptos_framework = @aptos_framework)]
    #[expected_failure]
    fun test_auth(account: &signer, aptos_framework: &signer, user: &signer) acquires NYCConfig {
        init_module_for_test(account, aptos_framework);
        aptos_account::create_account(signer::address_of(user));

        create_organization(
            user, string::utf8(b"ORG_ID"), string::utf8(b"ORG_NAME")
        );
    }

    #[test(account = @0x7a82477da5e3dc93eec06410198ae66371cc06e0665b9f97074198e85e67d53b, user = @0xFF, transfer_receiver = @0xFB, aptos_framework = @aptos_framework)]
    fun test_create_ticket(account: &signer, aptos_framework: &signer, user: &signer, transfer_receiver: address) acquires NYCConfig, NYCOrganization, NYCEvent, NYCTicket {
        init_module_for_test(account, aptos_framework);

        create_organization(
            account, string::utf8(b"OR87c35334-d43c-4208-b8dd-7adeab94a6d5"), string::utf8(b"ORG_NAME")
        );

        let account_address = signer::address_of(account);
        let organization_address = generate_organization_address(account_address, string::utf8(b"OR87c35334-d43c-4208-b8dd-7adeab94a6d5"));
        assert!(object::is_object(organization_address), 400);
        print(&token::create_token_seed(&string::utf8(ORGANIZATIONS_COLLECTION_NAME), &string::utf8(b"OR87c35334-d43c-4208-b8dd-7adeab94a6d5")));
        print(&organization_address);
        update_organization_uri(account, object::address_to_object<NYCOrganization>(organization_address));

        create_event(
            account, object::address_to_object<NYCOrganization>(organization_address), string::utf8(b"EVENT_ID"), string::utf8(b"A Test Event"), string::utf8(b"USD"),1,2
        );

        let nyc_event_address = generate_event_address(account_address, string::utf8(b"EVENT_ID"));
        create_ticket(account, signer::address_of(user), object::address_to_object<NYCEvent>(nyc_event_address),  string::utf8(b"TT_ID"), string::utf8(b"TICKET_ID_1"), 4, 45, 1);
        create_ticket(account, signer::address_of(user), object::address_to_object<NYCEvent>(nyc_event_address),  string::utf8(b"TT_ID"), string::utf8(b"TICKET_ID_2"), 4, 45, 2);
        create_ticket(account, signer::address_of(user), object::address_to_object<NYCEvent>(nyc_event_address),  string::utf8(b"TT_ID"), string::utf8(b"TICKET_ID_3"), 4, 45, 3);

        update_event_start_date(account, object::address_to_object<NYCEvent>(nyc_event_address), 3);
        update_event_end_date(account, object::address_to_object<NYCEvent>(nyc_event_address), 4);
        update_event_uri(account, object::address_to_object<NYCEvent>(nyc_event_address));

        let nyc_ticket_address = generate_ticket_address(account_address, string::utf8(b"EVENT_ID"), string::utf8(b"TICKET_ID_1"));

        assert!(object::is_owner(object::address_to_object<NYCTicket>(nyc_ticket_address), signer::address_of(user)), error::permission_denied(ENOT_TOKEN_OWNER));

        transfer_ticket(account, transfer_receiver, object::address_to_object<NYCTicket>(nyc_ticket_address), 0, 0);
        assert!(object::is_owner(object::address_to_object<NYCTicket>(nyc_ticket_address), transfer_receiver), error::permission_denied(ENOT_TOKEN_OWNER));

        redeem_ticket(account, object::address_to_object<NYCTicket>(nyc_ticket_address));

        let nyc_ticket = borrow_global<NYCTicket>(nyc_ticket_address);
        assert!(nyc_ticket.attended_at > 0, error::permission_denied(EINVALID_UPDATE));
    }
}
